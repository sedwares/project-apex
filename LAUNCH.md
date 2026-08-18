# Project Apex — launch checklist

Everything in **Mine** is written and committed. Everything in **Yours**
needs your machine, your account, or the passage of real days.

---

## Mine — done

| Area | State |
|---|---|
| Balance (pass 6) | Middle options carry real costs, two dead options repriced, reliability curve quadratic, `sim-1.1.0` |
| Daily regulation | Generated, published, enforced client-side and in the rules, shown on the brief and in the bay |
| The engineer | `SetupAdvisor` searches every feasible change; the old symptom→swap table is deprecated |
| Debrief | "Where the lap went" measured against the optimal car, per lap, summing exactly to your gap |
| Build screen | Circuit-relative demand axes |
| Leaderboard | Public entries split from sealed setups; setups unreadable until `closesAt`; standings cached |
| Account deletion | Client queues, `functions/index.js` drains it — anonymises entries, deletes setups, profile, auth user |
| Buffer alarm | Scheduled function warns before the game goes dark |
| Notifications | Rolling week of local reminders, permission asked on the third completed day, never nags a day you've played |
| Analytics | Four events: onboarding, first submission, day-2 return, share |
| Privacy manifest | `PrivacyInfo.xcprivacy` with `CA92.1` |
| App icon | Placeholder — competent, not designed |
| Tests | `Pass6BalanceTests`, `Pass6AdvisorTests` pin every claim I've made |
| Docs | `DEPLOY.md`, `PASS6-MIGRATION.md`, this file |

---

## Yours — before submitting

### 1. Deploy the functions
```
cd ~/Desktop/ProjectApex
firebase deploy --only functions
```
Requires the **Blaze** plan — Cloud Functions won't deploy on Spark. This
is the last App Store rejection risk: without it, "Delete my engineer"
queues a request nothing ever drains.

Then verify by deleting a throwaway account and checking the
`deletionRequests` document disappears and the leaderboard row reads
`ENG-DELETED`.

### 2. Run the full balance gate
Set `APEX_FULL_BATCH=1` in the test scheme's environment, switch to
Release, widen the range in `testFullGate` to `1...180`, and run it.

Expected from my Python port: max option win rate **54%**, minimum
top-1% share **16.3%**, static-setup exploit **~64%**. If Swift disagrees
materially, trust Swift and tell me the numbers.

### 3. Replace the app icon
Mine is a bold orange apex chevron with a racing line. It's legible and
it ships, but it isn't an identity. This is the cheapest thing on the
list to outsource.

### 4. Commit
Your tree was almost entirely untracked when this started. Branch first,
then commit — none of the last two days is recoverable otherwise.

### 5. App Store Connect
Screenshots (the debrief sells the game better than the bay does),
description, age rating, and the privacy nutrition labels — which must
match `PrivacyInfo.xcprivacy`: anonymous user ID linked to identity, not
used for tracking, plus crash data if Crashlytics ships.

---

## Yours — the part that needs calendar, not effort

Several behaviours cannot be tested faster than one per day, and none of
them has ever been observed working:

- **The yesterday-reveal card.** Needs a submission, then tomorrow.
- **The streak rolling over** at midnight UTC — you're UTC-4, so a
  submission after 8pm local lands on the next challenge day.
- **A leaderboard with more than one person on it.** Rank, "Top X%",
  and the tie-break by server timestamp are all untested above n=1.
- **The sealed setup staying sealed** until `closesAt` — needs a second
  account to prove.
- **Notifications firing** at 9am local, and *not* firing on a day you
  already played.

Budget a week to ten days on TestFlight with a handful of people. Submit
after that, and expect a rejection round on privacy or deletion.

---

## Known and accepted

- **The share text has no image.** Wordle-style games are carried by a
  glanceable share artifact; ours is plain text. Worth revisiting.
- **`TelemetryTimeline` invents its own decay curves** rather than
  deriving them from the engine's real penalties. The gauges correlate
  with the result instead of being computed from it.
- **The section-time curve is convex**, which mathematically favours flat
  cars. Pass 6 fought that with balance; fixing it properly is a
  `simulationVersion` bump and belongs in 1.1.
- **No weekly meta.** Nothing yet answers "why play on day 30".
