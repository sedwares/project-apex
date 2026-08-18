//
//  Pass6AdvisorTests.swift
//  ProjectApexCoreTests
//
//  The engineer has to be right, and the debrief has to be able to say
//  what went wrong. Both were measurably broken before pass 6:
//
//  • The old event→swap table made the car SLOWER 592 times out of 922
//    applicable cases (mean +583 ms), and was over budget a further 225
//    times. testAdvisorNeverMakesTheCarSlower and
//    testAdvisorBeatsTheOldFixedSwapTable pin the replacement.
//
//  • Sector feedback compared against the NEUTRAL car — all twelve
//    stats at 1000, no options — which every real build beats by
//    seconds in every sector. So FeedbackEngine's sector weakness line,
//    which only fires on a positive gap, could never fire at all.
//    testWeaknessLineFiresAgainstOptimal pins that fix, and
//    testOldNeutralComparisonIsSilent documents why it was needed.
//

import XCTest
@testable import ProjectApexCore

final class Pass6AdvisorTests: XCTestCase {

    // MARK: - Helpers

    /// A spread of setups across a few days, sampled deterministically
    /// so failures are reproducible.
    private func sampledSetups(
        challenge: DailyChallenge, stride step: Int
    ) -> [PlayerSetup] {
        let legal = SetupEnumerator.legalSetups(
            challengeId: challenge.id,
            budget: challenge.budget,
            banned: challenge.bannedOption
        )
        return legal.enumerated().compactMap { index, setup in
            index % step == 0 ? setup : nil
        }
    }

    private func average(_ setup: PlayerSetup, _ challenge: DailyChallenge) -> Int {
        SimulationEngine.averageLapMillis(
            setup: setup, circuit: challenge.circuit, weather: challenge.weather
        )
    }

    private func cost(_ selections: [EngineeringCategoryID: EngineeringOptionID]) -> Int {
        selections.values.map { OptionLibrary.option($0).cost }.reduce(0, +)
    }

    // MARK: - The advisor is sound

    /// The core guarantee the old table could not make: advice never
    /// makes the car slower, never exceeds the budget, and never
    /// suggests something the stewards banned.
    func testAdvisorNeverMakesTheCarSlower() {
        for day in 1...4 {
            let challenge = ChallengeGenerator.generate(dayNumber: day, dateKey: "day-\(day)")
            for setup in sampledSetups(challenge: challenge, stride: 400) {
                guard let advice = SetupAdvisor.bestAdvice(for: setup, challenge: challenge) else {
                    continue // nothing improves this setup — a legitimate answer
                }
                let before = average(setup, challenge)
                let after = SimulationEngine.averageLapMillis(
                    setup: PlayerSetup(
                        challengeId: challenge.id,
                        selectedOptions: advice.resultingSelections
                    ),
                    circuit: challenge.circuit,
                    weather: challenge.weather
                )

                XCTAssertLessThan(after, before, "advice made the car slower on day \(day)")
                XCTAssertEqual(
                    before - after, advice.gainMillis,
                    "reported gain must be the measured gain"
                )
                XCTAssertGreaterThanOrEqual(
                    advice.gainMillis, SetupAdvisor.minimumWorthwhileGainMillis
                )
                XCTAssertLessThanOrEqual(
                    cost(advice.resultingSelections), challenge.budget,
                    "advice went over budget"
                )
                XCTAssertEqual(advice.resultingSelections.count, 8)
                if let banned = challenge.bannedOption {
                    XCTAssertFalse(
                        advice.resultingSelections.values.contains(banned),
                        "advice suggested a banned option"
                    )
                }
            }
        }
    }

    func testAdvisorIsDeterministic() {
        let challenge = ChallengeGenerator.generate(dayNumber: 3, dateKey: "day-3")
        for setup in sampledSetups(challenge: challenge, stride: 700) {
            let first = SetupAdvisor.bestAdvice(for: setup, challenge: challenge)
            let second = SetupAdvisor.bestAdvice(for: setup, challenge: challenge)
            XCTAssertEqual(first, second)
        }
    }

    func testAdvisorNamesAFundingSourceWhenItNeedsOne() {
        // When the upgrade alone would breach the budget, the advice has
        // to say what to give up — otherwise it's unactionable. At least
        // some sampled cases must be funded pairs, or the two-swap search
        // isn't doing anything.
        var funded = 0, unfunded = 0
        for day in 1...4 {
            let challenge = ChallengeGenerator.generate(dayNumber: day, dateKey: "day-\(day)")
            for setup in sampledSetups(challenge: challenge, stride: 300) {
                guard let advice = SetupAdvisor.bestAdvice(for: setup, challenge: challenge) else { continue }
                if advice.funding == nil { unfunded += 1 } else { funded += 1 }
            }
        }
        XCTAssertGreaterThan(funded, 0, "the two-swap search never fired")
        XCTAssertGreaterThan(unfunded, 0, "single swaps should still win sometimes")
    }

    /// The headline comparison. Marked deprecated so calling the
    /// deprecated API it is measuring doesn't emit a warning.
    @available(*, deprecated)
    func testAdvisorBeatsTheOldFixedSwapTable() {
        var advisorImproved = 0
        var oldImproved = 0, oldWorsened = 0, oldInfeasible = 0

        for day in 1...6 {
            let challenge = ChallengeGenerator.generate(dayNumber: day, dateKey: "day-\(day)")
            for setup in sampledSetups(challenge: challenge, stride: 250) {
                let result = SimulationEngine.simulate(
                    setup: setup, circuit: challenge.circuit, weather: challenge.weather
                )
                // Only cases where the old table had an opinion.
                guard let suggestion = FeedbackEngine.nextTestSuggestion(for: result) else { continue }
                let before = average(setup, challenge)

                var swapped = setup.selectedOptions
                swapped[suggestion.category] = suggestion.option
                if cost(swapped) > challenge.budget || swapped.values.contains(where: {
                    $0 == challenge.bannedOption
                }) {
                    oldInfeasible += 1
                } else {
                    let after = average(
                        PlayerSetup(challengeId: challenge.id, selectedOptions: swapped),
                        challenge
                    )
                    if after < before { oldImproved += 1 } else if after > before { oldWorsened += 1 }
                }

                if SetupAdvisor.bestAdvice(for: setup, challenge: challenge) != nil {
                    advisorImproved += 1
                }
            }
        }

        print("""
        old fixed table: improved \(oldImproved), worsened \(oldWorsened), \
        infeasible \(oldInfeasible) | advisor found a genuine gain \(advisorImproved) times
        """)

        XCTAssertGreaterThan(oldWorsened, 0, "sanity: the old table should still be bad")
        XCTAssertGreaterThan(
            advisorImproved, oldImproved,
            "the advisor must find real gains more often than the fixed table did"
        )
    }

    // MARK: - Sector feedback measured against the optimum

    func testOptimalSetupLosesNothingInAnySector() {
        let challenge = ChallengeGenerator.generate(dayNumber: 5, dateKey: "day-5")
        let outcome = ExhaustiveSolver.solve(challenge: challenge)
        let optimalRun = SimulationEngine.simulate(
            setup: outcome.winner.setup, circuit: challenge.circuit, weather: challenge.weather
        )
        let totals = optimalRun.sectorResults.map(\.totalMillis)

        let lost = FeedbackEngine.sectorsLostToOptimal(
            result: optimalRun, optimalSectorTotalsMillis: totals
        )
        XCTAssertEqual(lost, [0, 0, 0])

        // And the strength line should recognise it rather than compare
        // to a car with no parts fitted.
        let strengths = FeedbackEngine.strengths(result: optimalRun, lostToOptimal: lost)
        XCTAssertTrue(
            strengths.contains { $0.contains("perfect") },
            "expected a 'perfect' sector line, got \(strengths)"
        )
    }

    /// The fix: a mid-field setup now gets told where its lap went.
    func testWeaknessLineFiresAgainstOptimal() {
        let challenge = ChallengeGenerator.generate(dayNumber: 5, dateKey: "day-5")
        let outcome = ExhaustiveSolver.solve(challenge: challenge)
        let midfield = outcome.ranked[outcome.legalCount / 2].setup

        let run = SimulationEngine.simulate(
            setup: midfield, circuit: challenge.circuit, weather: challenge.weather
        )
        let optimalRun = SimulationEngine.simulate(
            setup: outcome.winner.setup, circuit: challenge.circuit, weather: challenge.weather
        )
        let lost = FeedbackEngine.sectorsLostToOptimal(
            result: run, optimalSectorTotalsMillis: optimalRun.sectorResults.map(\.totalMillis)
        )

        XCTAssertNotNil(lost)
        XCTAssertGreaterThan(lost!.reduce(0, +), 0, "a mid-field car must have lost time somewhere")

        let weaknesses = FeedbackEngine.weaknesses(
            result: run, weather: challenge.weather, lostToOptimal: lost
        )
        XCTAssertTrue(
            weaknesses.contains { $0.contains("Sector") },
            "the debrief must be able to name the sector that cost the lap; got \(weaknesses)"
        )
    }

    /// Documents the bug this replaced: against the neutral car, a good
    /// setup produces NO sector weakness line at all, because no gap is
    /// ever positive. Keep this test — if it starts failing, the neutral
    /// baseline has changed and the old comparison may be worth
    /// revisiting.
    func testOldNeutralComparisonIsSilent() {
        let challenge = ChallengeGenerator.generate(dayNumber: 5, dateKey: "day-5")
        let outcome = ExhaustiveSolver.solve(challenge: challenge)
        let run = SimulationEngine.simulate(
            setup: outcome.winner.setup, circuit: challenge.circuit, weather: challenge.weather
        )

        XCTAssertTrue(
            run.sectorResults.allSatisfy { $0.gapMillis < 0 },
            "the optimal car should beat the neutral car in every sector"
        )
        let weaknesses = FeedbackEngine.weaknesses(
            result: run, weather: challenge.weather, lostToOptimal: nil
        )
        XCTAssertFalse(
            weaknesses.contains { $0.contains("Sector") },
            "neutral-relative weaknesses can't fire — that was the bug"
        )
    }

    // MARK: - The report says each thing once

    func testObservationTextOmitsTheRecommendation() {
        let challenge = ChallengeGenerator.generate(dayNumber: 2, dateKey: "day-2")
        var selections: [EngineeringCategoryID: EngineeringOptionID] = [:]
        for category in EngineeringCategoryID.allCases {
            let options = OptionLibrary.options(in: category, banned: challenge.bannedOption)
            selections[category] = options.first!.id
        }
        let setup = PlayerSetup(challengeId: challenge.id, selectedOptions: selections)
        let result = SimulationEngine.simulate(
            setup: setup, circuit: challenge.circuit, weather: challenge.weather
        )
        let feedback = FeedbackEngine.generate(result: result, challenge: challenge)

        XCTAssertTrue(feedback.reportText.contains(feedback.recommendation))
        XCTAssertFalse(
            feedback.observationText.contains(feedback.recommendation),
            "observationText exists precisely so the debrief doesn't print the "
                + "recommendation twice when the Next Test card is showing"
        )
    }
}
