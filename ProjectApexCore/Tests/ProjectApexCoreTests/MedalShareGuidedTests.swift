//
//  MedalShareGuidedTests.swift
//  ProjectApexCoreTests
//
//  v1.3: medals, the share card and the guided first day.
//

import XCTest
@testable import ProjectApexCore

final class MedalShareGuidedTests: XCTestCase {

    private func challenge(
        budget: Int = 100,
        banned: EngineeringOptionID? = nil,
        dateKey: String = "2026-10-20"
    ) -> DailyChallenge {
        DailyChallenge(
            id: "t", dateKey: dateKey, seed: 1, circuit: .reference, weather: .sunny,
            budget: budget, simulationVersion: ResultHasher.simulationVersion,
            minPossibleAverageLapMillis: 0, bannedOption: banned
        )
    }

    private func run(_ picks: [EngineeringCategoryID: EngineeringOptionID],
                     _ challenge: DailyChallenge) -> SimulationResult {
        SimulationEngine.simulate(
            setup: PlayerSetup(challengeId: challenge.id, selectedOptions: picks),
            circuit: challenge.circuit, weather: challenge.weather
        )
    }

    // MARK: - Medals

    func testThresholdsAreOrderedAndTheOptimumEarnsGold() {
        let day = challenge()
        let outcome = ExhaustiveSolver.solve(challenge: day)
        let targets = DayTargets.compute(challenge: day, outcome: outcome)
        XCTAssertLessThanOrEqual(targets.bestAverageLapMillis, targets.goldMillis)
        XCTAssertLessThanOrEqual(targets.goldMillis, targets.silverMillis)
        XCTAssertLessThanOrEqual(targets.silverMillis, targets.bronzeMillis)
        XCTAssertEqual(targets.medal(forAverageLapMillis: outcome.winner.averageLapMillis), .gold)
        XCTAssertNil(targets.medal(forAverageLapMillis: outcome.ranked.last!.averageLapMillis))
    }

    /// Roughly a third of the field medals, about a tenth Silver or
    /// better, about one in a hundred Gold — ties can only add a few.
    func testMedalSharesMatchTheirPercentiles() {
        let day = challenge()
        let outcome = ExhaustiveSolver.solve(challenge: day)
        let targets = DayTargets.compute(challenge: day, outcome: outcome)
        func share(_ m: Medal) -> Double {
            let n = outcome.ranked.filter {
                (targets.medal(forAverageLapMillis: $0.averageLapMillis) ?? .bronze) >= m
                    && targets.medal(forAverageLapMillis: $0.averageLapMillis) != nil
            }.count
            return Double(n) / Double(outcome.legalCount)
        }
        XCTAssertEqual(share(.gold), 0.01, accuracy: 0.01)
        XCTAssertEqual(share(.silver), 0.10, accuracy: 0.02)
        XCTAssertEqual(share(.bronze), 0.333, accuracy: 0.03)
    }

    func testNextTarget() {
        let t = DayTargets(bestAverageLapMillis: 90_000, goldMillis: 90_300,
                           silverMillis: 90_900, bronzeMillis: 91_800)
        XCTAssertEqual(t.nextTarget(forAverageLapMillis: 92_000)?.medal, .bronze)
        XCTAssertEqual(t.nextTarget(forAverageLapMillis: 92_000)?.gapMillis, 200)
        XCTAssertEqual(t.nextTarget(forAverageLapMillis: 91_000)?.medal, .silver)
        XCTAssertEqual(t.nextTarget(forAverageLapMillis: 90_500)?.medal, .gold)
        XCTAssertNil(t.nextTarget(forAverageLapMillis: 90_000))
    }

    func testAnalysisCarriesTargetsAndMedal() {
        let day = challenge()
        let outcome = ExhaustiveSolver.solve(challenge: day)
        let analysis = DayAnalyzer.analyze(
            challenge: day,
            playerAverageLapMillis: outcome.winner.averageLapMillis,
            outcome: outcome
        )
        XCTAssertEqual(analysis.medal, .gold)
        XCTAssertEqual(analysis.optimalSectorTotalsMillis, analysis.targets?.optimalSectorTotalsMillis)
    }

    // MARK: - Share card

    func testShareCardNeverNamesThePartsOrTheSetup() {
        let day = challenge()
        let picks = GuidedStart.plan(for: day).prefilled.merging(
            [.engineMode: .enginePower, .tires: .tiresSoft, .aerodynamics: .aeroLowDrag,
             .suspension: .suspensionStiff, .gearRatio: .gearShort, .cooling: .coolingLight,
             .brakes: .brakesAggressive, .reliabilityFocus: .reliabilityRisky]
        ) { _, new in new }
        let result = run(picks, day)
        let card = ShareCard.make(
            result: result, challenge: day,
            targets: DayTargets.compute(challenge: day),
            rivals: RivalField.rivals(for: day)
        )
        let text = card.text.lowercased()
        for option in OptionLibrary.allOptions where option.displayName != "Balanced" {
            XCTAssertFalse(text.contains(option.displayName.lowercased()), option.displayName)
        }
        XCTAssertFalse(text.contains(result.setupIdentity.displayText.lowercased()))
        XCTAssertTrue(card.text.contains(ShareCard.appURL))
        XCTAssertFalse(text.contains("f1"))
        XCTAssertFalse(text.contains("formula"))
    }

    func testShareCardPositionMatchesTheClassification() {
        let day = challenge()
        let rivals = RivalField.rivals(for: day)
        let result = run(rivals[3].result.setup.selectedOptions, day) // the Balanced car
        let card = ShareCard.make(result: result, challenge: day, targets: nil, rivals: rivals)
        let you = RaceEntrant(id: "you", name: "You", isPlayer: true, result: result)
        let field = RaceTimeline(entrants: [you] + rivals)
        XCTAssertEqual(card.position, field.classification.firstIndex(of: 0)! + 1)
        XCTAssertEqual(card.fieldSize, 6)
        XCTAssertTrue(card.sectorTiers.isEmpty)
        XCTAssertNil(card.gapText)
    }

    func testShareCardText() {
        let card = ShareCard(
            dayNumber: 232, circuitName: "Mountain", weatherName: "Rain",
            position: 2, fieldSize: 6, medal: .silver,
            sectorTiers: [.optimal, .close, .offPace],
            gapToBestMillis: 840, averageLapMillis: 91_000
        )
        XCTAssertEqual(card.text, """
        PROJECT APEX · Day 232
        Mountain · Rain
        🏁 P2 of 6   🥈 Silver
        🟪🟩🟨   +0.840s to optimal
        \(ShareCard.appURL)
        """)
    }

    // MARK: - Guided first day

    func testGuidedPlanLeavesThreeOpenAndStaysLegal() {
        for budget in [92, 100, 108] {
            for banned in [nil, EngineeringOptionID.enginePower, .tiresSoft, .aeroBalanced] {
                let day = challenge(budget: budget, banned: banned)
                let plan = GuidedStart.plan(for: day)
                XCTAssertEqual(plan.focus.count, 3)
                XCTAssertEqual(plan.prefilled.count, 5)
                XCTAssertTrue(Set(plan.focus).isDisjoint(with: plan.prefilled.keys))
                if let banned { XCTAssertFalse(plan.prefilled.values.contains(banned)) }
                // Any pick in the open systems at its cheapest still fits.
                let spent = plan.prefilled.values.reduce(0) { $0 + OptionLibrary.option($1).cost }
                let cheapest = plan.focus.reduce(0) { sum, c in
                    sum + OptionLibrary.options(in: c, banned: banned).map(\.cost).min()!
                }
                XCTAssertLessThanOrEqual(spent + cheapest, budget)
            }
        }
    }

    func testGuidedPlanIsDeterministic() {
        XCTAssertEqual(GuidedStart.plan(for: challenge()), GuidedStart.plan(for: challenge()))
    }
}
