//
//  ExhaustiveSolver.swift
//  ProjectApexCore
//
//  Simulates every legal setup for a challenge and ranks the results.
//  Uses the lean engine path (runLaps) rather than full simulate() —
//  no sector baselines, hashing, or identity work in the hot loop.
//  Deterministic: ties broken by canonical setup encoding.
//

public nonisolated struct EvaluatedSetup: Hashable, Sendable {
    public let setup: PlayerSetup
    public let averageLapMillis: Int
    public let fastestLapMillis: Int
}

public nonisolated struct SolverOutcome: Sendable {
    /// All legal setups, ranked best (lowest average) first.
    public let ranked: [EvaluatedSetup]
    public let legalCount: Int

    public var winner: EvaluatedSetup { ranked[0] }
    /// Exact minimum achievable average lap — feeds
    /// DailyChallenge.minPossibleAverageLapMillis and the leaderboard
    /// sanity check.
    public var minPossibleAverageLapMillis: Int { ranked[0].averageLapMillis }

    /// The top fraction of the field (at least `atLeast` entries).
    public func top(percent: Int, atLeast: Int = 10) -> ArraySlice<EvaluatedSetup> {
        let count = max(atLeast, legalCount * percent / 100)
        return ranked.prefix(min(count, ranked.count))
    }

    /// The entry at a given permille of the field, floored at `atLeast`
    /// entries in. Used by the spread gate, which must not be a fixed
    /// rank: field sizes range from ~1,400 to ~5,800 depending on
    /// budget and regulation, so "rank 20" means a wildly different
    /// percentile from day to day.
    public func entry(atPermille permille: Int, atLeast: Int = 10) -> EvaluatedSetup {
        let index = max(atLeast, legalCount * permille / 1_000) - 1
        return ranked[min(max(index, 0), ranked.count - 1)]
    }
}

public nonisolated enum ExhaustiveSolver {

    public static func solve(challenge: DailyChallenge) -> SolverOutcome {
        var evaluated: [EvaluatedSetup] = []
        evaluated.reserveCapacity(SetupEnumerator.setupCount(banned: challenge.bannedOption))

        SetupEnumerator.forEachSetup(
            challengeId: challenge.id,
            banned: challenge.bannedOption
        ) { setup in
            guard setup.totalCost <= challenge.budget else { return }
            let stats = challenge.weather.apply(to: VehicleBuilder.build(from: setup))
            let run = SimulationEngine.runLaps(
                stats: stats, circuit: challenge.circuit, weather: challenge.weather
            )
            let times = run.laps.map(\.timeMillis)
            evaluated.append(EvaluatedSetup(
                setup: setup,
                averageLapMillis: times.reduce(0, +) / times.count,
                fastestLapMillis: times.min() ?? 0
            ))
        }

        precondition(
            !evaluated.isEmpty,
            "no legal setups — budget below the regulated minimum cost? "
                + "Check DailyChallenge.isSatisfiable before publishing."
        )

        evaluated.sort { a, b in
            if a.averageLapMillis != b.averageLapMillis {
                return a.averageLapMillis < b.averageLapMillis
            }
            if a.fastestLapMillis != b.fastestLapMillis {
                return a.fastestLapMillis < b.fastestLapMillis
            }
            return CanonicalSetupEncoder.encode(a.setup) < CanonicalSetupEncoder.encode(b.setup)
        }

        return SolverOutcome(ranked: evaluated, legalCount: evaluated.count)
    }
}
