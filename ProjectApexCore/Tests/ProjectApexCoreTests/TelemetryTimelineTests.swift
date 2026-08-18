//
//  TelemetryTimelineTests.swift
//  ProjectApexCoreTests
//

import XCTest
@testable import ProjectApexCore

final class TelemetryTimelineTests: XCTestCase {

    private func result(_ setup: PlayerSetup, weather: Weather) -> SimulationResult {
        SimulationEngine.simulate(setup: setup, circuit: .reference, weather: weather)
    }

    private var balanced: PlayerSetup {
        PlayerSetup(challengeId: "t", selectedOptions: [
            .engineMode: .engineBalanced, .tires: .tiresMedium,
            .aerodynamics: .aeroBalanced, .suspension: .suspensionBalanced,
            .gearRatio: .gearBalanced, .cooling: .coolingStandard,
            .brakes: .brakesBalanced, .reliabilityFocus: .reliabilityBalanced
        ])
    }

    private var glassCannon: PlayerSetup {
        PlayerSetup(challengeId: "t", selectedOptions: [
            .engineMode: .enginePower, .tires: .tiresSoft,
            .aerodynamics: .aeroLowDrag, .suspension: .suspensionSoft,
            .gearRatio: .gearLong, .cooling: .coolingLight,
            .brakes: .brakesBalanced, .reliabilityFocus: .reliabilityRisky
        ])
    }

    func testTimelineShapeAndBounds() {
        let sections = Circuit.reference.sections.count
        let samples = TelemetryTimeline.samples(for: result(balanced, weather: .sunny), sectionsPerLap: sections)
        XCTAssertEqual(samples.count, 3 * sections)
        for s in samples {
            XCTAssertTrue((0.0...1.0).contains(s.grip))
            XCTAssertTrue((0.0...1.0).contains(s.heat))
            XCTAssertTrue((0.0...1.0).contains(s.tireLife))
            XCTAssertTrue((0.0...1.0).contains(s.runProgress))
        }
        // runProgress is strictly increasing and ends at 1.
        for i in 1..<samples.count {
            XCTAssertGreaterThan(samples[i].runProgress, samples[i-1].runProgress)
        }
        XCTAssertEqual(samples.last!.runProgress, 1.0, accuracy: 0.0001)
    }

    func testWarmupGripIsLowestAtTheStart() {
        let sections = Circuit.reference.sections.count
        let samples = TelemetryTimeline.samples(for: result(balanced, weather: .sunny), sectionsPerLap: sections)
        let firstSection = samples.first { $0.lap == 1 && $0.sectionIndex == 0 }!
        let peakLap2 = samples.first { $0.lap == 2 && $0.sectionIndex == 0 }!
        XCTAssertLessThan(firstSection.grip, peakLap2.grip, "Lap 1 opens cold")
    }

    func testGlassCannonHeatClimbsOnLapThree() {
        let sections = Circuit.reference.sections.count
        let hot = TelemetryTimeline.samples(for: result(glassCannon, weather: .hot), sectionsPerLap: sections)
        let lap2Heat = hot.first { $0.lap == 2 }!.heat
        let lap3End = hot.last!.heat
        XCTAssertGreaterThan(lap3End, lap2Heat, "heat must rise into Lap 3")
    }

    func testTireLifeFallsAcrossTheRun() {
        let sections = Circuit.reference.sections.count
        let samples = TelemetryTimeline.samples(for: result(glassCannon, weather: .hot), sectionsPerLap: sections)
        let earliest = samples.first!.tireLife
        let latest = samples.last!.tireLife
        XCTAssertLessThan(latest, earliest, "tires wear down over three laps")
    }

    func testDeterministic() {
        let sections = Circuit.reference.sections.count
        let a = TelemetryTimeline.samples(for: result(glassCannon, weather: .windy), sectionsPerLap: sections)
        let b = TelemetryTimeline.samples(for: result(glassCannon, weather: .windy), sectionsPerLap: sections)
        XCTAssertEqual(a, b)
    }

    func testBalancedCarDecaysLessThanGlassCannon() {
        let sections = Circuit.reference.sections.count
        let bal = TelemetryTimeline.samples(for: result(balanced, weather: .hot), sectionsPerLap: sections)
        let gc = TelemetryTimeline.samples(for: result(glassCannon, weather: .hot), sectionsPerLap: sections)
        // Final-lap heat: the cannon should end hotter than the balanced car.
        XCTAssertGreaterThan(gc.last!.heat, bal.last!.heat)
        // And keep more tire life in the balanced car.
        XCTAssertGreaterThan(bal.last!.tireLife, gc.last!.tireLife)
    }
}
