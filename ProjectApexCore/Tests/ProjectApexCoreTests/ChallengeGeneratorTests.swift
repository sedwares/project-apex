//
//  ChallengeGeneratorTests.swift
//  ProjectApexCoreTests
//

import XCTest
@testable import ProjectApexCore

final class ChallengeGeneratorTests: XCTestCase {

    // MARK: - Day-number math

    func testEpochDayNumbers() {
        XCTAssertEqual(ChallengeSeed.dayNumber(fromDateKey: "2026-01-01"), 1)
        XCTAssertEqual(ChallengeSeed.dayNumber(fromDateKey: "2026-01-02"), 2)
        XCTAssertEqual(ChallengeSeed.dayNumber(fromDateKey: "2026-02-01"), 32)
        XCTAssertEqual(ChallengeSeed.dayNumber(fromDateKey: "2026-12-31"), 365)
        XCTAssertEqual(ChallengeSeed.dayNumber(fromDateKey: "2027-01-01"), 366)
        // 2028 is a leap year; 2026-07-11 sanity pin: Jan 31 + Feb 28 +
        // Mar 31 + Apr 30 + May 31 + Jun 30 = 181; +11 = 192.
        XCTAssertEqual(ChallengeSeed.dayNumber(fromDateKey: "2026-07-11"), 192)
    }

    func testMalformedDateKeysReturnNil() {
        XCTAssertNil(ChallengeSeed.dayNumber(fromDateKey: "2026/01/01"))
        XCTAssertNil(ChallengeSeed.dayNumber(fromDateKey: "not-a-date"))
        XCTAssertNil(ChallengeSeed.dayNumber(fromDateKey: "2026-13-01"))
        XCTAssertNil(ChallengeSeed.dayNumber(fromDateKey: ""))
    }

    // MARK: - SplitMix64

    func testSplitMix64IsDeterministic() {
        var a = SplitMix64(seed: 42)
        var b = SplitMix64(seed: 42)
        for _ in 0..<100 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testSplitMix64DiffersBySeed() {
        var a = SplitMix64(seed: 1)
        var b = SplitMix64(seed: 2)
        XCTAssertNotEqual(a.next(), b.next())
    }

    // MARK: - Challenge generation

    func testGenerationIsDeterministic() {
        let first = ChallengeGenerator.generate(dateKey: "2026-07-11")
        let second = ChallengeGenerator.generate(dateKey: "2026-07-11")
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
    }

    func testDifferentDaysProduceDifferentChallenges() {
        var distinctCircuits = Set<[TrackSectionType]>()
        for day in 1...20 {
            let challenge = ChallengeGenerator.generate(dayNumber: day, dateKey: "day-\(day)")
            distinctCircuits.insert(challenge.circuit.sections)
        }
        // 20 days must not all share one circuit; expect near-total variety.
        XCTAssertGreaterThan(distinctCircuits.count, 15)
    }

    func testGeneratedChallengeStructure() {
        for day in 1...30 {
            let challenge = ChallengeGenerator.generate(dayNumber: day, dateKey: "day-\(day)")
            XCTAssertTrue(ChallengeGenerator.budgetRange.contains(challenge.budget))
            XCTAssertTrue((11...13).contains(challenge.circuit.sections.count))
            XCTAssertEqual(challenge.circuit.sections.last, .finalStraight)
            XCTAssertGreaterThanOrEqual(challenge.budget, OptionLibrary.minimumTotalCost,
                "budget must admit at least the cheapest setup")
            XCTAssertEqual(challenge.simulationVersion, ResultHasher.simulationVersion)
        }
    }

    func testGenerationCoversArchetypesAndWeather() {
        var archetypes = Set<CircuitArchetype>()
        var weathers = Set<Weather>()
        for day in 1...60 {
            let challenge = ChallengeGenerator.generate(dayNumber: day, dateKey: "day-\(day)")
            archetypes.insert(challenge.circuit.archetype)
            weathers.insert(challenge.weather)
        }
        XCTAssertEqual(archetypes.count, CircuitArchetype.allCases.count)
        XCTAssertEqual(weathers.count, Weather.allCases.count)
    }
}
