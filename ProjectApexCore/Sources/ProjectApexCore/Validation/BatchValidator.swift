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
//    3. No hard lock: at most ONE category may lock in the top-1% —
//                  or TWO on a regulated day, since the regulation is
//                  itself a deliberate forced pick and shrinks the
//                  field by roughly a third.
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
    public let lockedCategories: [EngineeringCategoryID: EngineeringOptionID]
    public let noLockOK: Bool

    public var passed: Bool { spreadOK && diversityOK && noLockOK }

    /// A failing day doesn't have to sink the batch — the publishing job
    /// can re-roll it. Nonce 1 is the first retry.
    public var rerollHint: String? {
        passed ? nil : "re-roll \(challenge.dateKey) with nonce 1"
    }
}

public nonisolated struct GateResult: Sendable {
    public let failures: [String]
    public var passed: Bool { failures.isEmpty }
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
    public let gate: GateResult

    /// Pure-Swift right-padding (the package is Foundation-free).
    private func pad(_ text: String, to width: Int) -> String {
        if text.count >= width { return String(text.prefix(width)) }
        return text + String(repeating: " ", count: width - text.count)
    }

    public func renderText() -> String {
        var lines: [String] = []
        lines.append("═══ PROJECT APEX — VALIDATION BATCH REPORT ═══")
        let gateText = gate.passed ? "PASSED ✅" : "FAILED ❌"
        lines.append("Challenges: \(challengeReports.count)   Gate: \(gateText)")
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
            let lockedNames = report.lockedCategories.keys.map(\.rawValue).sorted().joined(separator: ",")
            let lockFlag = report.noLockOK ? "lock✓" : "LOCK✗(\(lockedNames))"

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
            if win > BatchValidator.Thresholds.maxOptionWinRatePercent { marks += "  ⚠️ DOMINANT" }
            if share < BatchValidator.Thresholds.minTopSharePercent { marks += "  ⚠️ NEAR-DEAD" }
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

        if !gate.passed {
            lines.append("")
            lines.append("── GATE FAILURES ──")
            for failure in gate.failures { lines.append("  ✗ \(failure)") }
            let rerolls = challengeReports.compactMap(\.rerollHint)
            if !rerolls.isEmpty {
                lines.append("")
                lines.append("── SUGGESTED RE-ROLLS ──")
                for hint in rerolls { lines.append("  ↻ \(hint)") }
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
        /// Pass 6: 60 → 58. The old limit was exactly the value the
        /// library was hitting, so the gate could never warn before the
        /// problem arrived. Measured max over 180 days is 54%.
        public static let maxOptionWinRatePercent = 58
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
        /// Locked-category allowance, higher on regulated days.
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
        let top = outcome.top(percent: Thresholds.topPercent)
        var optionsUsed: [EngineeringCategoryID: Set<EngineeringOptionID>] = [:]
        for evaluated in top {
            for (category, option) in evaluated.setup.selectedOptions {
                optionsUsed[category, default: []].insert(option)
            }
        }
        let diverseCount = optionsUsed.values.filter { $0.count >= 2 }.count
        let diversityOK = diverseCount >= Thresholds.minDiverseCategories

        var locked: [EngineeringCategoryID: EngineeringOptionID] = [:]
        for (category, options) in optionsUsed where options.count == 1 {
            locked[category] = options.first!
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
    ///   - checkStaticExploit: criterion 8. Adds no solves, but does walk
    ///     every setup of every day to accumulate per-setup percentiles.
    public static func run(
        dayNumbers: ClosedRange<Int> = 1...30,
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
            let challenge = ChallengeGenerator.generate(dayNumber: day, dateKey: "day-\(day)")
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
            staticExploit: exploit
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
        staticExploit: StaticExploitReport? = nil
    ) -> BatchReport {
        let total = reports.count
        var failures: [String] = []

        for report in reports where !report.passed {
            var problems: [String] = []
            if !report.spreadOK { problems.append("spread \(report.spreadGapBP)bp > \(Thresholds.spreadMaxGapBP)bp") }
            if !report.diversityOK { problems.append("only \(report.diverseCategoryCount) diverse categories") }
            if !report.noLockOK { problems.append("locked: \(report.lockedCategories.keys.map(\.rawValue).sorted().joined(separator: ","))") }
            failures.append("\(report.challenge.dateKey): \(problems.joined(separator: "; "))")
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
            failures.append("dominant option: \(option.rawValue) wins \(rate)% of challenges (max \(Thresholds.maxOptionWinRatePercent)%)")
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
            failures.append("near-dead option: \(option.rawValue) appears in \(topShare[option] ?? 0)% of top-1% setups (min \(Thresholds.minTopSharePercent)%)")
        }

        // 5. Winning identities.
        var identities: [String: Int] = [:]
        for report in reports {
            identities[report.winnerIdentity.displayText, default: 0] += 1
        }
        if identities.count < Thresholds.minWinningIdentities {
            failures.append("only \(identities.count) winning identities (min \(Thresholds.minWinningIdentities))")
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
            failures.append("no weather-sensitive category (winning options never vary by weather)")
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
            failures.append("cheap-option presence \(cheapPresencePercent)% < \(Thresholds.cheapPresenceMinPercent)% (winners never use budget picks)")
        }

        // 8. The set-and-forget car.
        if let staticExploit, staticExploit.meanPercentile > Thresholds.staticExploitMaxPercentile {
            failures.append(
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
            gate: GateResult(failures: failures)
        )
    }
}
