//
//  SimulationResult.swift
//  ProjectApexCore
//
//  Result models for a completed simulation: SimulationEvent,
//  LapResult, SectorResult, SimulationResult. Kept in one file because
//  they always change together.
//

/// Rule-based events emitted by the simulation. The FeedbackEngine
/// (next module) converts these into debrief text.
public nonisolated enum SimulationEvent: String, Codable, CaseIterable, Sendable {
    case engineHeatHigh          // heat deficit crossed the event threshold
    case tireWearHigh            // Lap 3 wear penalty crossed the event threshold
    case reliabilityConcern      // reliability below the penalty threshold
    case straightLineSpeedStrong // top speed well above baseline
    case cornerStabilityWeak     // stability well below baseline
    case brakingPerformanceStrong
    case gripStrong
}

public nonisolated struct LapResult: Codable, Hashable, Sendable {
    /// 1, 2, or 3.
    public let lapNumber: Int
    public let timeMillis: Int
    /// Per-sector times for this lap (3 entries).
    public let sectorTimesMillis: [Int]

    public init(lapNumber: Int, timeMillis: Int, sectorTimesMillis: [Int]) {
        self.lapNumber = lapNumber
        self.timeMillis = timeMillis
        self.sectorTimesMillis = sectorTimesMillis
    }
}

public nonisolated struct SectorResult: Codable, Hashable, Sendable {
    /// 0-based sector index.
    public let index: Int
    /// Total time across all three laps.
    public let totalMillis: Int
    /// Neutral total (baseline car, same laps) for gap analysis.
    /// totalMillis < baselineMillis means the setup gains time here.
    public let baselineMillis: Int

    public init(index: Int, totalMillis: Int, baselineMillis: Int) {
        self.index = index
        self.totalMillis = totalMillis
        self.baselineMillis = baselineMillis
    }

    /// Gap to neutral in milliseconds (negative = faster than baseline).
    public var gapMillis: Int { totalMillis - baselineMillis }
}

public nonisolated struct SimulationResult: Codable, Hashable, Sendable {
    public let challengeId: String
    public let setup: PlayerSetup
    public let averageLapTimeMillis: Int
    public let fastestLapTimeMillis: Int
    public let lapResults: [LapResult]
    public let sectorResults: [SectorResult]
    public let events: [SimulationEvent]
    public let setupIdentity: SetupIdentity
    public let resultHash: String

    public init(
        challengeId: String,
        setup: PlayerSetup,
        averageLapTimeMillis: Int,
        fastestLapTimeMillis: Int,
        lapResults: [LapResult],
        sectorResults: [SectorResult],
        events: [SimulationEvent],
        setupIdentity: SetupIdentity,
        resultHash: String
    ) {
        self.challengeId = challengeId
        self.setup = setup
        self.averageLapTimeMillis = averageLapTimeMillis
        self.fastestLapTimeMillis = fastestLapTimeMillis
        self.lapResults = lapResults
        self.sectorResults = sectorResults
        self.events = events
        self.setupIdentity = setupIdentity
        self.resultHash = resultHash
    }
}
