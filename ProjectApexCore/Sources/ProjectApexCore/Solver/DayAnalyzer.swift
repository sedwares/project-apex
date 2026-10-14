//
//  DayAnalyzer.swift
//  ProjectApexCore
//
//  Post-race analysis for one challenge: the theoretical optimum and
//  where a player's result lands in the full setup space. Runs the
//  exhaustive solver — call off the main thread.
//

public nonisolated struct DayAnalysis: Sendable, Equatable {
    public let minPossibleAverageLapMillis: Int
    public let optimalSetup: PlayerSetup
    /// Percent of all legal setups the player's average strictly beats.
    public let beatPercent: Int
    /// Player gap to the optimum in milliseconds (0 = perfect).
    public let gapToOptimalMillis: Int

    /// The optimal setup's per-sector totals across all three laps, in
    /// the same basis as SimulationResult.sectorResults.totalMillis.
    ///
    /// This exists because comparing sectors to the NEUTRAL car turned
    /// out to be meaningless. The neutral car has all twelve stats at
    /// exactly 1000 and no options at all, so a real build beats it by
    /// 3–5 s in every sector: every bar was green, every tier label read
    /// "Much faster", and FeedbackEngine's sector weakness line — which
    /// only fires on a positive gap — could never fire at all. The
    /// debrief structurally could not tell a player what went wrong.
    ///
    /// Against the optimum, a gap is always ≥ 0 and always means
    /// something: this is where your 2.4 seconds went.
    public let optimalSectorTotalsMillis: [Int]

    /// How many setups were actually in the running: the structural
    /// space MINUS everything the budget priced out.
    ///
    /// `beatPercent` has always been computed against this, but the
    /// debrief labelled it with the STRUCTURAL count (4,374 = 2 × 3^7
    /// on a regulated day). On day 230 that read "all 4374 setups"
    /// beside a percentage taken from 2,099 — two denominators on one
    /// screen. The 2,275 setups the budget excluded were never
    /// candidates and shouldn't be claimed as beaten.
    public let legalCount: Int

    /// The day's medal thresholds (v1.3). Nil only for analyses built
    /// by hand in tests.
    public let targets: DayTargets?

    /// The medal this result earned.
    public var medal: Medal? {
        targets?.medal(forAverageLapMillis: minPossibleAverageLapMillis + gapToOptimalMillis)
    }

    public init(
        minPossibleAverageLapMillis: Int,
        optimalSetup: PlayerSetup,
        beatPercent: Int,
        gapToOptimalMillis: Int,
        optimalSectorTotalsMillis: [Int] = [],
        legalCount: Int = 0,
        targets: DayTargets? = nil
    ) {
        self.minPossibleAverageLapMillis = minPossibleAverageLapMillis
        self.optimalSetup = optimalSetup
        self.beatPercent = beatPercent
        self.gapToOptimalMillis = gapToOptimalMillis
        self.optimalSectorTotalsMillis = optimalSectorTotalsMillis
        self.legalCount = legalCount
        self.targets = targets
    }
}

public nonisolated enum DayAnalyzer {

    /// `outcome` lets a caller that already solved the day (the bay
    /// solves it for the medal targets) skip a second 6,561-setup run.
    public static func analyze(
        challenge: DailyChallenge,
        playerAverageLapMillis: Int,
        outcome solved: SolverOutcome? = nil
    ) -> DayAnalysis {
        let outcome = solved ?? ExhaustiveSolver.solve(challenge: challenge)
        let slowerCount = outcome.ranked.lazy
            .filter { $0.averageLapMillis > playerAverageLapMillis }
            .count
        let beat = slowerCount * 100 / max(outcome.legalCount, 1)

        // One extra full simulation on top of the solve — immaterial,
        // and it gives the debrief a comparison target that actually
        // varies. DayTargets runs it and keeps the sector totals.
        let targets = DayTargets.compute(challenge: challenge, outcome: outcome)

        return DayAnalysis(
            minPossibleAverageLapMillis: outcome.minPossibleAverageLapMillis,
            optimalSetup: outcome.winner.setup,
            beatPercent: beat,
            gapToOptimalMillis: playerAverageLapMillis - outcome.minPossibleAverageLapMillis,
            optimalSectorTotalsMillis: targets.optimalSectorTotalsMillis,
            legalCount: outcome.legalCount,
            targets: targets
        )
    }
}
