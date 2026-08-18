//
//  SimulationEngine.swift
//  ProjectApexCore
//
//  The deterministic 3-lap simulation.
//
//  MODEL
//  ─────
//  Section performance score:
//      perf = Σ over demand entries: (weightBP * effectiveStat) / 10_000
//      where effectiveStat = stat for normal stats,
//                            2000 - stat for inverted stats (weight, heatGen)
//      Weights sum to 10_000 per section, so a baseline car scores
//      exactly 1000 in every section.
//
//  Section time:
//      timeMs = (baseTimeMs * 1000) / max(perf, minPerfClamp)
//      perf 1000 → base time exactly; higher perf → faster.
//
//  Lap structure:
//      Lap 1 — warmup: grip reduced (harsher in Cold weather).
//      Lap 2 — peak: weather-modified stats, no lap effects.
//      Lap 3 — degradation:
//          • tire wear:  grip penalty scaled by tire durability deficit
//          • heat:       QUADRATIC power/topSpeed penalty when
//                        heatGeneration exceeds cooling (thermal
//                        runaway: small deficits nearly free, large
//                        deficits brutal — this is what makes Hot
//                        weather punish heat-prone setups specifically)
//          • reliability: QUADRATIC flat time penalty below the
//                        threshold (pass 6 — see below)
//
//  All constants live in Tuning. All math is fixed-point Int.
//  Determinism: same setup + circuit + weather → identical result, always.
//

public nonisolated enum SimulationEngine {

    // MARK: - Tuning constants (balance data — tune with OptionLibrary)

    public enum Tuning {
        /// Lap 1 grip modifier (basis points).
        public static let warmupGripBP = 9_700
        /// Lap 1 grip modifier when weather is Cold (slower warmup).
        public static let coldWarmupGripBP = 9_200

        /// Lap 3 tire wear:
        ///   deficit  = max(wearReference − tireDurability, 0)
        ///   penaltyBP = min(deficit * 3 / 2, wearPenaltyCapBP)
        public static let wearReference = 1_200
        public static let wearPenaltyNumerator = 3
        public static let wearPenaltyDenominator = 2
        public static let wearPenaltyCapBP = 1_500
        /// Wear penalty at or above this triggers `tireWearHigh`.
        public static let wearEventThresholdBP = 280

        /// Lap 3 heat: deficit = heatGeneration − cooling (if positive).
        /// QUADRATIC penalty to power & topSpeed:
        ///     min(deficit² / heatPenaltyQuadDivisor, heatPenaltyCapBP)
        public static let heatPenaltyQuadDivisor = 300
        public static let heatPenaltyCapBP = 1_400
        /// Deficit at or above this triggers `engineHeatHigh`.
        public static let heatEventThreshold = 200

        /// Lap 3 reliability: below this, a flat time penalty applies.
        public static let reliabilityThreshold = 920

        /// PASS 6 — reliability is now QUADRATIC, matching heat:
        ///     penaltyMs = min(deficit² / reliabilityPenaltyQuadDivisor,
        ///                     reliabilityPenaltyCapMs)
        ///
        /// Why the change. Under the old linear 18 ms/point rule the
        /// safety side of the trade never paid: across 30 days
        /// `reliabilityRisky` (−140 rel, 7 cr) appeared in 48% of top-1%
        /// setups and won 13 days, while `reliabilitySafe` (+160, 14 cr)
        /// managed 17% and 3 days. A build sitting 60 points under the
        /// threshold paid ~1.1 s once, and the 7 credits it saved bought
        /// 0.5–1.5 s elsewhere. Risk was simply cheaper than safety.
        ///
        /// Divisor 4 is calibrated so the curve MEETS the old linear
        /// penalty at a 72-point deficit and exceeds it beyond that:
        ///     deficit  30 →   225 ms  (old 540 — small risk got cheaper)
        ///     deficit  72 →  1296 ms  (old 1296 — the crossover)
        ///     deficit 140 →  4900 ms  (old 2520 — nearly double)
        ///     deficit 190 →  8000 ms  (capped; old 3420)
        /// Carrying a little risk is now genuinely cheap and carrying a
        /// lot is genuinely dangerous, which is the shape that makes the
        /// decision interesting — the same shape heat already had.
        ///
        /// The cap exists so a maximally fragile car is punished without
        /// the penalty growing unbounded if the option library ever
        /// widens. 8 s on a ~90 s lap is severe but survivable.
        public static let reliabilityPenaltyQuadDivisor = 4
        public static let reliabilityPenaltyCapMs = 8_000

        /// Retained so pre-pass-6 balance documents and tests can still
        /// reference the old linear rate. NOT used by the simulation.
        @available(*, deprecated, message: "Pass 6 replaced the linear reliability penalty with a quadratic curve. Use reliabilityPenaltyQuadDivisor.")
        public static let reliabilityPenaltyPerPointMs = 18

        /// Performance clamp: caps worst-case slowdown at 4× base time.
        public static let minPerfClamp = 250

        // Event thresholds on weather-modified stats.
        public static let straightLineStrongTopSpeed = 1_200
        public static let stabilityWeakThreshold = 900
        public static let brakingStrongThreshold = 1_120
        public static let gripStrongThreshold = 1_120
    }

    // MARK: - Public API

    /// Simulates a full 3-lap run for a player setup.
    /// Setup must already be validated; this function does not re-validate.
    public static func simulate(
        setup: PlayerSetup,
        circuit: Circuit,
        weather: Weather
    ) -> SimulationResult {
        let built = VehicleBuilder.build(from: setup)
        let raceStats = weather.apply(to: built)
        let identity = SetupIdentity.derive(from: built)

        let run = runLaps(stats: raceStats, circuit: circuit, weather: weather)
        let baselineRun = runLaps(
            stats: weather.apply(to: .baseline),
            circuit: circuit,
            weather: weather
        )

        let lapTimes = run.laps.map(\.timeMillis)
        let average = lapTimes.reduce(0, +) / lapTimes.count
        let fastest = lapTimes.min() ?? 0

        // Aggregate sector totals against the baseline car's totals.
        var sectorResults: [SectorResult] = []
        for sectorIndex in 0..<3 {
            let total = run.laps.map { $0.sectorTimesMillis[sectorIndex] }.reduce(0, +)
            let baselineTotal = baselineRun.laps.map { $0.sectorTimesMillis[sectorIndex] }.reduce(0, +)
            sectorResults.append(SectorResult(
                index: sectorIndex, totalMillis: total, baselineMillis: baselineTotal
            ))
        }

        let events = deriveEvents(stats: raceStats, lap3: run.lap3Effects)

        let hash = ResultHasher.hash(
            challengeId: setup.challengeId,
            setup: setup,
            averageLapTimeMillis: average,
            fastestLapTimeMillis: fastest
        )

        return SimulationResult(
            challengeId: setup.challengeId,
            setup: setup,
            averageLapTimeMillis: average,
            fastestLapTimeMillis: fastest,
            lapResults: run.laps,
            sectorResults: sectorResults,
            events: events,
            setupIdentity: identity,
            resultHash: hash
        )
    }

    /// Average lap time only — the hot path for the solver and the
    /// engineer's advisor. Skips sector baselines, hashing and identity.
    public static func averageLapMillis(
        setup: PlayerSetup,
        circuit: Circuit,
        weather: Weather
    ) -> Int {
        let stats = weather.apply(to: VehicleBuilder.build(from: setup))
        let run = runLaps(stats: stats, circuit: circuit, weather: weather)
        let times = run.laps.map(\.timeMillis)
        return times.reduce(0, +) / times.count
    }

    // MARK: - Lap loop

    struct Lap3Effects {
        var wearPenaltyBP = 0
        var heatDeficit = 0
        var reliabilityPenaltyMs = 0
    }

    struct RunOutcome {
        var laps: [LapResult]
        var lap3Effects: Lap3Effects
    }

    /// Internal so tests can drive it with arbitrary stats
    /// (including the pure baseline car, unreachable via options).
    static func runLaps(stats: VehicleStats, circuit: Circuit, weather: Weather) -> RunOutcome {
        var laps: [LapResult] = []
        var lap3Effects = Lap3Effects()

        for lapNumber in 1...3 {
            var lapStats = stats
            var flatPenaltyMs = 0

            switch lapNumber {
            case 1:
                let bp = (weather == .cold) ? Tuning.coldWarmupGripBP : Tuning.warmupGripBP
                lapStats.grip = FixedPoint.clampStat(
                    FixedPoint.applyBasisPoints(lapStats.grip, bp)
                )

            case 3:
                // Tire wear → grip penalty.
                let wearDeficit = max(Tuning.wearReference - lapStats.tireDurability, 0)
                let wear = min(
                    (wearDeficit * Tuning.wearPenaltyNumerator) / Tuning.wearPenaltyDenominator,
                    Tuning.wearPenaltyCapBP
                )
                if wear > 0 {
                    lapStats.grip = FixedPoint.clampStat(
                        FixedPoint.applyBasisPoints(
                            lapStats.grip,
                            FixedPoint.basisPointScale - wear
                        )
                    )
                }
                lap3Effects.wearPenaltyBP = wear

                // Heat deficit → power & top speed penalty.
                let deficit = lapStats.heatGeneration - lapStats.cooling
                if deficit > 0 {
                    let penalty = min(
                        (deficit * deficit) / Tuning.heatPenaltyQuadDivisor,
                        Tuning.heatPenaltyCapBP
                    )
                    let bp = FixedPoint.basisPointScale - penalty
                    lapStats.power = FixedPoint.clampStat(
                        FixedPoint.applyBasisPoints(lapStats.power, bp)
                    )
                    lapStats.topSpeed = FixedPoint.clampStat(
                        FixedPoint.applyBasisPoints(lapStats.topSpeed, bp)
                    )
                    lap3Effects.heatDeficit = deficit
                }

                // Reliability → flat time penalty, quadratic (pass 6).
                if lapStats.reliability < Tuning.reliabilityThreshold {
                    let shortfall = Tuning.reliabilityThreshold - lapStats.reliability
                    flatPenaltyMs = min(
                        (shortfall * shortfall) / Tuning.reliabilityPenaltyQuadDivisor,
                        Tuning.reliabilityPenaltyCapMs
                    )
                    lap3Effects.reliabilityPenaltyMs = flatPenaltyMs
                }

            default:
                break // Lap 2: peak performance, no lap effects.
            }

            // Run every section, accumulate per-sector times.
            let ranges = circuit.sectorRanges
            var sectorTimes = [Int](repeating: 0, count: 3)
            for (sectorIndex, range) in ranges.enumerated() {
                for sectionIndex in range {
                    sectorTimes[sectorIndex] += sectionTime(
                        section: circuit.sections[sectionIndex],
                        stats: lapStats
                    )
                }
            }
            // Flat penalties land on the final sector of the lap.
            sectorTimes[2] += flatPenaltyMs

            laps.append(LapResult(
                lapNumber: lapNumber,
                timeMillis: sectorTimes.reduce(0, +),
                sectorTimesMillis: sectorTimes
            ))
        }

        return RunOutcome(laps: laps, lap3Effects: lap3Effects)
    }

    // MARK: - Section math

    /// Precomputed, sorted demand entries per section. The solver calls
    /// performanceScore millions of times per validation batch; building
    /// the demand dictionary on every call would dominate the runtime.
    /// Entry order is StatKey-sorted → deterministic under truncation.
    private static let demandTable: [TrackSectionType: [(key: StatKey, weightBP: Int, inverted: Bool)]] = {
        var table: [TrackSectionType: [(key: StatKey, weightBP: Int, inverted: Bool)]] = [:]
        for section in TrackSectionType.allCases {
            table[section] = section.demandWeightsBP
                .sorted { $0.key < $1.key }
                .map { (key: $0.key, weightBP: $0.value, inverted: $0.key.isInverted) }
        }
        return table
    }()

    /// Demand-weighted performance score. Baseline car → exactly 1000.
    static func performanceScore(section: TrackSectionType, stats: VehicleStats) -> Int {
        var perf = 0
        for entry in demandTable[section]! {
            let effective = entry.inverted
                ? FixedPoint.clampStat(2 * FixedPoint.statBaseline - stats[entry.key])
                : stats[entry.key]
            perf += FixedPoint.applyBasisPoints(effective, entry.weightBP)
        }
        return perf
    }

    /// timeMs = baseTime * 1000 / perf, clamped so a broken setup
    /// can be at most 4× slower than base.
    static func sectionTime(section: TrackSectionType, stats: VehicleStats) -> Int {
        let perf = max(performanceScore(section: section, stats: stats), Tuning.minPerfClamp)
        return (section.baseTimeMillis * FixedPoint.statBaseline) / perf
    }

    // MARK: - Events

    static func deriveEvents(stats: VehicleStats, lap3: Lap3Effects) -> [SimulationEvent] {
        var events: [SimulationEvent] = []
        // Fixed order → deterministic event arrays.
        if lap3.heatDeficit >= Tuning.heatEventThreshold { events.append(.engineHeatHigh) }
        if lap3.wearPenaltyBP >= Tuning.wearEventThresholdBP { events.append(.tireWearHigh) }
        if stats.reliability < Tuning.reliabilityThreshold { events.append(.reliabilityConcern) }
        if stats.topSpeed >= Tuning.straightLineStrongTopSpeed { events.append(.straightLineSpeedStrong) }
        if stats.stability <= Tuning.stabilityWeakThreshold { events.append(.cornerStabilityWeak) }
        if stats.braking >= Tuning.brakingStrongThreshold { events.append(.brakingPerformanceStrong) }
        if stats.grip >= Tuning.gripStrongThreshold { events.append(.gripStrong) }
        return events
    }
}
