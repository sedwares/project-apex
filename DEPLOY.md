# Deploying the backend

Everything the game needs server-side lives in two files under
`ProjectApexCore/backend/`. `firebase.json` at the repo root points the
CLI at them, and `.firebaserc` pins the project so you never deploy to
the wrong one by accident.

From the repo root:

```
firebase deploy --only firestore:rules,firestore:indexes
```

**Do not run `firebase init`.** It offers to create `firestore.rules`
and will happily overwrite the real ruleset with a starter template that
allows nothing. The two config files here are all `init` would have
produced, minus that risk.

Indexes deploy asynchronously — the command returns before they finish
building. Until they're ready the four aggregate COUNT queries behind
Global Standing fail with "the query requires an index", which looks
identical to a rules rejection from inside the app. Check the Firestore
console's Indexes tab shows **Enabled** rather than Building before
concluding anything about the leaderboard.

## Deploying the functions

This section did not exist until 2026-09-17, which is how the account
deletion function reached three launch-readiness reviews undeployed.
LAUNCH.md mentioned it; this file — the one you actually reread — did
not.

```
firebase deploy --only functions
```

Deploys both, from `functions/index.js`:

- **accountDeletion** — drains `deletionRequests/{uid}`. App Store
  guideline 5.1.1(v). If this is not deployed, in-app deletion queues a
  request that nothing ever acts on, and the app tells the player their
  account is gone. That is the single largest rejection risk in the
  project and it fails silently.
- **deletionRequestSweeper** — hourly backstop for a deletion event that
  was never delivered. New in build 22; confirm it appears in the
  deployed list, because its whole job is to cover the case where the
  trigger did not run.
- **publishBufferAlarm** — daily, 09:00 UTC.

First deploy also enables Cloud Build, Artifact Registry and Cloud Run
on the project and takes a few minutes. Node 22, pinned in both
`firebase.json` and `functions/package.json`.

**`publishBufferAlarm` logs an error nobody is subscribed to.** Create a
log-based alert on:

```
severity=ERROR AND resource.labels.function_name="publishBufferAlarm"
```

An alarm with no subscriber is the same as no alarm, and the comment in
the function says as much: the failure "arrives on a day nobody happens
to be looking".

### Verifying deletion actually works

Deploying is not verifying. Delete a throwaway account in-app, then
check all five, in order:

1. `deletionRequests/{uid}` is gone.
2. That uid's leaderboard entry reads `displayName: "ENG-DELETED"`.
3. Its `leaderboards/{dateKey}/setups/{uid}` documents are gone.
4. The `players/{uid}` profile is gone.
5. **Delete the app, reinstall, and confirm a different callsign.**
   Before build 22 the iOS keychain restored the same anonymous
   identity, so a reinstall was the same engineer. This is the newest
   code path and has no automated test behind it.

## Publishing challenges

```
cd ProjectApexCore
swift run -c release apex-publish \
    --project project-apex-prod \
    --start $(date -u +%F) \
    --days 60 \
    --token "$(gcloud auth print-access-token)"
```

`-c release` is not optional in practice: each day runs a full
exhaustive solve, which takes ~40ms in release and minutes in debug.

Add `--overwrite` only when existing days must be **replaced** — a
simulation version bump, or a new document field. The default skips days
that already exist, which is correct for topping up the future and wrong
for a migration: a plain rerun prints "already published" for every day
and changes nothing, which reads exactly like success.

## The buffer

The last published day is the day the game stops working. When the
buffer runs out every player sees "Paddock unreachable" — there is no
degraded mode, because the client will not generate a challenge itself
(Decision 4).

`apex-publish` prints the buffer on every run. Re-publish well before it
reaches single digits, and put a calendar reminder somewhere that isn't
your memory.

## Verifying a published day

```
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://firestore.googleapis.com/v1/projects/project-apex-prod/databases/(default)/documents/challenges/$(date -u +%F)" \
  | grep -E 'simulationVersion|bannedOption|opensAt' -A 1
```

Both `simulationVersion` and `bannedOption` must be present and current.
A missing `bannedOption` denies **every** submission for that day: the
security rules dereference it, and in Firestore rules reading an absent
field raises an error that evaluates the whole condition to false.
