//
//  Pass6BalanceTests.swift
//  ProjectApexCoreTests
//
//  Every claim made about the pass-6 rebalance, as an assertion.
//
//  These exist because the pass-6 numbers were derived from a Python
//  port of the simulation, not from this code. A port is not the thing
//  itself. Each test below pins one of those claims to real Swift, so
//  the balance sheet is verified here rather than trusted from a
//  comment — and so a future tuning pass can't quietly undo it.
//
//  All fast (no exhaustive solving) EXCEPT testFullGate, which is
//  gated behind an environment variable. Run it with:
//      APEX_FULL_BATCH=1 swift test --filter testFullGate
//  or add APEX_FULL_BATCH=1 to the scheme's environment variables.
//

import XCTest
@testable import ProjectApexCore

final class Pass6BalanceTests: XCTestCase {

    // MARK: - The version bump

    func testSimulationVersionWasBumped() {
        // Records and leaderboard rows from sim-1.0.0 are not comparable
        // to this build: the option library, the reliability curve and
        // the legal setup set all moved.
        XCTAssertEqual(ResultHasher.simulationVersion, "sim-1.1.0")
    }

    // MARK: - Library shape

    func testLibraryShapeAndCostBounds() {
        XCTAssertEqual(OptionLibrary.allOptions.count, 24)
        for category in EngineeringCategoryID.allCases {
            XCTAssertEqual(
                OptionLibrary.options(in: category).count, 3,
                "\(category.rawValue) must offer exactly three options"
            )
        }
        // Repricing engineEfficient 7 → 5 moved the floor from 64 to 62.
        XCTAssertEqual(OptionLibrary.minimumTotalCost, 62)
        XCTAssertEqual(OptionLibrary.maximumTotalCost, 135)
    }

    /// THE test that matters most in this file.
    ///
    /// The static-setup exploit — one fixed car, submitted unchanged
    /// every day, beating 88% of the field — existed because seven of
    /// the eight middle options had no downside whatsoever. They were
    /// pure stat gifts, so the middle row was never wrong, which is
    /// exactly what a set-and-forget build needs.
    ///
    /// This asserts the invariant that killed it: EVERY option pays for
    /// itself somewhere. If a future tuning pass reintroduces a
    /// free option, this fails before the exploit comes back.
    func testEveryOptionHasARealDownside() {
        for option in OptionLibrary.allOptions {
            let hasDownside = option.statEffects.contains { key, value in
                key.isInverted ? value > 0 : value < 0
            }
            XCTAssertTrue(
                hasDownside,
                "\(option.id.rawValue) has no downside — a free option makes a "
                    + "set-and-forget car viable. Give it a cost somewhere."
            )
        }
    }

    func testRepricedOptionsMatchTheBalanceSheet() {
        let efficient = OptionLibrary.option(.engineEfficient)
        XCTAssertEqual(efficient.cost, 5)
        // Efficient only earns its place on hot days if it genuinely
        // substitutes for cooling capacity.
        XCTAssertEqual(efficient.statEffects[.cooling], 60)
        XCTAssertEqual(efficient.statEffects[.heatGeneration], -150)

        let lowDrag = OptionLibrary.option(.aeroLowDrag)
        XCTAssertEqual(lowDrag.cost, 13)
        XCTAssertEqual(lowDrag.statEffects[.topSpeed], 110)
        XCTAssertEqual(lowDrag.statEffects[.aeroEfficiency], 85)
    }

    // MARK: - The reliability curve

    /// Measured through the engine, not by re-deriving the formula:
    /// stats are arranged so lap 3's ONLY active effect is reliability
    /// (tires above the wear reference, cooling above heat), so the
    /// lap-3-minus-lap-2 delta is exactly the flat penalty.
    private func reliabilityPenaltyMillis(deficit: Int) -> Int {
        var stats = VehicleStats.baseline
        stats.tireDurability = SimulationEngine.Tuning.wearReference // no wear
        stats.heatGeneration = 900
        stats.cooling = 1_000                                        // no heat deficit
        stats.reliability = SimulationEngine.Tuning.reliabilityThreshold - deficit

        let run = SimulationEngine.runLaps(
            stats: stats, circuit: .reference, weather: .sunny
        )
        return run.laps[2].timeMillis - run.laps[1].timeMillis
    }

    func testReliabilityPenaltyIsQuadraticWithTheDocumentedShape() {
        // The comment in SimulationEngine.Tuning promises these values.
        XCTAssertEqual(reliabilityPenaltyMillis(deficit: 0), 0)
        XCTAssertEqual(reliabilityPenaltyMillis(deficit: 30), 225)
        XCTAssertEqual(reliabilityPenaltyMillis(deficit: 72), 1_296)
        XCTAssertEqual(reliabilityPenaltyMillis(deficit: 140), 4_900)
        // Capped, not unbounded.
        XCTAssertEqual(
            reliabilityPenaltyMillis(deficit: 190),
            SimulationEngine.Tuning.reliabilityPenaltyCapMs
        )
    }

    func testReliabilityCurveCrossesTheOldLinearRateAt72() {
        // The point of the change: carrying a LITTLE risk got cheaper,
        // carrying a LOT got much more expensive. 18 ms/point was the
        // old linear rate.
        let oldRate = 18
        XCTAssertLessThan(reliabilityPenaltyMillis(deficit: 30), 30 * oldRate)
        XCTAssertEqual(reliabilityPenaltyMillis(deficit: 72), 72 * oldRate)
        XCTAssertGreaterThan(reliabilityPenaltyMillis(deficit: 140), 140 * oldRate)
    }

    func testReliabilityPenaltyIsMonotonic() {
        var previous = -1
        for deficit in stride(from: 0, through: 200, by: 10) {
            let penalty = reliabilityPenaltyMillis(deficit: deficit)
            XCTAssertGreaterThanOrEqual(penalty, previous)
            previous = penalty
        }
    }

    // MARK: - The daily technical regulation

    func testEveryGeneratedDayIsSatisfiable() {
        // A regulation that bans the cheapest option in a category
        // raises the cost floor. If it raises it above the day's budget
        // there is no legal setup at all and the day is unplayable.
        for day in 1...365 {
            let challenge = ChallengeGenerator.generate(dayNumber: day, dateKey: "day-\(day)")
            XCTAssertTrue(
                challenge.isSatisfiable,
                "day \(day): budget \(challenge.budget) below the regulated minimum "
                    + "\(OptionLibrary.minimumTotalCost(banned: challenge.bannedOption))"
            )
        }
    }

    func testRegulationShrinksTheLegalSpaceAndIsNeverEnumerated() {
        let challenge = ChallengeGenerator.generate(dayNumber: 7, dateKey: "day-7")
        guard let banned = challenge.bannedOption else {
            return XCTFail("day 7 should carry a regulation")
        }
        // One category drops to two options: 3^8 → 2 × 3^7.
        XCTAssertEqual(SetupEnumerator.setupCount(banned: banned), 4_374)

        var sawBanned = false
        SetupEnumerator.forEachSetup(challengeId: challenge.id, banned: banned) { setup in
            if setup.selectedOptions.values.contains(banned) { sawBanned = true }
        }
        XCTAssertFalse(sawBanned, "the enumerator emitted a banned option")
    }

    func testValidatorRejectsTheBannedOption() {
        let challenge = ChallengeGenerator.generate(dayNumber: 7, dateKey: "day-7")
        guard let banned = challenge.bannedOption else {
            return XCTFail("day 7 should carry a regulation")
        }
        // Build a setup that deliberately uses it.
        var selections: [EngineeringCategoryID: EngineeringOptionID] = [:]
        for category in EngineeringCategoryID.allCases {
            selections[category] = OptionLibrary.options(in: category).first!.id
        }
        selections[OptionLibrary.option(banned).category] = banned

        let setup = PlayerSetup(challengeId: challenge.id, selectedOptions: selections)
        let errors = SetupValidator.validate(setup, challenge: challenge)
        XCTAssertTrue(errors.contains(.bannedOption(banned)), "got \(errors)")
    }

    func testGenerationIsDeterministicAndNonceRerollsTheDay() {
        let a = ChallengeGenerator.generate(dayNumber: 12, dateKey: "day-12")
        let b = ChallengeGenerator.generate(dayNumber: 12, dateKey: "day-12")
        XCTAssertEqual(a, b, "same day must produce an identical challenge")

        let rerolled = ChallengeGenerator.generate(dayNumber: 12, dateKey: "day-12", nonce: 1)
        XCTAssertNotEqual(
            a.circuit.sections, rerolled.circuit.sections,
            "a nonce must actually re-roll the day, or a failing day can't be replaced"
        )
    }

    // MARK: - Circuit demand profile (the build screen's honesty)

    func testDemandSharesSumToWhole() {
        for day in 1...20 {
            let challenge = ChallengeGenerator.generate(dayNumber: day, dateKey: "day-\(day)")
            let total = challenge.circuit.statDemandBP.reduce(0) { $0 + $1.shareBP }
            // Integer truncation loses a few basis points per entry.
            XCTAssertEqual(
                Double(total), Double(FixedPoint.basisPointScale), accuracy: 30,
                "day \(day) demand shares summed to \(total)"
            )
        }
    }

    /// The claim behind the whole build-screen change: different
    /// circuits genuinely demand different stats. Built from explicit
    /// section lists so this tests the mechanism, not a lucky draw.
    func testDemandProfileDistinguishesCircuitCharacter() {
        let straights = Circuit(
            id: "t-fast", name: "Fast", archetype: .highSpeed,
            sections: Array(repeating: .longStraight, count: 6) + [.finalStraight]
        )
        let corners = Circuit(
            id: "t-slow", name: "Slow", archetype: .technical,
            sections: Array(repeating: .slowCorner, count: 6) + [.finalStraight]
        )

        let fastTop = straights.decidingStats().map(\.key)
        let slowTop = corners.decidingStats().map(\.key)

        XCTAssertTrue(fastTop.contains(.topSpeed), "a straight-line circuit must demand top speed")
        XCTAssertFalse(fastTop.contains(.grip), "a straight-line circuit shouldn't rank grip in its top four")
        XCTAssertTrue(slowTop.contains(.grip), "a slow-corner circuit must demand grip")
        XCTAssertNotEqual(fastTop, slowTop, "the two archetypes must read differently")
    }

    func testDemandProfileSurfacesStatsTheOldFixedAxesHid() {
        // braking, acceleration, power, cooling and weight were all
        // invisible in the old five-axis profile. On the right circuit
        // each must now be able to reach the top four.
        let brakingCircuit = Circuit(
            id: "t-brake", name: "Brakes", archetype: .street,
            sections: Array(repeating: .heavyBrakingZone, count: 6) + [.finalStraight]
        )
        XCTAssertTrue(brakingCircuit.decidingStats().map(\.key).contains(.braking))

        let climbCircuit = Circuit(
            id: "t-climb", name: "Climb", archetype: .mountain,
            sections: Array(repeating: .elevationClimb, count: 6) + [.finalStraight]
        )
        let climbTop = climbCircuit.decidingStats().map(\.key)
        XCTAssertTrue(climbTop.contains(.cooling))
        XCTAssertTrue(climbTop.contains(.weight))
    }

    // MARK: - The full gate (slow, opt-in)

    /// The batch gate, including criterion 8 (no reusable static car).
    /// Opt-in because it exhaustively solves every day in the range.
    ///
    /// Expected shape from the Python port over 180 days: max option win
    /// rate 54%, minimum top-1% share 16.3%, static exploit ~64%. If the
    /// Swift numbers differ materially from those, trust THIS and tell
    /// me — the port was the approximation, not the code.
    func testFullGate() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["APEX_FULL_BATCH"] == "1",
            "set APEX_FULL_BATCH=1 to run the exhaustive batch gate"
        )
        // 30 days in Debug; widen to 1...180 in Release for real tuning
        // decisions — at n=30 an option's win rate carries roughly ±9
        // percentage points of sampling noise.
        let report = BatchValidator.run(dayNumbers: 1...30, checkStaticExploit: true)
        print(report.renderText())

        if let exploit = report.staticExploit {
            XCTAssertLessThanOrEqual(
                exploit.meanPercentile,
                BatchValidator.Thresholds.staticExploitMaxPercentile,
                "a single fixed setup is too good: "
                    + CanonicalSetupEncoder.encode(exploit.setup)
            )
        } else {
            XCTFail("criterion 8 did not run")
        }

        for (option, share) in report.optionTopSharePercent
        where share < BatchValidator.Thresholds.minTopSharePercent {
            XCTFail("near-dead option \(option.rawValue) at \(share)% of top-1% setups")
        }

        XCTAssertTrue(report.gate.passed, "gate failures:\n" + report.gate.failures.joined(separator: "\n"))
    }
}
