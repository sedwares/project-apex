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
