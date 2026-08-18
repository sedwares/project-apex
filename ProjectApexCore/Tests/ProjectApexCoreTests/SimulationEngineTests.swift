//
//  SimulationEngineTests.swift
//  ProjectApexCoreTests
//
//  Three kinds of tests:
//  1. Exact pins where math is hand-verifiable (baseline car, single
//     sections, SHA-256 vector).
//  2. Structural properties that must survive balance tuning
//     (lap ordering, determinism, degradation direction).
//  3. Event triggers for the reference setups.
//

import XCTest
@testable import ProjectApexCore

final class SimulationEngineTests: XCTestCase {

    // Reference Setup A: all-balanced (cost 87).
    private var setupA: PlayerSetup {
        PlayerSetup(challengeId: "apex-test-001", selectedOptions: [
            .engineMode: .engineBalanced, .tires: .tiresMedium,
            .aerodynamics: .aeroBalanced, .suspension: .suspensionBalanced,
            .gearRatio: .gearBalanced, .cooling: .coolingStandard,
            .brakes: .brakesBalanced, .reliabilityFocus: .reliabilityBalanced
        ])
    }

    // Reference Setup C: glass cannon (cost 107 after tuning pass 1).
    private var setupC: PlayerSetup {
        PlayerSetup(challengeId: "apex-test-001", selectedOptions: [
            .engineMode: .enginePower, .tires: .tiresSoft,
            .aerodynamics: .aeroLowDrag, .suspension: .suspensionSoft,
            .gearRatio: .gearLong, .cooling: .coolingLight,
            .brakes: .brakesBalanced, .reliabilityFocus: .reliabilityRisky
        ])
    }

    // MARK: - Exact pins: baseline car

    func testBaselineCarLap2IsExactlyCircuitBaseline() {
        // Baseline stats + sunny → perf exactly 1000 in every section →
        // Lap 2 (no lap effects) equals the sum of base times: 95_000.
        let run = SimulationEngine.runLaps(
            stats: .baseline, circuit: .reference, weather: .sunny
        )
        XCTAssertEqual(Circuit.reference.baselineLapMillis, 95_000)
        XCTAssertEqual(run.laps[1].timeMillis, 95_000)
    }

    func testBaselineCarLapOrdering() {
        // Lap 1 warmup makes it slower than Lap 2; Lap 3 wear
        // (baseline durability 1000 < wearReference 1200) makes it
        // slower than Lap 2 as well.
        let run = SimulationEngine.runLaps(
            stats: .baseline, circuit: .reference, weather: .sunny
        )
        XCTAssertGreaterThan(run.laps[0].timeMillis, run.laps[1].timeMillis)
        XCTAssertGreaterThan(run.laps[2].timeMillis, run.laps[1].timeMillis)
    }

    func testSectionTimeExactPin() {
        // Medium corner (base 7000) with grip 970, others baseline
        // (pass-4 weights: grip 3700, stability 3500, aeroEff 2800):
        // perf = (3700*970)/10000 + (3500*1000)/10000 + (2800*1000)/10000
        //      = 358 + 350 + 280 = 988   (coincidentally unchanged)
        // time = 7_000_000 / 988 = 7085 (truncated)
        var stats = VehicleStats.baseline
        stats.grip = 970
        XCTAssertEqual(
            SimulationEngine.performanceScore(section: .mediumCorner, stats: stats), 988
        )
        XCTAssertEqual(
            SimulationEngine.sectionTime(section: .mediumCorner, stats: stats), 7_085
        )
    }

    func testInvertedStatsScoreAsLowerIsBetter() {
        // Elevation climb demands weight (inverted). A lighter car
        // (weight 860 → effective 1140) must outscore baseline.
        var light = VehicleStats.baseline
        light.weight = 860
        let baselineScore = SimulationEngine.performanceScore(section: .elevationClimb, stats: .baseline)
        let lightScore = SimulationEngine.performanceScore(section: .elevationClimb, stats: light)
        XCTAssertEqual(baselineScore, 1_000)
        XCTAssertGreaterThan(lightScore, baselineScore)
    }

    // MARK: - Full-run properties for reference setups

    func testSimulationIsDeterministic() {
        let first = SimulationEngine.simulate(setup: setupC, circuit: .reference, weather: .hot)
        for _ in 0..<50 {
            let again = SimulationEngine.simulate(setup: setupC, circuit: .reference, weather: .hot)
            XCTAssertEqual(again, first)
        }
    }

    func testAverageAndFastestAreConsistent() {
        let result = SimulationEngine.simulate(setup: setupA, circuit: .reference, weather: .sunny)
        let times = result.lapResults.map(\.timeMillis)
        XCTAssertEqual(result.lapResults.count, 3)
        XCTAssertEqual(result.averageLapTimeMillis, times.reduce(0, +) / 3)
        XCTAssertEqual(result.fastestLapTimeMillis, times.min())
        XCTAssertLessThanOrEqual(result.fastestLapTimeMillis, result.averageLapTimeMillis)
    }

    func testGlassCannonDegradesHardestOnLap3() {
        // Setup C: durability 820, heatGen 1240 vs cooling 900,
        // reliability 770 → Lap 3 must be its worst lap by a clear margin.
        let result = SimulationEngine.simulate(setup: setupC, circuit: .reference, weather: .sunny)
        let lap2 = result.lapResults[1].timeMillis
        let lap3 = result.lapResults[2].timeMillis
        XCTAssertGreaterThan(lap3, lap2)
        // Reliability penalty alone: (920 - 770) * 18 = 2700 ms.
        XCTAssertGreaterThanOrEqual(lap3 - lap2, 2_700)
    }

    func testHotWeatherHurtsGlassCannonMoreThanBalanced() {
        // The intended tension (Balance Sheet §4): Hot must punish
        // Power+Soft harder than a balanced build.
        func avgDelta(_ setup: PlayerSetup) -> Int {
            let sunny = SimulationEngine.simulate(setup: setup, circuit: .reference, weather: .sunny)
            let hot = SimulationEngine.simulate(setup: setup, circuit: .reference, weather: .hot)
            return hot.averageLapTimeMillis - sunny.averageLapTimeMillis
        }
        XCTAssertGreaterThan(avgDelta(setupC), avgDelta(setupA))
    }

    // MARK: - Events

    func testGlassCannonEventsFire() {
        let result = SimulationEngine.simulate(setup: setupC, circuit: .reference, weather: .sunny)
        XCTAssertTrue(result.events.contains(.engineHeatHigh))     // deficit 390 ≥ 200
        XCTAssertTrue(result.events.contains(.tireWearHigh))       // wear 570 ≥ 280
        XCTAssertTrue(result.events.contains(.reliabilityConcern)) // 770 < 920
        XCTAssertTrue(result.events.contains(.straightLineSpeedStrong)) // 1285 ≥ 1200
        XCTAssertTrue(result.events.contains(.cornerStabilityWeak))     // 900 ≤ 900
    }

    func testBalancedSetupTriggersNoNegativeEvents() {
        let result = SimulationEngine.simulate(setup: setupA, circuit: .reference, weather: .sunny)
        XCTAssertFalse(result.events.contains(.engineHeatHigh))
        XCTAssertFalse(result.events.contains(.reliabilityConcern))
        XCTAssertFalse(result.events.contains(.cornerStabilityWeak))
    }

    // MARK: - Sectors

    func testSectorStructure() {
        let result = SimulationEngine.simulate(setup: setupA, circuit: .reference, weather: .sunny)
        XCTAssertEqual(result.sectorResults.count, 3)
        XCTAssertEqual(Circuit.reference.sectorRanges.map(\.count), [4, 4, 4])
        // Sector totals must reconstruct the lap totals.
        let sectorSum = result.sectorResults.map(\.totalMillis).reduce(0, +)
        let lapSum = result.lapResults.map(\.timeMillis).reduce(0, +)
        XCTAssertEqual(sectorSum, lapSum)
    }

    // MARK: - Hashing

    func testSHA256KnownVector() {
        // FIPS 180-4 test vector.
        XCTAssertEqual(
            SHA256.hexDigest(of: "abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            SHA256.hexDigest(of: ""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testResultHashIsStableAndSetupSensitive() {
        let a = SimulationEngine.simulate(setup: setupA, circuit: .reference, weather: .sunny)
        let a2 = SimulationEngine.simulate(setup: setupA, circuit: .reference, weather: .sunny)
        let c = SimulationEngine.simulate(setup: setupC, circuit: .reference, weather: .sunny)
        XCTAssertEqual(a.resultHash, a2.resultHash)
        XCTAssertNotEqual(a.resultHash, c.resultHash)
        XCTAssertEqual(a.resultHash.count, 64) // hex SHA-256
    }
}
