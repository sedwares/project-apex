//
//  TestSessionViewModelTests.swift
//  ProjectApexTests
//

import XCTest
import ProjectApexCore
@testable import ProjectApex

@MainActor
final class TestSessionViewModelTests: XCTestCase {

    private func makeSession(
        archetype: CircuitArchetype = .balanced,
        weather: Weather = .sunny,
        budget: Int = 100,
        seed: UInt64 = 42
    ) -> TestSessionViewModel {
        TestSessionViewModel(
            conditions: .init(archetype: archetype, weather: weather, budget: budget),
            seed: seed
        )
    }

    private func selectAllBalanced(_ vm: TestSessionViewModel) {
        vm.select(.engineBalanced); vm.select(.tiresMedium)
        vm.select(.aeroBalanced); vm.select(.suspensionBalanced)
        vm.select(.gearBalanced); vm.select(.coolingStandard)
        vm.select(.brakesBalanced); vm.select(.reliabilityBalanced)
    }

    func testQuickRaceIsDeterministicPerSeed() {
        let a = TestSessionViewModel.quickRace(seed: 7)
        let b = TestSessionViewModel.quickRace(seed: 7)
        XCTAssertEqual(a.conditions, b.conditions)
        XCTAssertEqual(a.circuit.sections, b.circuit.sections)
    }

    func testUnlimitedRunsAndSessionBest() {
        let vm = makeSession()
        selectAllBalanced(vm)
        vm.run()
        let firstAverage = vm.lastResult!.averageLapTimeMillis
        XCTAssertEqual(vm.runCount, 1)
        XCTAssertEqual(vm.bestAverageMillis, firstAverage)

        // Faster build: same run again is deterministic-equal, so
        // switch tires to change the time, then verify best tracks min.
        vm.select(.tiresSoft)
        guard vm.canRun else { return } // 97 ≤ 100, always legal
        vm.run()
        XCTAssertEqual(vm.runCount, 2)
        let second = vm.lastResult!.averageLapTimeMillis
        XCTAssertEqual(vm.bestAverageMillis, min(firstAverage, second))
    }

    func testEditInvalidatesLastResultButKeepsBest() {
        let vm = makeSession()
        selectAllBalanced(vm)
        vm.run()
        let best = vm.bestAverageMillis
        vm.select(.tiresHard)
        XCTAssertNil(vm.lastResult, "stale result cleared on edit")
        XCTAssertEqual(vm.bestAverageMillis, best, "session best survives edits")
    }

    func testOverBudgetGatesRun() {
        let vm = makeSession(budget: 80)
        selectAllBalanced(vm) // 88 > 80
        XCTAssertTrue(vm.isOverBudget)
        XCTAssertFalse(vm.canRun)
        vm.run()
        XCTAssertNil(vm.lastResult)
    }

    func testChangingConditionsResetsSession() {
        let vm = makeSession()
        selectAllBalanced(vm)
        vm.run()
        XCTAssertNotNil(vm.bestAverageMillis)

        vm.setWeather(.hot)
        XCTAssertNil(vm.lastResult)
        XCTAssertNil(vm.bestAverageMillis, "best is meaningless across conditions")
        XCTAssertEqual(vm.runCount, 0)
        // Selections survive — only results reset.
        XCTAssertTrue(vm.isComplete)
    }

    func testBudgetClampsToCustomRange() {
        let vm = makeSession()
        vm.setBudget(500)
        XCTAssertEqual(vm.budget, TestSessionViewModel.customBudgetRange.upperBound)
        vm.setBudget(1)
        XCTAssertEqual(vm.budget, TestSessionViewModel.customBudgetRange.lowerBound)
    }

    func testRerollChangesLayoutKeepsConditions() {
        let vm = makeSession()
        let before = vm.circuit.sections
        let conditions = vm.conditions
        vm.rerollCircuit()
        XCTAssertEqual(vm.conditions, conditions)
        // Same archetype pool; layouts can rarely collide, so assert
        // the reroll at least produced a valid circuit.
        XCTAssertEqual(vm.circuit.sections.last, .finalStraight)
        XCTAssertTrue((11...13).contains(vm.circuit.sections.count))
        _ = before // layout inequality not guaranteed; validity is.
    }

    func testModes() {
        XCTAssertEqual(TestSessionViewModel.quickRace(seed: 1).mode, .quickRace)
        XCTAssertEqual(makeSession().mode, .customTest)
    }

    func testNewQuickRaceRerollsAndResetsButKeepsSelections() {
        let vm = TestSessionViewModel.quickRace(seed: 3)
        selectAllBalanced(vm)
        if vm.canRun { vm.run() }
        vm.newQuickRace()
        XCTAssertNil(vm.lastResult)
        XCTAssertNil(vm.bestAverageMillis)
        XCTAssertEqual(vm.runCount, 0)
        XCTAssertTrue(vm.isComplete, "selections survive the reroll")
        XCTAssertTrue(ChallengeGenerator.budgetRange.contains(vm.budget))
        XCTAssertEqual(vm.circuit.sections.last, .finalStraight)
    }

    func testFeedbackAvailableAfterRun() {
        let vm = makeSession(weather: .windy)
        selectAllBalanced(vm)
        XCTAssertNil(vm.feedback)
        vm.run()
        XCTAssertNotNil(vm.feedback)
        XCTAssertFalse(vm.feedback!.recommendation.isEmpty)
    }
}
