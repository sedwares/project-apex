//
//  BatchValidationTests.swift
//  ProjectApexCoreTests
//
//  THE PHASE 2 EXIT GATE.
//
//  testDiversityGatePasses runs the full 30-challenge exhaustive batch
//  (~200k simulations) and asserts the Addendum §F criteria. It is
//  EXPECTED to fail on early balance drafts — that is the tuning loop
//  working, not a code bug. On failure, read the printed report, tune
//  OptionLibrary / section weights / engine Tuning, and re-run.
//
//  Runtime: seconds in Release, may take a minute+ in Debug. Prefer
//  the My Mac destination.
//

import XCTest
@testable import ProjectApexCore

final class BatchValidationTests: XCTestCase {

    // MARK: - Solver mechanics (fast, must always pass)

    func testSolverRanksAndComputesMinimum() {
        let challenge = ChallengeGenerator.generate(dayNumber: 1, dateKey: "day-1")
        let outcome = ExhaustiveSolver.solve(challenge: challenge)

        XCTAssertGreaterThan(outcome.legalCount, 0)
        XCTAssertLessThanOrEqual(outcome.legalCount, SetupEnumerator.totalSetupCount)
        // Ranking is non-decreasing.
        for i in 1..<min(outcome.ranked.count, 200) {
            XCTAssertLessThanOrEqual(
                outcome.ranked[i - 1].averageLapMillis,
                outcome.ranked[i].averageLapMillis
            )
        }
        XCTAssertEqual(outcome.minPossibleAverageLapMillis, outcome.winner.averageLapMillis)
        // Every legal setup respects the budget.
        XCTAssertTrue(outcome.ranked.allSatisfy { $0.setup.totalCost <= challenge.budget })
    }

    func testEnumeratorCoversFullSpace() {
        var count = 0
        var seen = Set<String>()
        SetupEnumerator.forEachSetup(challengeId: "t") { setup in
            count += 1
            seen.insert(CanonicalSetupEncoder.encode(setup))
        }
        XCTAssertEqual(count, 6_561)
        XCTAssertEqual(seen.count, 6_561) // all distinct
    }

    func testSolverIsDeterministic() {
        let challenge = ChallengeGenerator.generate(dayNumber: 7, dateKey: "day-7")
        let a = ExhaustiveSolver.solve(challenge: challenge)
        let b = ExhaustiveSolver.solve(challenge: challenge)
        XCTAssertEqual(a.ranked.prefix(50).map(\.setup), b.ranked.prefix(50).map(\.setup))
        XCTAssertEqual(a.minPossibleAverageLapMillis, b.minPossibleAverageLapMillis)
    }

    // MARK: - THE GATE (may fail during balance tuning — read the report)

    func testDiversityGatePasses() {
        let report = BatchValidator.run(dayNumbers: 1...30)

        // Always print the full report — it is the tuning instrument.
        print("\n\(report.renderText())\n")

        XCTAssertTrue(
            report.gate.passed,
            "DIVERSITY GATE FAILED — this blocks UI work, not the commit. "
            + "Failures:\n" + report.gate.failures.joined(separator: "\n")
        )
    }
}
