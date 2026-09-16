//
//  SetupValidatorTests.swift
//  ProjectApexCoreTests
//

import XCTest
@testable import ProjectApexCore

final class SetupValidatorTests: XCTestCase {

    // Reference Setup A: all-balanced, cost 88 (see VehicleBuilderTests).
    private var setupA: PlayerSetup {
        PlayerSetup(challengeId: "apex-test-001", selectedOptions: [
            .engineMode: .engineBalanced,
            .tires: .tiresMedium,
            .aerodynamics: .aeroBalanced,
            .suspension: .suspensionBalanced,
            .gearRatio: .gearBalanced,
            .cooling: .coolingStandard,
            .brakes: .brakesBalanced,
            .reliabilityFocus: .reliabilityBalanced
        ])
    }

    // Reference Setup B: all-premium, cost 118 — deliberately over budget.
    private var setupB: PlayerSetup {
        PlayerSetup(challengeId: "apex-test-001", selectedOptions: [
            .engineMode: .enginePower,          // 25
            .tires: .tiresSoft,                 // 21
            .aerodynamics: .aeroLowDrag,        // 13 (pass 6 reprice, was 16)
            .suspension: .suspensionStiff,      // 15
            .gearRatio: .gearLong,              // 14
            .cooling: .coolingLight,            // 6
            .brakes: .brakesAggressive,         // 17
            .reliabilityFocus: .reliabilityRisky // 7
        ])
    }

    func testBalancedSetupIsLegal() {
        XCTAssertEqual(setupA.totalCost, 88)
        XCTAssertTrue(SetupValidator.isLegal(setupA, budget: 100))
        XCTAssertTrue(SetupValidator.validate(setupA, budget: 100).isEmpty)
    }

    func testOverBudgetSetupIsRejectedWithExactError() {
        XCTAssertEqual(setupB.totalCost, 118)
        let errors = SetupValidator.validate(setupB, budget: 100)
        XCTAssertEqual(errors, [.overBudget(totalCost: 118, budget: 100)])
    }

    func testMissingCategoryIsReported() {
        var options = setupA.selectedOptions
        options[.cooling] = nil
        let incomplete = PlayerSetup(challengeId: "apex-test-001", selectedOptions: options)
        let errors = SetupValidator.validate(incomplete, budget: 100)
        XCTAssertTrue(errors.contains(.missingCategory(.cooling)))
    }

    func testWrongCategoryKeyingIsReported() {
        // Key hard tires under engineMode — tamper/corruption scenario.
        var options = setupA.selectedOptions
        options[.engineMode] = .tiresHard
        let tampered = PlayerSetup(challengeId: "apex-test-001", selectedOptions: options)
        let errors = SetupValidator.validate(tampered, budget: 100)
        XCTAssertTrue(errors.contains(
            .optionCategoryMismatch(category: .engineMode, option: .tiresHard)
        ))
    }

    // MARK: - Canonical encoding (wire format — pin exactly)

    func testCanonicalEncodingIsExactAndSorted() {
        let encoded = CanonicalSetupEncoder.encode(setupA)
        XCTAssertEqual(
            encoded,
            "aerodynamics=aeroBalanced|brakes=brakesBalanced|cooling=coolingStandard|"
            + "engineMode=engineBalanced|gearRatio=gearBalanced|"
            + "reliabilityFocus=reliabilityBalanced|suspension=suspensionBalanced|"
            + "tires=tiresMedium"
        )
    }

    func testCanonicalEncodingIsInsertionOrderIndependent() {
        // Same selections, different construction order → same encoding.
        let reversed = PlayerSetup(challengeId: "apex-test-001", selectedOptions: [
            .reliabilityFocus: .reliabilityBalanced,
            .brakes: .brakesBalanced,
            .cooling: .coolingStandard,
            .gearRatio: .gearBalanced,
            .suspension: .suspensionBalanced,
            .aerodynamics: .aeroBalanced,
            .tires: .tiresMedium,
            .engineMode: .engineBalanced
        ])
        XCTAssertEqual(
            CanonicalSetupEncoder.encode(reversed),
            CanonicalSetupEncoder.encode(setupA)
        )
    }

    // MARK: - Codable wire format (Firestore readability)

    func testSelectedOptionsEncodeAsKeyedObjectNotArray() throws {
        let data = try JSONEncoder().encode(setupA)
        let json = String(decoding: data, as: UTF8.self)

        // CodingKeyRepresentable must produce a keyed object:
        // "engineMode":"engineBalanced" — not Codable's flat-array fallback.
        XCTAssertTrue(json.contains("\"engineMode\""),
                      "selectedOptions did not encode as a keyed object: \(json)")
        XCTAssertTrue(json.contains("\"engineBalanced\""))

        let decoded = try JSONDecoder().decode(PlayerSetup.self, from: data)
        XCTAssertEqual(decoded, setupA)
    }
}
