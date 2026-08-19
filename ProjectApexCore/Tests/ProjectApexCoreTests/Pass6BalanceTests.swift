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
import Foundation
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
    /// The re-roll register is keyed by date and the gate is keyed by
    /// day number, so every entry passes through this inverse. A
    /// calendar bug here would apply the right nonce to the wrong day —
    /// silently, and only on dates near a month or leap boundary.
    func testDayNumberDateKeyRoundTrip() {
        XCTAssertEqual(ChallengeSeed.dateKey(forDayNumber: 1), "2026-01-01")
        XCTAssertEqual(ChallengeSeed.dateKey(forDayNumber: 59), "2026-02-28")
        XCTAssertEqual(ChallengeSeed.dateKey(forDayNumber: 60), "2026-03-01")
        XCTAssertEqual(ChallengeSeed.dateKey(forDayNumber: 230), "2026-08-18")
        XCTAssertEqual(ChallengeSeed.dateKey(forDayNumber: 366), "2027-01-01")
        // 2028 is a leap year — the boundary the naive version gets wrong.
        XCTAssertEqual(ChallengeSeed.dateKey(forDayNumber: 789), "2028-02-28")
        XCTAssertEqual(ChallengeSeed.dateKey(forDayNumber: 790), "2028-02-29")
        XCTAssertEqual(ChallengeSeed.dateKey(forDayNumber: 791), "2028-03-01")

        for day in 1...4000 {
            let key = ChallengeSeed.dateKey(forDayNumber: day)
            XCTAssertEqual(ChallengeSeed.dayNumber(fromDateKey: key), day, "round-trip broke at day \(day) (\(key))")
        }
    }

    /// Today's day number (UTC). Days before this cannot be re-rolled:
    /// a new draw for a date that has passed either does nothing or,
    /// once the game is live, rewrites a competition people played.
    static var todayDayNumber: Int {
        ChallengeSeed.dayNumber(fromDateKey: UTCDateKey.make()) ?? 1
    }

    /// Reads the repository's re-roll register into dayNumber → nonce.
    ///
    /// Located relative to THIS SOURCE FILE, not the working directory:
    /// `swift test` and Xcode disagree about the latter, and a loader
    /// that silently returns [:] when it can't find the file would make
    /// the gate quietly validate the wrong challenges.
    static func publishedNonces() -> [Int: Int] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ProjectApexCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // ProjectApexCore
            .deletingLastPathComponent()   // repo root
        let path = root.appendingPathComponent("rerolls.txt")
        guard let text = try? String(contentsOf: path, encoding: .utf8) else {
            print("⚠️ no rerolls.txt at \(path.path) — validating canonical draws only")
            return [:]
        }
        var map: [Int: Int] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.prefix { $0 != "#" }.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts = line.split(separator: "=")
            guard parts.count == 2,
                  let nonce = Int(parts[1]),
                  let day = ChallengeSeed.dayNumber(fromDateKey: String(parts[0]))
            else {
                XCTFail("malformed line in rerolls.txt: \(line)")
                continue
            }
            map[day] = nonce
        }
        return map
    }

    func testFullGate() throws {
        // APEX_FULL_BATCH is both the switch and the day count:
        //   =1    → 30 days, a quick sanity pass
        //   =180  → the real thing, and what tuning decisions need
        // Parameterised so a serious run needs a scheme setting rather
        // than a source edit you then have to remember to revert.
        guard let raw = ProcessInfo.processInfo.environment["APEX_FULL_BATCH"] else {
            throw XCTSkip("set APEX_FULL_BATCH=1 (or =180) to run the exhaustive batch gate")
        }
        let days = max(Int(raw) ?? 30, 2)
        let range = 1...(days == 1 ? 30 : days)

        // At n=30 an option's win rate carries roughly ±9 percentage
        // points of sampling noise — wider than the distance between
        // "healthy" and "dominant". Use 180 before changing balance.
        print("Running the gate over \(range.count) days…")
        // Honour the re-roll register: a day that was published with a
        // non-canonical draw must be validated as PUBLISHED, not as its
        // canonical draw. Without this the same days fail forever no
        // matter how many times you re-roll them.
        let nonces = Self.publishedNonces()
        if !nonces.isEmpty { print("Applying \(nonces.count) re-roll(s) from rerolls.txt") }
        let report = BatchValidator.run(
            dayNumbers: range,
            nonces: nonces,
            // Days 1...180 are Jan-Jun 2026 — a statistical SAMPLE, and
            // entirely in the past. Telling the report so keeps it from
            // printing a confident paste-ready --reroll command made
            // only of dates that must never be re-rolled.
            publishableFrom: Self.todayDayNumber,
            checkStaticExploit: true
        )
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

        // `gate.passed` is the BALANCE verdict only. Per-day spread and
        // lock failures are a publishing worklist — they are printed in
        // the report above and deliberately not asserted here, because a
        // day that draws badly is re-rolled with a nonce, not fixed by
        // changing the model. See GateResult.
        XCTAssertTrue(
            report.gate.passed,
            "balance gate failed:\n" + report.gate.balanceFailures.joined(separator: "\n")
        )

        if !report.gate.dayFailures.isEmpty {
            print(
                "\n\(report.gate.dayFailures.count) of \(range.count) sampled days drew badly. "
                    + "Balance is unaffected. The actionable list is below."
            )
        }

        // ── The worklist that can actually be acted on ───────────────
        //
        // Everything above is a balance sample. The days you can still
        // change are the ones that haven't happened yet, so validate
        // those separately and take the re-roll command from HERE.
        //
        // The window's batch criteria are not evaluated at all: at n=90
        // an option's win rate carries about ±6 percentage points of
        // sampling noise, wider than the gap to the 58% ceiling. The
        // 180-day sample above is the balance verdict; this run only
        // answers "which upcoming days drew badly".
        let windowStart = Self.todayDayNumber + 1
        let windowLength = 90
        print("\n\n═══ PUBLISHING WINDOW — the re-rollable days ═══")
        print("\(windowLength) days from \(ChallengeSeed.dateKey(forDayNumber: windowStart))\n")
        let window = BatchValidator.run(
            dayNumbers: windowStart...(windowStart + windowLength - 1),
            nonces: nonces,
            publishableFrom: windowStart,
            // Worklist only. The first version of this run reported
            // "⚠️ DOMINANT suspensionStiff 62%" on a window whose
            // 180-day parent measured 52% — a real number, drawn from a
            // sample far too small to carry it.
            evaluateBatchCriteria: false,
            checkStaticExploit: false
        )
        print(window.renderText())
    }

    // MARK: - Drift

    /// The 540-day baseline, measured 2026-08-19 at `sim-1.1.0`.
    ///
    /// (win rate across challenges, share of top-1% setups), both
    /// percent, sorted by win rate.
    ///
    /// This is the real change-detector. A single dominance ceiling
    /// watches one option in one direction; this watches all 24 in both,
    /// so a change that makes something quietly WEAKER — the failure
    /// that produced seven downside-free middle options before pass 6 —
    /// shows up here and nowhere else.
    ///
    /// If you change OptionLibrary, SimulationEngine or TrackGenerator,
    /// this test tells you what you actually did. Update the numbers
    /// only once you have looked at the diff and agreed with it.
    static let winRateBaseline: [EngineeringOptionID: (win: Int, share: Int)] = [
        .suspensionStiff:     (57, 46),
        .coolingLight:        (55, 44),
        .reliabilityBalanced: (49, 44),
        .tiresMedium:         (46, 43),
        .aeroHighDownforce:   (42, 39),
        .engineBalanced:      (42, 45),
        .aeroLowDrag:         (40, 39),
        .enginePower:         (40, 37),
        .gearLong:            (40, 37),
        .brakesConservative:  (38, 36),
        .gearShort:           (36, 34),
        .tiresSoft:           (36, 35),
        .reliabilityRisky:    (31, 31),
        .brakesAggressive:    (30, 29),
        .brakesBalanced:      (30, 33),
        .suspensionSoft:      (26, 26),
        .gearBalanced:        (23, 28),
        .coolingStandard:     (22, 30),
        .coolingHeavy:        (21, 24),
        .reliabilitySafe:     (19, 24),
        .tiresHard:           (17, 20),
        .aeroBalanced:        (16, 21),
        .engineEfficient:     (16, 17),
        .suspensionBalanced:  (16, 26),
    ]

    /// 8 points. At n=540 an option's win rate carries about ±2 points
    /// of sampling noise, so 8 is roughly four standard errors — it will
    /// not fire by chance, and anything that does move an option that
    /// far is a design decision you want to have made deliberately.
    static let driftTolerance = 8

    /// Opt-in: 540 exhaustive solves, about 15 seconds in Release.
    ///
    ///     APEX_DRIFT_BATCH=1 swift test -c release -Xswiftc -enable-testing \
    ///         --filter testOptionWinRatesHaveNotDrifted
    func testOptionWinRatesHaveNotDrifted() throws {
        guard ProcessInfo.processInfo.environment["APEX_DRIFT_BATCH"] != nil else {
            throw XCTSkip("set APEX_DRIFT_BATCH=1 to check the option library against its 540-day baseline")
        }

        let report = BatchValidator.run(
            dayNumbers: 1...540,
            nonces: Self.publishedNonces(),
            publishableFrom: Self.todayDayNumber,
            checkStaticExploit: false
        )

        func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

        var moved: [String] = []
        for option in EngineeringOptionID.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let base = Self.winRateBaseline[option] else {
                XCTFail("no baseline for \(option.rawValue) — a new option needs a new 540-day run")
                continue
            }
            let win = report.optionWinRates[option] ?? 0
            let share = report.optionTopSharePercent[option] ?? 0
            let winDelta = win - base.win
            let shareDelta = share - base.share
            if abs(winDelta) > Self.driftTolerance || abs(shareDelta) > Self.driftTolerance {
                moved.append(
                    "  \(option.rawValue): win \(base.win)% → \(win)% (\(signed(winDelta)))"
                        + ", top1% \(base.share)% → \(share)% (\(signed(shareDelta)))"
                )
            }
        }

        if !moved.isEmpty {
            XCTFail("""
                \(moved.count) option(s) moved more than \(Self.driftTolerance) points from the \
                540-day baseline:
                \(moved.joined(separator: "\n"))

                If this was intentional, update winRateBaseline — and remember that a change to \
                the option library changes lap times, so it also needs a simulationVersion bump \
                and a full republish of every unplayed day.
                """)
        }
    }
}
