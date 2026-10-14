//
//  Medal.swift
//  ProjectApexCore
//
//  Bronze, Silver and Gold for the day, set from the solver's own
//  ranking of every legal setup.
//
//  ── WHY ────────────────────────────────────────────────────────────
//  "Rank #1 of 1" means nothing, and that is what a small field shows.
//  A medal measures you against the SETUP SPACE, not against other
//  players, so it means the same with one engineer or ten thousand.
//  It fixes the cold start that the leaderboard can't, and it gives
//  the share card a headline.
//
//  Thresholds are PERCENTILES of the legal field, not fixed gaps to the
//  optimum. The spread of lap times varies a lot from day to day
//  (budget, regulation, circuit), so "within 0.5s" would be trivial on
//  some days and impossible on others. Top 1% / 10% / 33% is equally
//  hard every day.
//
//  The targets are lap TIMES, never setups. Showing them before you
//  lock reveals nothing about which parts reach them.
//

public nonisolated enum Medal: Int, Sendable, Codable, CaseIterable, Comparable {
    case bronze = 1
    case silver
    case gold

    public static func < (a: Medal, b: Medal) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .gold: return "Gold"
        case .silver: return "Silver"
        case .bronze: return "Bronze"
        }
    }

    public var emoji: String {
        switch self {
        case .gold: return "🥇"
        case .silver: return "🥈"
        case .bronze: return "🥉"
        }
    }

    /// The next medal up, nil from Gold.
    public var next: Medal? { Medal(rawValue: rawValue + 1) }
}

public nonisolated struct DayTargets: Sendable, Equatable {

    /// Top 1%, 10% and a third of the legal field.
    public static let goldPermille = 10
    public static let silverPermille = 100
    public static let bronzePermille = 333

    /// The optimum's average lap.
    public let bestAverageLapMillis: Int
    /// An average at or under this earns the medal.
    public let goldMillis: Int
    public let silverMillis: Int
    public let bronzeMillis: Int
    /// The optimal setup's per-sector totals over all laps, same basis
    /// as SimulationResult.sectorResults.totalMillis.
    public let optimalSectorTotalsMillis: [Int]
    public let legalCount: Int

    public init(
        bestAverageLapMillis: Int,
        goldMillis: Int,
        silverMillis: Int,
        bronzeMillis: Int,
        optimalSectorTotalsMillis: [Int] = [],
        legalCount: Int = 0
    ) {
        self.bestAverageLapMillis = bestAverageLapMillis
        self.goldMillis = goldMillis
        self.silverMillis = silverMillis
        self.bronzeMillis = bronzeMillis
        self.optimalSectorTotalsMillis = optimalSectorTotalsMillis
        self.legalCount = legalCount
    }

    public func millis(for medal: Medal) -> Int {
        switch medal {
        case .gold: return goldMillis
        case .silver: return silverMillis
        case .bronze: return bronzeMillis
        }
    }

    public func medal(forAverageLapMillis average: Int) -> Medal? {
        if average <= goldMillis { return .gold }
        if average <= silverMillis { return .silver }
        if average <= bronzeMillis { return .bronze }
        return nil
    }

    /// The next medal up and how much average lap it still needs.
    /// Nil once you have Gold.
    public func nextTarget(forAverageLapMillis average: Int) -> (medal: Medal, gapMillis: Int)? {
        let current = medal(forAverageLapMillis: average)
        guard let target = current == nil ? Medal.bronze : current?.next else { return nil }
        return (target, average - millis(for: target))
    }

    /// Thresholds from a solved field.
    public static func from(_ outcome: SolverOutcome, optimalSectorTotalsMillis: [Int]) -> DayTargets {
        DayTargets(
            bestAverageLapMillis: outcome.minPossibleAverageLapMillis,
            goldMillis: outcome.entry(atPermille: goldPermille, atLeast: 1).averageLapMillis,
            silverMillis: outcome.entry(atPermille: silverPermille, atLeast: 1).averageLapMillis,
            bronzeMillis: outcome.entry(atPermille: bronzePermille, atLeast: 1).averageLapMillis,
            optimalSectorTotalsMillis: optimalSectorTotalsMillis,
            legalCount: outcome.legalCount
        )
    }

    /// Solves the day and derives its targets. Runs the exhaustive
    /// solver — call off the main thread.
    public static func compute(challenge: DailyChallenge) -> DayTargets {
        compute(challenge: challenge, outcome: ExhaustiveSolver.solve(challenge: challenge))
    }

    public static func compute(challenge: DailyChallenge, outcome: SolverOutcome) -> DayTargets {
        let optimalRun = SimulationEngine.simulate(
            setup: outcome.winner.setup,
            circuit: challenge.circuit,
            weather: challenge.weather
        )
        return from(outcome, optimalSectorTotalsMillis: optimalRun.sectorResults.map(\.totalMillis))
    }
}
