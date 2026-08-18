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
exports.accountDeletion = onDocumentCreated(
  { document: "deletionRequests/{uid}", region: "us-central1" },
  async (event) => {
    const uid = event.params.uid;
    logger.info(`account deletion requested`, { uid });

    let anonymised = 0;
    let setupsDeleted = 0;

    // listDocuments() returns a reference for every leaderboards/{dateKey}
    // even though those parent documents are never written — they exist
    // only as containers for the entries/ and setups/ subcollections.
    const days = await db.collection("leaderboards").listDocuments();

    for (const day of days) {
      const entryRef = day.collection("entries").doc(uid);
      const entry = await entryRef.get();
      if (entry.exists && entry.get("displayName") !== TOMBSTONE_NAME) {
        await entryRef.update({ displayName: TOMBSTONE_NAME });
        anonymised += 1;
      }

      const setupRef = day.collection("setups").doc(uid);
      if ((await setupRef.get()).exists) {
        await setupRef.delete();
        setupsDeleted += 1;
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

    await event.data.ref.delete();

    logger.info(`account deletion complete`, {
      uid,
      daysScanned: days.length,
      anonymised,
      setupsDeleted,
    });
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
