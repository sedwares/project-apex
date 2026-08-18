# Project Apex — proposed changes (pass 6)

Every file here mirrors its path in the repo. Nothing in `ProjectApex/` or
`ProjectApexCore/` has been modified — copy a file over its original when you
want that change, and delete the rest.

**Why a sibling folder rather than `Foo.new.swift` next to the original:** the
Xcode project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16 buildable
folders), so any `.swift` file dropped inside `ProjectApex/` or
`ProjectApexCore/Sources/` is added to the target automatically. A `.new.swift`
sibling would have compiled alongside the original and broken the build with
duplicate declarations before you could read it.

**None of this has been compiled.** There is no Swift toolchain where these were
written. Treat it as a reviewed patch, not a tested one: build in Xcode, run
`swift test` on ProjectApexCore, and expect to fix small things.

---

## What's here

### Core — balance (sim-1.1.0)

| File | Change |
|---|---|
| `Engineering/OptionLibrary.swift` | Middle options carry real downsides; `engineEfficient` 7→5 cr with a cooling role; `aeroLowDrag` 16→13 cr with sharper top-end; `minimumTotalCost(banned:)` added |
| `Simulation/SimulationEngine.swift` | Reliability penalty is quadratic (divisor 4, cap 8 s), matching heat; `averageLapMillis(setup:circuit:weather:)` added for the advisor's hot path |
| `Hashing/ResultHasher.swift` | `simulationVersion` → `"sim-1.1.0"` |

### Core — the daily technical regulation

| File | Change |
|---|---|
| `Challenge/DailyChallenge.swift` | `bannedOption`, `regulationText`, `isSatisfiable` |
| `Challenge/ChallengeGenerator.swift` | Draws the regulation **last** so every day keeps the circuit/weather/budget it already had; `nonce` parameter for re-rolling a day that fails the gate |
| `Challenge/ChallengeSeed.swift` | `rng(forDayNumber:nonce:)` — nonce 0 reproduces the old seed exactly |
| `Engineering/SetupValidator.swift` | `.bannedOption` error case; `validate(_:challenge:)` convenience |
| `Solver/SetupEnumerator.swift` | Never emits banned options; `setupCount(banned:)` |
| `Solver/ExhaustiveSolver.swift` | Respects the regulation; `entry(atPermille:)` for the recalibrated spread gate |

### Core — the engineer

| File | Change |
|---|---|
| `Feedback/SetupAdvisor.swift` | **New.** Searches every feasible single and funded two-category change (≤128 sims) and returns the genuinely fastest, with the funding source named |
| `Feedback/FeedbackEngine.swift` | `generate(result:challenge:)` uses the advisor; old fixed-swap `nextTestSuggestion` deprecated but kept so existing tests compile; duplicate `reportText` collapsed to one implementation; briefing mentions the regulation |

### Core — the preview and the gate

| File | Change |
|---|---|
| `Track/Circuit.swift` | `statDemandBP` (time-weighted stat demand) and `decidingStats(limit:)` |
| `Vehicle/VehicleProfile.swift` | `from(setup:circuit:)` — today's four deciding stats with their share of the lap; fixed-axis version kept for the Test Lab |
| `Validation/BatchValidator.swift` | Spread measured at the 0.5th percentile instead of rank 20; dominance limit 60→58%; new near-dead-option criterion; **new criterion 8: no reusable static setup**; default batch 30→180 days; re-roll hints |

### App

| File | Change |
|---|---|
| `Services/LeaderboardService.swift` | Setups written to a separate sealed `setups/{uid}` document; standings cached for 2 min with a `force` bypass |
| `Services/DailyChallengeService.swift` | Maps `bannedOption`; shared `ChallengeCache`; new `CachedOfficialChallengeService` |
| `Services/AccountDeletionService.swift` | **New.** In-app deletion path (App Store 5.1.1(v)) |
| `Features/Daily/DailyViewModel.swift` | Regulation handling, circuit-relative preview, async advisor, banned-aware submit gating |
| `Features/Daily/DailyCoordinator.swift` | Yesterday reveal reads the **cached official document**, not a local regeneration; refuses unsatisfiable days |
| `Features/Daily/EngineeringBayView.swift` | Demand axes with "% of this lap"; banned options struck through and disabled; regulation banner |
| `PrivacyInfo.xcprivacy` | **New.** Declares `CA92.1` for UserDefaults + collected data types |
| `Assets.xcassets/AppIcon.appiconset/` | **New.** 1024 light/dark/tinted PNGs + updated `Contents.json` |

### Backend

| File | Change |
|---|---|
| `ProjectApexCore/backend/firestore.rules` | Public entries no longer carry `selections`; sealed `setups/` gated on `closesAt`; regulation enforced server-side; player + setup deletion for account deletion; `deletionRequests` queue |

---

## Order to apply

The balance changes and the version bump have to land together — a `sim-1.1.0`
client against `sim-1.0.0` documents shows "Update required" for everyone, and
the reverse silently produces wrong lap times.

1. **Core, all at once.** Copy the Core files, bump the version, run
   `swift test`. Expect `FeedbackEngineTests` and any test asserting exact lap
   times to fail — the numbers moved deliberately. `nextTestSuggestion` tests
   still pass (the function is unchanged, just deprecated).
2. **Run the gate.** `BatchValidator.run()` now defaults to 180 days and takes
   noticeably longer. Criterion 8 is the one to watch. Expected shape from the
   Python port: max option win rate 54%, minimum top-1% share 16.3%, static
   exploit ~64%, 11/180 spread failures and 5/180 lock failures — those 16 days
   want re-rolling with `nonce: 1`.
3. **App layer.** Then the views and services.
4. **Rules and publishing job last**, and in this order: deploy the rules, then
   ship the client. The new rules reject a client that still writes `selections`
   into the public entry, so the old build breaks the moment the rules land —
   if you need zero downtime, deploy a permissive intermediate ruleset that
   accepts both shapes, ship the client, then tighten.

The publishing job needs two additions: write `bannedOption` (empty string when
unrestricted) into the challenge document, and assert `challenge.isSatisfiable`
before publishing.

---

## What I could not verify

- **None of it compiles here.** No Swift toolchain. Type errors are likely in the
  view code especially.
- **The balance numbers come from a Python port**, not from your Core. The port
  reproduces your documented invariants (62/135 cost bounds, 95.000 s reference
  lap, baseline perf exactly 1000) but a port is not the thing itself. Trust
  `BatchValidator` over anything in this document.
- **The app icon is a placeholder** — a competent one that unblocks submission,
  not a designed identity. Replace it before you care about the App Store
  listing.
- **The Cloud Function that drains `deletionRequests`** is not written. The rules
  and the client half are here; the function that anonymises leaderboard rows
  and deletes the auth user still needs writing.
- **Notification scheduling and analytics events** from the roadmap are not
  implemented — they were not part of what you asked me to write.
