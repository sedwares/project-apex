//
//  index.js
//  Project Apex — Cloud Functions
//
//  Two jobs, both of which exist because the client cannot do them:
//
//  1. accountDeletion — App Store guideline 5.1.1(v). The client queues
//     a request; this drains it with admin credentials.
//  2. publishBufferAlarm — the last published day is the day the game
//     stops working, and nothing else would tell you it was coming.
//

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

/** Callsign shown in place of a deleted player's name. */
const TOMBSTONE_NAME = "ENG-DELETED";

// ─────────────────────────────────────────────────────────────────────
// Account deletion
// ─────────────────────────────────────────────────────────────────────

/**
 * Drains `deletionRequests/{uid}`.
 *
 * Why a function at all: the client genuinely cannot finish this job.
 * Leaderboard entries are create-only by design — letting a client
 * delete one would silently re-rank everyone who finished behind it and
 * corrupt a completed competition — and a collection-group query over
 * `setups` is doubly impossible from the client (documentID() needs a
 * full path in a group query, and the rules only match the concrete
 * `leaderboards/{dateKey}/setups/{uid}` path, not the group).
 *
 * So entries are ANONYMISED rather than removed: the row and its lap
 * time stay, the identity goes. The callsign is derived from the uid and
 * carries no personal data once the profile and auth user are gone, and
 * the day's results remain honest for everyone who played it.
 */
/**
 * Anonymises one player's leaderboard rows and deletes their sealed
 * setups, profile and auth user, then removes the request.
 *
 * ── IDEMPOTENT ON PURPOSE ──────────────────────────────────────────
 * Every step is safe to repeat: entries are skipped once already
 * tombstoned, setups and the profile are delete-if-exists, and an
 * already-deleted auth user is tolerated. That is what makes both the
 * retry path and the sweeper below safe.
 *
 * Returns a summary so callers can log it.
 */
async function drainDeletionRequest(uid, requestRef) {
  let anonymised = 0;
  let setupsDeleted = 0;

  // listDocuments() returns a reference for every leaderboards/{dateKey}
  // even though those parent documents are never written — they exist
  // only as containers for the entries/ and setups/ subcollections.
  const days = await db.collection("leaderboards").listDocuments();

  // ── WHY THIS IS BATCHED ───────────────────────────────────────────
  // This used to be a serial for-loop doing two awaited get()s per day.
  // At a few hundred published days that is several hundred sequential
  // round trips, which starts brushing the function timeout — and a
  // deletion that times out half way is exactly the failure this whole
  // file exists to avoid. Bounded concurrency keeps it flat without
  // opening an unbounded number of connections.
  const CONCURRENCY = 25;
  for (let i = 0; i < days.length; i += CONCURRENCY) {
    const slice = days.slice(i, i + CONCURRENCY);
    const results = await Promise.all(
      slice.map(async (day) => {
        const entryRef = day.collection("entries").doc(uid);
        const setupRef = day.collection("setups").doc(uid);
        const [entry, setup] = await Promise.all([
          entryRef.get(),
          setupRef.get(),
        ]);

        let didAnonymise = false;
        if (entry.exists && entry.get("displayName") !== TOMBSTONE_NAME) {
          await entryRef.update({ displayName: TOMBSTONE_NAME });
          didAnonymise = true;
        }
        let didDeleteSetup = false;
        if (setup.exists) {
          await setupRef.delete();
          didDeleteSetup = true;
        }
        return { didAnonymise, didDeleteSetup };
      })
    );
    for (const r of results) {
      if (r.didAnonymise) anonymised += 1;
      if (r.didDeleteSetup) setupsDeleted += 1;
    }
  }

  await db.collection("players").doc(uid).delete().catch(() => {});

  // The auth user last: if anything above threw, the request document
  // survives and a retry can finish the job. Deleting the user first
  // would strand the data with no uid left to find it by.
  try {
    await admin.auth().deleteUser(uid);
  } catch (error) {
    // Already gone (the client deletes it too, best-effort) is fine.
    if (error.code !== "auth/user-not-found") throw error;
  }

  // Only now: the request is the record that work is outstanding, so it
  // is removed last and only on a clean pass.
  await requestRef.delete();

  return { daysScanned: days.length, anonymised, setupsDeleted };
}

/**
 * Drains `deletionRequests/{uid}` when the request is created.
 *
 * Why a function at all: the client genuinely cannot finish this job.
 * Leaderboard entries are create-only by design — letting a client
 * delete one would silently re-rank everyone who finished behind it and
 * corrupt a completed competition — and a collection-group query over
 * `setups` is doubly impossible from the client (documentID() needs a
 * full path in a group query, and the rules only match the concrete
 * `leaderboards/{dateKey}/setups/{uid}` path, not the group).
 *
 * So entries are ANONYMISED rather than removed: the row and its lap
 * time stay, the identity goes. The callsign is derived from the uid and
 * carries no personal data once the profile and auth user are gone, and
 * the day's results remain honest for everyone who played it.
 *
 * ── retry: true IS LOAD-BEARING ────────────────────────────────────
 * Without it, Firebase drops a failed event and nothing ever retries.
 * The request document is no safety net on its own: it only fires
 * onDocumentCreated on CREATE, the rules are create-only
 * (`allow update, delete: if false`), and the client is therefore
 * forbidden from rewriting it to trigger a second attempt. One
 * transient Firestore error and the request sat there forever while the
 * player had been told their account was gone.
 *
 * timeoutSeconds is raised for the same reason: a deletion cut off by
 * the default 60s would leave exactly that stuck state.
 */
exports.accountDeletion = onDocumentCreated(
  {
    document: "deletionRequests/{uid}",
    region: "us-central1",
    retry: true,
    timeoutSeconds: 540,
  },
  async (event) => {
    const uid = event.params.uid;
    logger.info(`account deletion requested`, { uid });
    const summary = await drainDeletionRequest(uid, event.data.ref);
    logger.info(`account deletion complete`, { uid, ...summary });
  }
);

/**
 * The backstop.
 *
 * `retry: true` above covers an attempt that THREW. It does not cover
 * an event that was never delivered — a deploy mid-write, an outage,
 * exhausted retries — and in those cases the request document is
 * unreachable: create-only rules mean the client cannot re-queue it,
 * and onDocumentCreated will never fire for a document that already
 * exists. Without this sweeper those requests are stranded silently,
 * which for a privacy feature means a player who asked to be erased and
 * was told it happened.
 *
 * Runs hourly and drains anything that has been waiting more than
 * fifteen minutes, which is long enough that it never races a delivery
 * still in progress. Idempotent, so overlapping with one is harmless
 * anyway.
 */
exports.deletionRequestSweeper = onSchedule(
  {
    schedule: "7 * * * *",
    timeZone: "UTC",
    region: "us-central1",
    timeoutSeconds: 540,
  },
  async () => {
    const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - 15 * 60 * 1000);
    const stale = await db
      .collection("deletionRequests")
      .where("requestedAt", "<=", cutoff)
      .limit(50)
      .get();

    if (stale.empty) {
      logger.info("deletion sweeper: nothing outstanding");
      return;
    }

    logger.error(
      `deletion sweeper: ${stale.size} request(s) were not drained by the ` +
        `trigger and are being completed here`,
      { uids: stale.docs.map((d) => d.id) }
    );

    for (const doc of stale.docs) {
      try {
        const summary = await drainDeletionRequest(doc.id, doc.ref);
        logger.info(`account deletion completed by sweeper`, {
          uid: doc.id,
          ...summary,
        });
      } catch (error) {
        // Keep going: one stuck uid must not block the rest, and the
        // request survives for the next hourly pass.
        logger.error(`deletion sweeper failed for ${doc.id}`, error);
      }
    }
  }
);

// ─────────────────────────────────────────────────────────────────────
// Publish buffer alarm
// ─────────────────────────────────────────────────────────────────────

/** UTC yyyy-MM-dd, matching the client's dateKey format exactly. */
function utcDateKey(date) {
  return date.toISOString().slice(0, 10);
}

/**
 * Warns before the game goes dark.
 *
 * The client refuses to generate a challenge itself (Decision 4), so
 * there is no degraded mode: the day after the last published document,
 * every player gets "Paddock unreachable". apex-publish prints the
 * buffer on every run, but nothing watches it between runs — and the
 * failure arrives on a day nobody happens to be looking.
 *
 * Errors (rather than warns) under a week so it surfaces in alerting
 * rather than only in logs.
 */
exports.publishBufferAlarm = onSchedule(
  { schedule: "0 9 * * *", timeZone: "UTC", region: "us-central1" },
  async () => {
    const today = utcDateKey(new Date());

    const furthest = await db
      .collection("challenges")
      .orderBy(admin.firestore.FieldPath.documentId(), "desc")
      .limit(1)
      .get();

    if (furthest.empty) {
      logger.error("NO CHALLENGES PUBLISHED AT ALL — the game is down.");
      return;
    }

    const lastKey = furthest.docs[0].id;
    const days = Math.round(
      (Date.parse(`${lastKey}T00:00:00Z`) - Date.parse(`${today}T00:00:00Z`)) /
        86400000
    );

    const detail = { lastPublished: lastKey, bufferDays: days };
    if (days < 0) {
      logger.error(`GAME IS DOWN: last published day was ${lastKey}.`, detail);
    } else if (days <= 7) {
      logger.error(`Publish buffer critical: ${days} days left.`, detail);
    } else if (days <= 21) {
      logger.warn(`Publish buffer low: ${days} days left.`, detail);
    } else {
      logger.info(`Publish buffer healthy: ${days} days.`, detail);
    }
  }
);
