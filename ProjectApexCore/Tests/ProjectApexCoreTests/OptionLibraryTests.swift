//
//  OptionLibraryTests.swift
//  ProjectApexCoreTests
//
//  Guards the structural invariants of the balance sheet. These tests
//  are meant to keep passing through every tuning iteration — they test
//  the SHAPE of the balance, not specific numbers.
//

import XCTest
@testable import ProjectApexCore

final class OptionLibraryTests: XCTestCase {

    // MARK: - Structure

    func testExactlyEightCategoriesWithThreeOptionsEach() {
        XCTAssertEqual(EngineeringCategoryID.allCases.count, 8)
        XCTAssertEqual(OptionLibrary.allOptions.count, 24)
        for category in EngineeringCategoryID.allCases {
            XCTAssertEqual(
                OptionLibrary.options(in: category).count, 3,
                "\(category.rawValue) must have exactly 3 options"
            )
        }
    }

    func testEveryOptionIDHasExactlyOneDefinition() {
        XCTAssertEqual(OptionLibrary.optionsByID.count, EngineeringOptionID.allCases.count)
        for id in EngineeringOptionID.allCases {
            XCTAssertNotNil(OptionLibrary.optionsByID[id], "missing definition for \(id.rawValue)")
        }
    }

    // MARK: - Cost design invariants (Balance Sheet §2)

    func testCostBounds() {
        // 62, not 64: pass 6 repriced engineEfficient 7 → 5 cr. The
        // OptionLibrary header has said "cheapest legal setup = 62 cr"
        // since that change; this pin did not follow.
        XCTAssertEqual(OptionLibrary.minimumTotalCost, 62)
        XCTAssertEqual(OptionLibrary.maximumTotalCost, 135)
    }

    func testCheapestSetupFitsBudgetAndPremiumOvershoots25to35Percent() {
        let budget = OptionLibrary.referenceBudget
        XCTAssertLessThanOrEqual(OptionLibrary.minimumTotalCost, budget)
        XCTAssertGreaterThan(OptionLibrary.maximumTotalCost, budget)

        let overshootPercent = (OptionLibrary.maximumTotalCost - budget) * 100 / budget
        XCTAssertTrue(
            (25...35).contains(overshootPercent),
            "premium overshoot is \(overshootPercent)%, target band 25–35%"
        )
    }

    func testBudgetBitesButDoesNotStrangle() {
        // Enumerate all 3^8 = 6561 setups; the budget must exclude some
        // but leave a large legal space.
        var affordable = 0
        var total = 0
        enumerateAllSetups { setup in
            total += 1
            if setup.totalCost <= OptionLibrary.referenceBudget { affordable += 1 }
        }
        XCTAssertEqual(total, 6_561)
        XCTAssertGreaterThan(affordable, 2_000, "budget excludes too many setups")
        XCTAssertLessThan(affordable, 6_400, "budget excludes almost nothing")
    }

    // MARK: - Trade-off invariants (Balance Sheet §3)

    func testEveryExtremeOptionHasAtLeastOneDownside() {
        // "Balanced" options may be all-positive (cost is their trade-off);
        // every extreme option must hurt at least one stat.
        let balancedIDs: Set<EngineeringOptionID> = [
            .engineBalanced, .tiresMedium, .aeroBalanced, .suspensionBalanced,
            .gearBalanced, .coolingStandard, .brakesBalanced, .reliabilityBalanced
        ]
        for option in OptionLibrary.allOptions where !balancedIDs.contains(option.id) {
            let hasDownside = option.statEffects.contains { key, delta in
                key.isInverted ? delta > 0 : delta < 0
            }
            XCTAssertTrue(hasDownside, "\(option.id.rawValue) has no downside")
        }
    }

    func testEveryOptionHasAtLeastOneUpside() {
        for option in OptionLibrary.allOptions {
            let hasUpside = option.statEffects.contains { key, delta in
                key.isInverted ? delta < 0 : delta > 0
            }
            XCTAssertTrue(hasUpside, "\(option.id.rawValue) improves nothing")
        }
    }

    // MARK: - Section & weather data sanity

    func testSectionDemandWeightsSumToTenThousand() {
        for section in TrackSectionType.allCases {
            let sum = section.demandWeightsBP.values.reduce(0, +)
            XCTAssertEqual(sum, 10_000, "\(section.rawValue) demand weights sum to \(sum)")
        }
    }

    func testWeatherModifiersAreReasonable() {
        for weather in Weather.allCases {
            for (key, bp) in weather.statModifiersBP {
                XCTAssertTrue(
                    (7_000...13_000).contains(bp),
                    "\(weather.rawValue) modifier for \(key.rawValue) out of sane range: \(bp)"
                )
            }
        }
        XCTAssertTrue(Weather.sunny.statModifiersBP.isEmpty, "sunny is the baseline")
    }

    // MARK: - Helper

    private func enumerateAllSetups(_ body: (PlayerSetup) -> Void) {
        let categories = EngineeringCategoryID.allCases.sorted()
        let optionsPerCategory = categories.map { OptionLibrary.options(in: $0) }
        var indices = [Int](repeating: 0, count: categories.count)

        while true {
            var selection: [EngineeringCategoryID: EngineeringOptionID] = [:]
            for (i, category) in categories.enumerated() {
                selection[category] = optionsPerCategory[i][indices[i]].id
            }
            body(PlayerSetup(challengeId: "test", selectedOptions: selection))

            // Odometer increment
            var pos = indices.count - 1
            while pos >= 0 {
                indices[pos] += 1
                if indices[pos] < 3 { break }
                indices[pos] = 0
                pos -= 1
            }
            if pos < 0 { break }
        }
    }
}
