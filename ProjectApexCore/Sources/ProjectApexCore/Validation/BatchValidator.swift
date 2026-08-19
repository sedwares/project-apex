//
//  BatchValidator.swift
//  ProjectApexCore
//
//  The diversity gate, per Phase 0 Addendum §F, recalibrated in pass 6.
//
//  Per-challenge criteria:
//    1. Spread:    the setup at the 0.5th PERCENTILE of the field is
//                  within 1.0% of the winner's average.
//                  (Pass 6: this used to check a fixed rank 20. Field
//                  sizes run from ~1,400 to ~5,800 depending on budget
//                  and regulation, so rank 20 meant a wildly different
//                  percentile from day to day and the gate failed on
//                  small fields for no design reason.)
//    2. Diversity: top-1% setups use ≥2 options in ≥4 of 8 categories.
//    3. No hard lock: at most ONE category may be effectively decided
//                  in the top-1% — or TWO on a regulated day, since the
//                  regulation is itself a deliberate forced pick and
//                  shrinks the field by roughly a third.
//
//                  "Decided" means the modal option holds >=95% of the
//                  slice, NOT that it holds 100%. The original test
//                  asked whether a second option appeared at all, which
//                  fires at 100% and passes at 97% — the same day
//                  either way. Measured over 180 days: one day locked
//                  aero/engine/gear at 100/100/100 and failed; another
//                  sat at 97/97 and passed, and a player could not have
//                  told them apart. Counting distinct options measures
//                  the tail of the distribution; counting the mode
//                  measures the choice.
//
//  Batch criteria (across all challenges):
//    4. No dominant option: no option in >58% of winning setups.
//   4b. No near-dead option: every option appears in ≥15% of top-1% setups.
//    5. Philosophy rotation: ≥4 distinct winning setup identities.
//    6. Weather sensitivity: some category's winning option varies
//       across weather types.
//    7. Cheap-option presence: the winner must use ≥2
//       cheapest-in-category options in ≥50% of challenges.
//    8. NO REUSABLE CAR (pass 6, new): no single fixed setup, played
//       unchanged every day, may average better than the 70th
//       percentile of the field.
//
//  ── WHAT FAILS THE GATE ────────────────────────────────────────────
//  Criteria 4-8 (batch) fail it. Criteria 1-3 (per-day) do not: they
//  produce a re-roll worklist instead. A day whose spread lands at
//  103bp is a day to re-draw with a nonce, not evidence that the game
//  is unbalanced, and treating it as the latter means the gate is red
//  forever. See GateResult.
//
//  Criterion 8 is the one that caught the real problem. Everything
//  above it passed comfortably while a single static build beat 88% of
//  the field on average and finished top-10% on half the days. Per-day
//  diversity metrics cannot see a cross-day exploit; you have to look
//  for it explicitly.
//
//  ── ONE SOLVE PER DAY ──────────────────────────────────────────────
//  This file briefly performed THREE exhaustive solves per challenge —
//  one in validate(), one in the static-exploit scan, one more in
//  assemble()'s option-presence loop — which tripled the runtime of the
//  existing gate test and made it look like a hang in Debug. run() now
//  solves each day exactly once and accumulates every statistic from
//  that single outcome. If you add a criterion, thread it through the
//  loop below; do not re-solve.
//

public nonisolated struct ChallengeReport: Sendable {
    public let challenge: DailyChallenge
    public let legalCount: Int
    public let winner: EvaluatedSetup
    public let winnerIdentity: SetupIdentity
    public let minPossibleAverageLapMillis: Int

    public let spreadGapBP: Int          // gap of the 0.5th-percentile setup vs winner
    public let spreadOK: Bool
    public let diverseCategoryCount: Int // categories with ≥2 options in top 1%
    public let diversityOK: Bool
    /// Categories whose modal option holds >= modalShareLockPercent of
    /// the top-1% slice, mapped to that option.
    public let lockedCategories: [EngineeringCategoryID: EngineeringOptionID]
    /// Every category's modal share of the top-1% slice, for context —
    /// a day at 94/93/91 is not flagged but is worth seeing.
    public let modalSharePercent: [EngineeringCategoryID: Int]
    public let noLockOK: Bool

    /// "aerodynamics 100%,gearRatio 97%" — the flagged categories with
    /// the number that flagged them, so the report never makes you go
    /// and look up why a day failed.
    public var lockedDescription: String {
        lockedCategories.keys
            .sorted { $0.rawValue < $1.rawValue }
            .map { "\($0.rawValue) \(modalSharePercent[$0] ?? 0)%" }
            .joined(separator: ",")
    }

    public var passed: Bool { spreadOK && diversityOK && noLockOK }

    /// A failing day doesn't have to sink the batch — the publishing job
    /// can re-roll it. Nonce 1 is the first retry.
    public var rerollHint: String? {
        passed ? nil : "re-roll \(challenge.dateKey) with nonce 1"
    }
}

/// The gate verdict, deliberately split in two.
///
/// PASS 6 (second revision): these used to be one flat list, and
/// `passed` required all of it to be empty. So a batch where every
/// balance criterion was green still went red because 9 days out of 180
/// came in at 103-156bp of spread against a 100bp target. That conflates
/// two different kinds of failure:
///
///   - `balanceFailures` are verdicts about the GAME. A dominant option,
///     a near-dead option, a car you can set once and forget - none of
///     these can be fixed by choosing different days. They need the
///     model to change. These are the gate.
///   - `dayFailures` are verdicts about ONE DAY'S DRAW. Spread,
///     diversity and category locks are properties of a particular
///     circuit / weather / budget / regulation combination. The fix is a
///     re-roll (ChallengeGenerator's `nonce`) and a republish - that is
///     publishing work, not balance work. These are a worklist.
///
/// Keeping them in one bucket means the gate can never be green while
/// any day anywhere wants re-rolling, which is both unachievable and
/// misleading: it reports a healthy game as broken.
public nonisolated struct GateResult: Sendable {
    /// Batch-wide balance verdicts. These, and only these, fail the gate.
    public let balanceFailures: [String]
    /// Per-day draws that want a re-roll before publication.
    public let dayFailures: [String]

    public var passed: Bool { balanceFailures.isEmpty }

    /// Gate green AND nothing left to re-roll. This is what a batch you
    /// are about to publish should look like; `passed` is what a batch
    /// you are about to change the model over should look like.
    public var clean: Bool { passed && dayFailures.isEmpty }

    /// Everything, for callers that want the whole picture.
    public var failures: [String] { balanceFailures + dayFailures }
}

public nonisolated struct StaticExploitReport: Sendable {
    /// The single best set-and-forget setup found across the batch.
    public let setup: PlayerSetup
    /// Mean percentile of the field it beats, playing it every day.
    /// Days where it is illegal (over budget or banned) count as 0.
    public let meanPercentile: Int
    /// How many days it finishes in the top 10%.
    public let topTenPercentDays: Int
    /// How many days it isn't even legal.
    public let illegalDays: Int
}

public nonisolated struct BatchReport: Sendable {
    public let challengeReports: [ChallengeReport]
    public let optionWinRates: [EngineeringOptionID: Int]        // percent of challenges won
    public let optionTopSharePercent: [EngineeringOptionID: Int] // presence in top 1%
    public let winningIdentities: [String: Int]
    public let weatherSensitiveCategories: [EngineeringCategoryID]
    public let cheapPresencePercent: Int
    public let staticExploit: StaticExploitReport?
    /// Day number from which a failing day can still be re-rolled.
    /// nil = every day in this batch is in the publishable future.
    ///
    /// A batch run for BALANCE deliberately covers a historical sample
    /// (days 1...180 = Jan-Jun 2026) because 30 days is too noisy to
    /// tune on. Those days cannot be re-rolled — publishing a new draw
    /// for a date that has already passed either does nothing or, once
    /// the game is live, rewrites a competition people played. Without
    /// this, the report emits a paste-ready --reroll command consisting
    /// entirely of dates you must never re-roll, which is the worst
    /// kind of wrong: confident, specific and actionable.
    public let publishableFromDayNumber: Int?
    /// dayNumber → nonce actually used for this run, so the re-roll
    /// command can advance PAST what has already been tried.
    public let appliedNonces: [Int: Int]
    /// Whether the batch (cross-day) criteria were evaluated at all.
    ///
    /// A short run — the 90-day publishing window, say — is fine for
    /// finding days that drew badly, and useless as a balance verdict:
    /// at n=90 an option's win rate carries roughly ±6 percentage points
    /// of sampling noise, which is wider than the distance between
    /// "healthy" and the 58% dominance ceiling. Running one anyway
    /// produced "⚠️ DOMINANT suspensionStiff 62%" on a window whose
    /// 180-day parent measured the same option at 52% — an alarm raised
    /// by arithmetic, not by the game.
    ///
    /// When false the criteria are neither evaluated nor rendered, so a
    /// worklist run cannot be mistaken for a verdict.
    public let batchCriteriaEvaluated: Bool
    public let gate: GateResult

    /// Whether this day is still in the re-rollable future.
    private func isPublishable(_ report: ChallengeReport) -> Bool {
        guard let floor = publishableFromDayNumber else { return true }
        guard let day = ChallengeSeed.dayNumber(fromDateKey: report.challenge.dateKey)
        else { return false }
        return day >= floor
    }

    /// Days that failed the lock check, grouped by WHICH categories
    /// locked, most common grouping first.
    ///
    /// The distinction matters: one day locking three categories is a
    /// bad draw, and a re-roll is the right answer. Five days locking
    /// the SAME three is structural - those systems are deciding
    /// themselves across a whole class of day, and re-rolling only
    /// hides it until it shows up as a stale meta.
    public var lockClusters: [(categories: String, days: Int)] {
        var counts: [String: Int] = [:]
        for report in challengeReports where !report.noLockOK {
            let key = report.lockedCategories.keys
                .map(\.rawValue).sorted().joined(separator: ",")
            counts[key, default: 0] += 1
        }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { (categories: $0.key, days: $0.value) }
    }

    /// The re-roll worklist as apex-publish arguments, ready to paste.
    /// Empty when every day's draw is fine.
    ///
    /// The nonce is the one ALREADY APPLIED plus one — not a hardcoded
    /// 1. The first version emitted `=1` for every failing day on the
    /// grounds that "the report cannot know what you already tried",
    /// which was simply untrue: `run(nonces:)` hands it the map. On the
    /// second pass that produced a confident, paste-ready command whose
    /// every argument was a no-op — republishing the exact draw that
    /// had just been rejected, and reporting success while doing it.
    /// The worst kind of wrong output is the kind that looks right.
    public var rerollArguments: String {
        challengeReports
            .filter { !$0.passed && isPublishable($0) }
            .map { report -> String in
                let day = ChallengeSeed.dayNumber(fromDateKey: report.challenge.dateKey)
                let next = (day.flatMap { appliedNonces[$0] } ?? 0) + 1
                return "--reroll \(report.challenge.dateKey)=\(next)"
            }
            .joined(separator: " ")
    }

    /// Failing days that are already in the past — reportable, but not
    /// re-rollable. Counted separately so the worklist can say so
    /// instead of quietly dropping them.
    public var unrollableDayCount: Int {
        challengeReports.filter { !$0.passed && !isPublishable($0) }.count
    }

    /// Pure-Swift right-padding (the package is Foundation-free).
    private func pad(_ text: String, to width: Int) -> String {
        if text.count >= width { return String(text.prefix(width)) }
        return text + String(repeating: " ", count: width - text.count)
    }

    public func renderText() -> String {
        var lines: [String] = []
        lines.append("═══ PROJECT APEX — VALIDATION BATCH REPORT ═══")
        let gateText = gate.passed ? "PASSED ✅" : "FAILED ❌"
        var header = "Challenges: \(challengeReports.count)   Gate: \(gateText)"
        if !gate.dayFailures.isEmpty {
            header += "   Re-roll worklist: \(gate.dayFailures.count)"
        }
        lines.append(header)
        if let staticExploit {
            lines.append(
                "Best set-and-forget car beats \(staticExploit.meanPercentile)% of the field "
                    + "(top-10% on \(staticExploit.topTenPercentDays) days, "
                    + "illegal on \(staticExploit.illegalDays))"
            )
            lines.append("  → \(CanonicalSetupEncoder.encode(staticExploit.setup))")
        }
        lines.append("")

        for report in challengeReports {
            let c = report.challenge
            let spreadFlag = report.spreadOK ? "spread✓" : "SPREAD✗(\(report.spreadGapBP)bp)"
            let diversityFlag = report.diversityOK
                ? "div✓(\(report.diverseCategoryCount))" : "DIV✗(\(report.diverseCategoryCount))"
            let lockFlag = report.noLockOK ? "lock✓" : "LOCK✗(\(report.lockedDescription))"

            let minTime = FixedPoint.formatLapTime(millis: report.minPossibleAverageLapMillis)
            var line = ""
            line += "\(c.dateKey)  "
            line += pad(c.circuit.archetype.rawValue, to: 10) + " "
            line += pad(c.weather.rawValue, to: 6) + " "
            line += "budget \(c.budget)  "
            line += pad(c.bannedOption.map { "no-\($0.rawValue)" } ?? "unrestricted", to: 24) + " "
            line += "legal \(report.legalCount)  "
            line += "min \(minTime)  "
            line += "cost \(report.winner.setup.totalCost)  "
            line += "[\(report.winnerIdentity.displayText)]  "
            line += "\(spreadFlag) \(diversityFlag) \(lockFlag)"
            lines.append(line)
            lines.append("      → \(CanonicalSetupEncoder.encode(report.winner.setup))")
        }

        lines.append("")
        lines.append("── Option health (win rate / share of top-1% setups) ──")
        for option in EngineeringOptionID.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            let win = optionWinRates[option] ?? 0
            let share = optionTopSharePercent[option] ?? 0
            var marks = ""
            if batchCriteriaEvaluated {
                if win > BatchValidator.Thresholds.maxOptionWinRatePercent { marks += "  ⚠️ DOMINANT" }
                if share < BatchValidator.Thresholds.minTopSharePercent { marks += "  ⚠️ NEAR-DEAD" }
            }
            lines.append("  \(pad(option.rawValue, to: 22)) win \(pad("\(win)%", to: 5)) top1% \(share)%" + marks)
        }

        lines.append("")
        lines.append("── Winning identities ──")
        for (identity, count) in winningIdentities.sorted(by: { $0.value > $1.value }) {
            lines.append("  \(identity): \(count)")
        }

        lines.append("")
        lines.append("Weather-sensitive categories: \(weatherSensitiveCategories.map(\.rawValue).sorted().joined(separator: ", "))")
        lines.append("Cheap-option presence (winner uses ≥2 cheapest-in-category): \(cheapPresencePercent)%")

        // Not a gate — a description. The mean sits around 70% and has
        // never been observed outside 58–78%, so a ceiling on it would
        // pass comfortably while something was wrong, which is the
        // failure mode criterion 8 was invented to fix. Printed so the
        // number is visible if it ever does move.
        lines.append("")
        lines.append("── How decided is the top 1%, per system (mean modal share) ──")
        var shareTotals: [EngineeringCategoryID: Int] = [:]
        for report in challengeReports {
            for (category, share) in report.modalSharePercent {
                shareTotals[category, default: 0] += share
            }
        }
        let dayCount = max(challengeReports.count, 1)
        for (category, total) in shareTotals.sorted(by: { $0.value > $1.value }) {
            let mean = total / dayCount
            let flag = mean >= 80 ? "  ← the track decides this one" : ""
            lines.append("  \(pad(category.rawValue, to: 20)) \(mean)%\(flag)")
        }

        lines.append("")
        if !batchCriteriaEvaluated {
            lines.append("── BATCH CRITERIA NOT EVALUATED — sample too small for a verdict ──")
            lines.append("   \(challengeReports.count) days. Balance is judged on the full")
            lines.append("   historical batch; this run exists to find days that drew badly.")
        } else if gate.passed {
            lines.append("── GATE: PASSED ✅ — batch balance criteria are green ──")
        } else {
            lines.append("── GATE FAILURES — balance, fix the model ──")
            for failure in gate.balanceFailures { lines.append("  ✗ \(failure)") }
        }

        if !gate.dayFailures.isEmpty {
            lines.append("")
            lines.append(
                "── RE-ROLL WORKLIST (\(gate.dayFailures.count) of "
                    + "\(challengeReports.count) days) — publishing, not balance ──"
            )
            for failure in gate.dayFailures { lines.append("  ↻ \(failure)") }
            lines.append("")
            let arguments = rerollArguments
            if arguments.isEmpty {
                lines.append("  Nothing to paste: all \(unrollableDayCount) failing days are in the past.")
                lines.append("  This batch is a balance SAMPLE, not the publishing window. Re-run")
                lines.append("  over the live window to get an actionable worklist.")
            } else {
                if unrollableDayCount > 0 {
                    lines.append("  (\(unrollableDayCount) further failing day(s) are in the past and omitted.)")
                }
                lines.append("  Paste into apex-publish (with --overwrite), then UPDATE rerolls.txt")
            lines.append("  to match — the register and the server must not disagree:")
                lines.append("    \(arguments)")
            }

            if let worst = lockClusters.first, worst.days >= 3 {
                lines.append("")
                lines.append("  ⚠️ \(worst.days) lock failures share the same categories: \(worst.categories)")
                lines.append("     That is a pattern, not a draw. Look at it before re-rolling.")
            }
        }
        return lines.joined(separator: "\n")
    }
}

public nonisolated enum BatchValidator {

    /// A setup identity independent of which day it was played on.
    /// Dictionaries of Hashable keys and values are Hashable, so this
    /// works directly as a dictionary key — much cheaper than building a
    /// canonical string for every setup of every day.
    typealias Selections = [EngineeringCategoryID: EngineeringOptionID]

    public enum Thresholds {
        /// Spread is measured at a percentile, not a fixed rank.
        public static let spreadPermille = 5              // 0.5%
        public static let spreadMinRank = 10
        public static let spreadMaxGapBP = 100            // 1.0%
        public static let minDiverseCategories = 4
        public static let topPercent = 1
        /// A backstop, not the drift detector.
        ///
        /// History: 60 → 58 in pass 6, on the grounds that the old limit
        /// was exactly the value the library was hitting so the gate
        /// could never warn before the problem arrived. That reasoning
        /// was right and the number was wrong — it came from a Python
        /// estimate of a 54% maximum. Swift over 540 days says the true
        /// maximum is 57% (`suspensionStiff`), ±2 at that sample size.
        /// So 58 reproduced exactly the fault it was meant to fix: one
        /// point of headroom, firing on sampling luck rather than on
        /// change. A 90-day window duly reported the same option at 62%
        /// and cried DOMINANT.
        ///
        /// 65 is roughly three standard errors above the measured
        /// maximum: it cannot be reached by noise, and a change that
        /// does reach it is real. Detecting ordinary drift is the job of
        /// `testOptionWinRatesHaveNotDrifted`, which pins every option's
        /// 540-day rate and fails on any move over 8 points. That is a
        /// far better instrument than one ceiling, because it watches
        /// all 24 options in both directions instead of only the top one
        /// in one direction.
        public static let maxOptionWinRatePercent = 65
        /// Pass 6, new: an option appearing in fewer than this share of
        /// top-1% setups is functionally dead. Measured minimum over
        /// 180 days is 16.3%.
        public static let minTopSharePercent = 15
        public static let minWinningIdentities = 4
        public static let cheapPresenceMinPercent = 50
        public static let cheapOptionsRequired = 2
        /// Pass 6, new: the set-and-forget ceiling. Was 88% before the
        /// pass, 63.6% after.
        public static let staticExploitMaxPercentile = 70
        /// A category counts as decided when its modal option holds at
        /// least this share of the top-1% slice.
        ///
        /// 95, not 100. Over 180 days the count of categories at >=95%
        /// and the count at exactly 100% differ by only about a third
        /// (69 days vs 45 with two or more), so this is not a loosening
        /// — it is the same measurement taken where it means something.
        /// Going lower gets steep fast: at >=85% almost every day has
        /// two decided categories, which is a description of the game
        /// rather than a fault in it.
        public static let modalShareLockPercent = 95
        /// Decided-category allowance, higher on regulated days.
        public static let maxLockedCategories = 1
        public static let maxLockedCategoriesRegulated = 2
    }

    // MARK: - Single challenge

    /// Validates one challenge, solving it exhaustively.
    public static func validate(challenge: DailyChallenge) -> ChallengeReport {
        report(for: challenge, outcome: ExhaustiveSolver.solve(challenge: challenge))
    }

    /// The report body, split out so `run` can reuse a solve it already
    /// performed rather than paying for a second one.
    static func report(for challenge: DailyChallenge, outcome: SolverOutcome) -> ChallengeReport {
        let winner = outcome.winner
        let identity = SetupIdentity.derive(from: VehicleBuilder.build(from: winner.setup))

        // 1. Spread, measured at a percentile of the field.
        let marker = outcome.entry(
            atPermille: Thresholds.spreadPermille, atLeast: Thresholds.spreadMinRank
        )
        let gapBP = (marker.averageLapMillis - winner.averageLapMillis)
            * FixedPoint.basisPointScale / max(winner.averageLapMillis, 1)
        let spreadOK = gapBP <= Thresholds.spreadMaxGapBP

        // 2 & 3. Top-1% option usage per category.
        //
        // COUNTS, not sets. Criterion 2 only needs to know whether a
        // second option exists, but criterion 3 needs to know how much
        // of the slice the winner holds, and a Set throws exactly that
        // away.
        let top = outcome.top(percent: Thresholds.topPercent)
        var counts: [EngineeringCategoryID: [EngineeringOptionID: Int]] = [:]
        for evaluated in top {
            for (category, option) in evaluated.setup.selectedOptions {
                counts[category, default: [:]][option, default: 0] += 1
            }
        }
        let diverseCount = counts.values.filter { $0.count >= 2 }.count
        let diversityOK = diverseCount >= Thresholds.minDiverseCategories

        var locked: [EngineeringCategoryID: EngineeringOptionID] = [:]
        var modalShare: [EngineeringCategoryID: Int] = [:]
        let sliceSize = max(top.count, 1)
        for (category, byOption) in counts {
            // Deterministic mode: highest count, ties broken by the
            // lower rawValue. Dictionary iteration order is not stable
            // across runs, so an unbroken tie would make the report
            // non-reproducible — which is exactly what this package
            // exists to avoid.
            guard let modal = byOption.max(by: {
                $0.value == $1.value ? $0.key.rawValue > $1.key.rawValue : $0.value < $1.value
            }) else { continue }
            let share = modal.value * 100 / sliceSize
            modalShare[category] = share
            if share >= Thresholds.modalShareLockPercent {
                locked[category] = modal.key
            }
        }
        let lockAllowance = challenge.bannedOption == nil
            ? Thresholds.maxLockedCategories
            : Thresholds.maxLockedCategoriesRegulated
        let noLockOK = locked.count <= lockAllowance

        return ChallengeReport(
            challenge: challenge.finalized(
                minPossibleAverageLapMillis: outcome.minPossibleAverageLapMillis
            ),
            legalCount: outcome.legalCount,
            winner: winner,
            winnerIdentity: identity,
            minPossibleAverageLapMillis: outcome.minPossibleAverageLapMillis,
            spreadGapBP: gapBP,
            spreadOK: spreadOK,
            diverseCategoryCount: diverseCount,
            diversityOK: diversityOK,
            lockedCategories: locked,
            modalSharePercent: modalShare,
            noLockOK: noLockOK
        )
    }

    // MARK: - Batch

    /// Runs the full batch and evaluates the gate. ONE exhaustive solve
    /// per day; every statistic is accumulated from that outcome.
    ///
    /// - Parameters:
    ///   - dayNumbers: 30 days is the working default and what the exit
    ///     gate uses. Widen to 1...180 in RELEASE for real tuning
    ///     decisions — at n=30 an option's win rate carries roughly ±9
    ///     percentage points of sampling noise, which is more than the
    ///     distance between "healthy" and "dominant".
    ///   - nonces: dayNumber → nonce, for days that have already been
    ///     re-rolled. Without this the gate keeps re-generating the
    ///     canonical draw of a day you replaced weeks ago, so the same
    ///     day fails forever and the worklist never shrinks. Keep the
    ///     map in `rerolls.txt` next to apex-publish, which reads the
    ///     same file — one record, two consumers.
    ///   - publishableFrom: the first day number that can still be
    ///     re-rolled, normally today. Failing days before it are still
    ///     reported but are kept out of the paste-ready command. Pass
    ///     nil only when the whole range is in the future.
    ///   - evaluateBatchCriteria: false for a run whose only job is the
    ///     per-day worklist. Suppresses criteria 4-8 entirely rather
    ///     than reporting them from a sample too small to support them.
    ///   - checkStaticExploit: criterion 8. Adds no solves, but does walk
    ///     every setup of every day to accumulate per-setup percentiles.
    public static func run(
        dayNumbers: ClosedRange<Int> = 1...30,
        nonces: [Int: Int] = [:],
        publishableFrom: Int? = nil,
        evaluateBatchCriteria: Bool = true,
        checkStaticExploit: Bool = true
    ) -> BatchReport {
        var reports: [ChallengeReport] = []
        var presence: [EngineeringOptionID: Int] = [:]
        var topTotal = 0

        // Criterion 8 accumulators, keyed by day-independent selections.
        var exploitScore: [Selections: Int] = [:]
        var exploitTopTenDays: [Selections: Int] = [:]
        var exploitLegalDays: [Selections: Int] = [:]

        for day in dayNumbers {
            // Real dateKeys, not "day-49": the report's re-roll worklist
            // is meant to be pasted into apex-publish, which is keyed by
            // date. Nonce 0 is the canonical draw, so this is identical
            // to the old behaviour for every day that hasn't been rolled.
            let challenge = ChallengeGenerator.generate(
                dayNumber: day,
                dateKey: ChallengeSeed.dateKey(forDayNumber: day),
                nonce: nonces[day] ?? 0
            )
            // The one and only solve for this day.
            let outcome = ExhaustiveSolver.solve(challenge: challenge)
            reports.append(report(for: challenge, outcome: outcome))

            // 4b. Option presence in the top 1%.
            let top = outcome.top(percent: Thresholds.topPercent)
            topTotal += top.count
            for evaluated in top {
                for option in evaluated.setup.selectedOptions.values {
                    presence[option, default: 0] += 1
                }
            }

            guard checkStaticExploit else { continue }

            // 8. Per-setup percentile for this day. `ranked` is ascending
            // by time, so index i beats (count - 1 - i) entries.
            let count = outcome.legalCount
            for (index, evaluated) in outcome.ranked.enumerated() {
                let key = evaluated.setup.selectedOptions
                let percentile = (count - 1 - index) * 100 / max(count, 1)
                exploitScore[key, default: 0] += percentile
                exploitLegalDays[key, default: 0] += 1
                if percentile >= 90 { exploitTopTenDays[key, default: 0] += 1 }
            }
        }

        let exploit = checkStaticExploit
            ? bestStaticSetup(
                score: exploitScore,
                topTenDays: exploitTopTenDays,
                legalDays: exploitLegalDays,
                dayCount: reports.count
            )
            : nil

        return assemble(
            reports: reports,
            optionPresence: presence,
            topSetupTotal: topTotal,
            staticExploit: exploit,
            publishableFrom: publishableFrom,
            evaluateBatchCriteria: evaluateBatchCriteria,
            appliedNonces: nonces
        )
    }

    /// The best set-and-forget car. Illegal days score zero — a car you
    /// cannot enter is not a car you can rely on.
    static func bestStaticSetup(
        score: [Selections: Int],
        topTenDays: [Selections: Int],
        legalDays: [Selections: Int],
        dayCount: Int
    ) -> StaticExploitReport? {
        guard dayCount > 0, !score.isEmpty else { return nil }

        var best: (key: Selections, mean: Int)?
        // Deterministic: ties resolve by canonical encoding, and the
        // encoding is only built for candidates that tie the maximum.
        for (key, total) in score {
            let mean = total / dayCount
            guard let current = best else {
                best = (key, mean)
                continue
            }
            if mean > current.mean {
                best = (key, mean)
            } else if mean == current.mean {
                let candidate = PlayerSetup(challengeId: "batch", selectedOptions: key)
                let incumbent = PlayerSetup(challengeId: "batch", selectedOptions: current.key)
                if CanonicalSetupEncoder.encode(candidate)
                    < CanonicalSetupEncoder.encode(incumbent) {
                    best = (key, mean)
                }
            }
        }
        guard let winner = best else { return nil }

        return StaticExploitReport(
            setup: PlayerSetup(challengeId: "batch", selectedOptions: winner.key),
            meanPercentile: winner.mean,
            topTenPercentDays: topTenDays[winner.key] ?? 0,
            illegalDays: dayCount - (legalDays[winner.key] ?? 0)
        )
    }

    // MARK: - Assembly

    static func assemble(
        reports: [ChallengeReport],
        optionPresence: [EngineeringOptionID: Int],
        topSetupTotal: Int,
        staticExploit: StaticExploitReport? = nil,
        publishableFrom: Int? = nil,
        evaluateBatchCriteria: Bool = true,
        appliedNonces: [Int: Int] = [:]
    ) -> BatchReport {
        let total = reports.count
        // Two buckets, not one. See GateResult.
        var balanceFailures: [String] = []
        var dayFailures: [String] = []

        for report in reports where !report.passed {
            var problems: [String] = []
            if !report.spreadOK { problems.append("spread \(report.spreadGapBP)bp > \(Thresholds.spreadMaxGapBP)bp") }
            if !report.diversityOK { problems.append("only \(report.diverseCategoryCount) diverse categories") }
            if !report.noLockOK { problems.append("decided: \(report.lockedDescription)") }
            dayFailures.append("\(report.challenge.dateKey): \(problems.joined(separator: "; "))")
        }

        // Criteria 4-8 below append to balanceFailures only when this
        // run is large enough to mean anything. The statistics are still
        // computed and returned — they are useful to look at — but they
        // do not become verdicts.
        func recordBalanceFailure(_ message: String) {
            guard evaluateBatchCriteria else { return }
            balanceFailures.append(message)
        }

        // 4. Option win rates.
        var winCounts: [EngineeringOptionID: Int] = [:]
        for report in reports {
            for option in report.winner.setup.selectedOptions.values {
                winCounts[option, default: 0] += 1
            }
        }
        let winRates = winCounts.mapValues { $0 * 100 / max(total, 1) }
        for (option, rate) in winRates.sorted(by: { $0.key.rawValue < $1.key.rawValue })
        where rate > Thresholds.maxOptionWinRatePercent {
            recordBalanceFailure("dominant option: \(option.rawValue) wins \(rate)% of challenges (max \(Thresholds.maxOptionWinRatePercent)%)")
        }

        // 4b. Near-dead options, from the presence counted during the run.
        var topShare: [EngineeringOptionID: Int] = [:]
        for option in EngineeringOptionID.allCases {
            topShare[option] = topSetupTotal > 0
                ? (optionPresence[option] ?? 0) * 100 / topSetupTotal
                : 0
        }
        for option in EngineeringOptionID.allCases.sorted(by: { $0.rawValue < $1.rawValue })
        where (topShare[option] ?? 0) < Thresholds.minTopSharePercent {
            recordBalanceFailure("near-dead option: \(option.rawValue) appears in \(topShare[option] ?? 0)% of top-1% setups (min \(Thresholds.minTopSharePercent)%)")
        }

        // 5. Winning identities.
        var identities: [String: Int] = [:]
        for report in reports {
            identities[report.winnerIdentity.displayText, default: 0] += 1
        }
        if identities.count < Thresholds.minWinningIdentities {
            recordBalanceFailure("only \(identities.count) winning identities (min \(Thresholds.minWinningIdentities))")
        }

        // 6. Weather sensitivity.
        var winnersByWeather: [EngineeringCategoryID: [Weather: Set<EngineeringOptionID>]] = [:]
        for report in reports {
            let weather = report.challenge.weather
            for (category, option) in report.winner.setup.selectedOptions {
                winnersByWeather[category, default: [:]][weather, default: []].insert(option)
            }
        }
        var sensitiveCategories: [EngineeringCategoryID] = []
        for (category, byWeather) in winnersByWeather where byWeather.count >= 2 {
            let allOptions = byWeather.values.reduce(into: Set<EngineeringOptionID>()) { $0.formUnion($1) }
            if allOptions.count >= 2 { sensitiveCategories.append(category) }
        }
        if sensitiveCategories.isEmpty {
            recordBalanceFailure("no weather-sensitive category (winning options never vary by weather)")
        }

        // 7. Cheap-option presence.
        let cheapestPerCategory: [EngineeringCategoryID: EngineeringOptionID] = {
            var result: [EngineeringCategoryID: EngineeringOptionID] = [:]
            for category in EngineeringCategoryID.allCases {
                let options = OptionLibrary.options(in: category)
                result[category] = options.min { $0.cost < $1.cost }!.id
            }
            return result
        }()
        let cheapPresenceCount = reports.filter { report in
            report.winner.setup.selectedOptions.filter { category, option in
                cheapestPerCategory[category] == option
            }.count >= Thresholds.cheapOptionsRequired
        }.count
        let cheapPresencePercent = cheapPresenceCount * 100 / max(total, 1)
        if cheapPresencePercent < Thresholds.cheapPresenceMinPercent {
            recordBalanceFailure("cheap-option presence \(cheapPresencePercent)% < \(Thresholds.cheapPresenceMinPercent)% (winners never use budget picks)")
        }

        // 8. The set-and-forget car.
        if let staticExploit, staticExploit.meanPercentile > Thresholds.staticExploitMaxPercentile {
            recordBalanceFailure(
                "reusable car: one fixed setup beats \(staticExploit.meanPercentile)% of the field "
                    + "every day (max \(Thresholds.staticExploitMaxPercentile)%) — "
                    + CanonicalSetupEncoder.encode(staticExploit.setup)
            )
        }

        return BatchReport(
            challengeReports: reports,
            optionWinRates: winRates,
            optionTopSharePercent: topShare,
            winningIdentities: identities,
            weatherSensitiveCategories: sensitiveCategories.sorted(),
            cheapPresencePercent: cheapPresencePercent,
            staticExploit: staticExploit,
            publishableFromDayNumber: publishableFrom,
            appliedNonces: appliedNonces,
            batchCriteriaEvaluated: evaluateBatchCriteria,
            gate: GateResult(balanceFailures: balanceFailures, dayFailures: dayFailures)
        )
    }
}
