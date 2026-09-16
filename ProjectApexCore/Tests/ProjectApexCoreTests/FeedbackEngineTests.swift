//
//  FeedbackEngineTests.swift
//  ProjectApexCoreTests
//

import XCTest
@testable import ProjectApexCore

final class FeedbackEngineTests: XCTestCase {

    private var setupA: PlayerSetup {
        PlayerSetup(challengeId: "t", selectedOptions: [
            .engineMode: .engineBalanced, .tires: .tiresMedium,
            .aerodynamics: .aeroBalanced, .suspension: .suspensionBalanced,
            .gearRatio: .gearBalanced, .cooling: .coolingStandard,
            .brakes: .brakesBalanced, .reliabilityFocus: .reliabilityBalanced
        ])
    }

    private var setupC: PlayerSetup {
        PlayerSetup(challengeId: "t", selectedOptions: [
            .engineMode: .enginePower, .tires: .tiresSoft,
            .aerodynamics: .aeroLowDrag, .suspension: .suspensionSoft,
            .gearRatio: .gearLong, .cooling: .coolingLight,
            .brakes: .brakesBalanced, .reliabilityFocus: .reliabilityRisky
        ])
    }

    private func feedback(for setup: PlayerSetup, weather: Weather) -> EngineerFeedback {
        let result = SimulationEngine.simulate(setup: setup, circuit: .reference, weather: weather)
        return FeedbackEngine.generate(
            result: result, weather: weather, archetype: Circuit.reference.archetype
        )
    }

    func testGlassCannonGetsHeatPriorityRecommendation() {
        let fb = feedback(for: setupC, weather: .sunny)
        // Heat is the top-priority problem for Setup C (deficit 390).
        // Case-insensitive: the copy says "Cooling capacity or a calmer
        // engine mode". The assertion was pinning a lowercase 'c' that
        // a rewrite capitalised — the behaviour was always right.
        XCTAssertTrue(fb.recommendation.lowercased().contains("cooling"),
                      "expected cooling recommendation, got: \(fb.recommendation)")
        XCTAssertTrue(fb.weaknesses.contains { $0.contains("heat") || $0.contains("Cooling") })
        XCTAssertTrue(fb.weaknesses.contains { $0.contains("tire") || $0.contains("Tire") })
        XCTAssertTrue(fb.weaknesses.contains { $0.contains("Reliability") })
        // Its straight-line speed is real.
        XCTAssertTrue(fb.strengths.contains { $0.contains("straight-line") })
    }

    func testHotWeatherChangesTheWording() {
        let sunny = feedback(for: setupC, weather: .sunny)
        let hot = feedback(for: setupC, weather: .hot)
        XCTAssertNotEqual(sunny.recommendation, hot.recommendation)
        XCTAssertTrue(hot.recommendation.contains("hot") || hot.recommendation.contains("Heavy cooling"))
    }

    func testBalancedSetupGetsCleanRunNudge() {
        let fb = feedback(for: setupA, weather: .sunny)
        XCTAssertTrue(fb.recommendation.hasPrefix("Clean run."),
                      "expected archetype nudge, got: \(fb.recommendation)")
        // No decay complaints for the balanced car.
        XCTAssertFalse(fb.weaknesses.contains { $0.contains("overheated") || $0.contains("Reliability") })
        // Consistency strength should fire (tight lap 2→3 delta, no decay events).
        XCTAssertTrue(fb.strengths.contains { $0.contains("held together") })
    }

    func testFeedbackIsDeterministic() {
        let first = feedback(for: setupC, weather: .windy)
        for _ in 0..<20 {
            XCTAssertEqual(feedback(for: setupC, weather: .windy), first)
        }
    }

    func testPreRaceBriefingCoversAllConditionsDeterministically() {
        for archetype in CircuitArchetype.allCases {
            for weather in Weather.allCases {
                let first = FeedbackEngine.preRaceBriefing(archetype: archetype, weather: weather)
                XCTAssertFalse(first.isEmpty)
                XCTAssertEqual(first, FeedbackEngine.preRaceBriefing(archetype: archetype, weather: weather))
            }
        }
    }

    func testReportTextEndsWithRecommendation() {
        let fb = feedback(for: setupC, weather: .hot)
        XCTAssertTrue(fb.reportText.hasSuffix(fb.recommendation))
        XCTAssertTrue(fb.reportText.count >= fb.recommendation.count)
    }

    func testPreRaceBriefingCoversAllCombinations() {
        for archetype in CircuitArchetype.allCases {
            for weather in Weather.allCases {
                let brief = FeedbackEngine.preRaceBriefing(archetype: archetype, weather: weather)
                XCTAssertFalse(brief.isEmpty)
                XCTAssertTrue(brief.lowercased().contains("competitive solutions"))
                XCTAssertEqual(brief, FeedbackEngine.preRaceBriefing(archetype: archetype, weather: weather))
            }
        }
    }

    func testReportTextComposesFromFeedback() {
        let fb = feedback(for: setupC, weather: .hot)
        let report = FeedbackEngine.reportText(for: fb)
        XCTAssertTrue(report.contains(fb.recommendation), "report must end with the actionable line")
        XCTAssertFalse(report.isEmpty)
    }

    func testEffectSummaryRespectsStatSemantics() {
        let power = OptionLibrary.option(.enginePower)
        // Power's biggest raw delta is +230 heat — which is a DOWNSIDE
        // (semantics: more heat hurts). Label carries the true direction:
        // "+Heat" (more heat), colored orange by the UI.
        XCTAssertEqual(OptionEffectSummary.topDownside(of: power), "+Heat")
        XCTAssertEqual(OptionEffectSummary.topUpside(of: power), "+Power")

        let efficient = OptionLibrary.option(.engineEfficient)
        // Efficient: −120 heat is its biggest UPSIDE (less heat is good) —
        // labeled with the stat's true direction, colored green by the UI.
        XCTAssertEqual(OptionEffectSummary.topUpside(of: efficient), "−Heat")
        XCTAssertNotNil(OptionEffectSummary.topDownside(of: efficient))

        // Every option must present at least one honest downside or be
        // a pure-middle option — never zero information.
        for option in OptionLibrary.allOptions {
            XCTAssertTrue(
                OptionEffectSummary.topUpside(of: option) != nil
                || OptionEffectSummary.topDownside(of: option) != nil,
                "\(option.id.rawValue) has no effect summary at all"
            )
        }
    }


    func testRadioFeedTellsTheTruth() {
        let hotC = SimulationEngine.simulate(setup: setupC, circuit: .reference, weather: .hot)
        let radioC = FeedbackEngine.radioMessages(for: hotC, weather: .hot)
        XCTAssertTrue(radioC.contains { $0.text.contains("Temps climbing") },
                      "glass cannon in heat must get the heat call")
        XCTAssertFalse(radioC.contains { $0.text.contains("holding together") })

        let sunnyA = SimulationEngine.simulate(setup: setupA, circuit: .reference, weather: .sunny)
        let radioA = FeedbackEngine.radioMessages(for: sunnyA, weather: .sunny)
        XCTAssertTrue(radioA.contains { $0.text.contains("holding together") })

        // Ordering + determinism.
        XCTAssertEqual(radioC, FeedbackEngine.radioMessages(for: hotC, weather: .hot))
        let sorted = radioC.sorted { ($0.lap, $0.atFraction) < ($1.lap, $1.atFraction) }
        XCTAssertEqual(radioC, sorted, "feed must already be in broadcast order")
    }

    func testNextTestSuggestionMatchesRecommendation() {
        let hot = SimulationEngine.simulate(setup: setupC, circuit: .reference, weather: .hot)
        let suggestion = FeedbackEngine.nextTestSuggestion(for: hot)
        XCTAssertEqual(suggestion?.category, .cooling)
        XCTAssertEqual(suggestion?.option, .coolingHeavy)
    }

    func testNextTestSuggestionNilOnCleanRun() {
        let clean = SimulationEngine.simulate(setup: setupA, circuit: .reference, weather: .sunny)
        XCTAssertNil(FeedbackEngine.nextTestSuggestion(for: clean))
    }

    /// The calibration that the four clean-run failures were really
    /// about: a warning has to mean "worse than having no plan", so the
    /// threshold must sit above the wear of a car with no tyre
    /// investment at all. At 280 it sat below, and fired on the median
    /// setup. See SimulationEngine.Tuning.wearEventThresholdBP.
    func testWearWarningThresholdIsAboveTheBaselineCar() {
        let baselineWear = min(
            (SimulationEngine.Tuning.wearReference - FixedPoint.statBaseline)
                * SimulationEngine.Tuning.wearPenaltyNumerator
                / SimulationEngine.Tuning.wearPenaltyDenominator,
            SimulationEngine.Tuning.wearPenaltyCapBP
        )
        XCTAssertGreaterThan(
            SimulationEngine.Tuning.wearEventThresholdBP, baselineWear,
            "a car with no tyre investment scores \(baselineWear) bp; a warning "
                + "that fires below that fires for existing"
        )
    }

    func testRecommendationIsNeverEmpty() {
        for setup in [setupA, setupC] {
            for weather in Weather.allCases {
                let fb = feedback(for: setup, weather: weather)
                XCTAssertFalse(fb.recommendation.isEmpty)
            }
        }
    }
}
