//
//  PitWallRemarkTests.swift
//  ProjectApexCoreTests
//

import XCTest
@testable import ProjectApexCore

final class PitWallRemarkTests: XCTestCase {

    private let allBalanced: [EngineeringCategoryID: EngineeringOptionID] = [
        .engineMode: .engineBalanced, .tires: .tiresMedium,
        .aerodynamics: .aeroBalanced, .suspension: .suspensionBalanced,
        .gearRatio: .gearBalanced, .cooling: .coolingStandard,
        .brakes: .brakesBalanced, .reliabilityFocus: .reliabilityBalanced
    ]

    private func remark(
        _ pick: EngineeringOptionID,
        _ selections: [EngineeringCategoryID: EngineeringOptionID],
        weather: Weather = .sunny,
        budget: Int = 100
    ) -> String {
        PitWallRemark.after(
            picking: pick, selections: selections,
            circuit: .reference, weather: weather, budget: budget
        )
    }

    func testOverBudgetWinsOverEverything() {
        let text = remark(.brakesBalanced, allBalanced, budget: 40)
        XCTAssertTrue(text.contains("over the budget"), text)
    }

    func testCompleteSetupSaysAllEight() {
        let text = remark(.brakesBalanced, allBalanced, budget: 200)
        XCTAssertTrue(text.hasPrefix("All eight systems"), text)
    }

    func testImpossibleBudgetIsCalledOut() {
        let one: [EngineeringCategoryID: EngineeringOptionID] = [.engineMode: .enginePower]
        let cost = OptionLibrary.option(.enginePower).cost
        let text = remark(.enginePower, one, budget: cost + 1)
        XCTAssertTrue(text.contains("won't fit"), text)
    }

    func testDeterministic() {
        let partial: [EngineeringCategoryID: EngineeringOptionID] = [.aerodynamics: .aeroLowDrag]
        XCTAssertEqual(remark(.aeroLowDrag, partial), remark(.aeroLowDrag, partial))
    }

    /// The setup is the puzzle answer. Across every option, weather and
    /// archetype, the remark may describe a pick but never grade it as
    /// the winning one.
    func testNeverClaimsToKnowTheAnswer() {
        let banned = ["optimal", "best", "perfect", "correct", "the right", "winning", "fastest"]
        for archetype in CircuitArchetype.allCases {
            var rng = SplitMix64(seed: 99)
            let circuit = TrackGenerator.generate(archetype: archetype, id: "t", name: "t", rng: &rng)
            for weather in Weather.allCases {
                for option in OptionLibrary.allOptions {
                    let text = PitWallRemark.after(
                        picking: option.id,
                        selections: [option.category: option.id],
                        circuit: circuit, weather: weather, budget: 100
                    ).lowercased()
                    XCTAssertFalse(text.isEmpty)
                    for word in banned {
                        XCTAssertFalse(text.contains(word), "\(option.id) / \(weather): \(text)")
                    }
                }
            }
        }
    }

    func testStrongestEffectRespectsInvertedStats() {
        // Light cooling sheds weight: a negative weight delta is an UPSIDE.
        let light = OptionLibrary.option(.coolingLight)
        if let weight = light.statEffects[.weight], weight < 0 {
            XCTAssertNotEqual(PitWallRemark.strongestEffect(of: light, helping: false), .weight)
        }
    }
}
