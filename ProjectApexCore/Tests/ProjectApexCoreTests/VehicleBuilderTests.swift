//
//  VehicleBuilderTests.swift
//  ProjectApexCoreTests
//
//  EXACT-OUTPUT PINS. These tests assert precise integer results for
//  reference setups. If a refactor or balance change alters any number,
//  a test fails loudly — that is the point. After deliberate balance
//  tuning, update the pinned values in the same commit as the tuning.
//

import XCTest
@testable import ProjectApexCore

final class VehicleBuilderTests: XCTestCase {

    // Reference Setup A: all-balanced. Cost 88.
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

    // Reference Setup C: aggressive "glass cannon" build. Cost 107
    // (over the 100 reference budget after tuning pass 1 — used with
    // a 110 budget in legality checks; the sim itself doesn't gate).
    private var setupC: PlayerSetup {
        PlayerSetup(challengeId: "apex-test-001", selectedOptions: [
            .engineMode: .enginePower,           // 25
            .tires: .tiresSoft,                  // 21
            .aerodynamics: .aeroLowDrag,         // 16
            .suspension: .suspensionSoft,        // 9
            .gearRatio: .gearLong,               // 14
            .cooling: .coolingLight,             // 6
            .brakes: .brakesBalanced,            // 11
            .reliabilityFocus: .reliabilityRisky // 7
        ])
    }

    // MARK: - Exact stat pins

    func testSetupA_ExactStats() {
        XCTAssertEqual(setupA.totalCost, 88)
        let stats = VehicleBuilder.build(from: setupA)

        XCTAssertEqual(stats.power, 1_040)
        XCTAssertEqual(stats.acceleration, 1_050)
        XCTAssertEqual(stats.topSpeed, 1_060)
        XCTAssertEqual(stats.grip, 1_055)
        XCTAssertEqual(stats.braking, 1_040)
        XCTAssertEqual(stats.stability, 1_045)
        XCTAssertEqual(stats.cooling, 1_050)
        XCTAssertEqual(stats.reliability, 1_030)
        XCTAssertEqual(stats.tireDurability, 1_030)
        XCTAssertEqual(stats.weight, 1_000)
        XCTAssertEqual(stats.aeroEfficiency, 1_040)
        XCTAssertEqual(stats.heatGeneration, 1_030)
    }

    func testSetupC_ExactStats() {
        XCTAssertEqual(setupC.totalCost, 109)
        XCTAssertTrue(SetupValidator.isLegal(setupC, budget: 110))
        let stats = VehicleBuilder.build(from: setupC)

        XCTAssertEqual(stats.power, 1_130)
        XCTAssertEqual(stats.acceleration, 970)
        XCTAssertEqual(stats.topSpeed, 1_285)
        XCTAssertEqual(stats.grip, 1_140)
        XCTAssertEqual(stats.braking, 1_040)
        XCTAssertEqual(stats.stability, 900)
        XCTAssertEqual(stats.cooling, 880)
        XCTAssertEqual(stats.reliability, 770)
        XCTAssertEqual(stats.tireDurability, 820)
        XCTAssertEqual(stats.weight, 880)
        XCTAssertEqual(stats.aeroEfficiency, 1_070)
        XCTAssertEqual(stats.heatGeneration, 1_270)
        // heat deficit vs cooling 880: 390 → the gamble is real
    }

    func testBuildIsDeterministic() {
        let first = VehicleBuilder.build(from: setupC)
        for _ in 0..<100 {
            XCTAssertEqual(VehicleBuilder.build(from: setupC), first)
        }
    }

    // MARK: - Setup identity pins

    func testSetupA_IdentityIsBalanced() {
        let identity = SetupIdentity.derive(from: VehicleBuilder.build(from: setupA))
        XCTAssertEqual(identity.tags, [.balanced])
        XCTAssertEqual(identity.displayText, "Balanced")
    }

    func testSetupC_IdentityIsHighSpeedCornerFocusedHeatRisk() {
        let identity = SetupIdentity.derive(from: VehicleBuilder.build(from: setupC))
        XCTAssertEqual(identity.tags, [.highSpeed, .cornerFocused, .heatRisk])
        XCTAssertEqual(identity.displayText, "High Speed / Corner Focused / Heat Risk")
    }

    // MARK: - Weather application pins

    func testHotWeatherOnBaseline_ExactValues() {
        let modified = Weather.hot.apply(to: .baseline)
        XCTAssertEqual(modified.heatGeneration, 1_150) // 1000 * 11500 / 10000
        XCTAssertEqual(modified.tireDurability, 920)   // 1000 * 9200 / 10000
        XCTAssertEqual(modified.grip, 1_000)           // untouched
    }

    func testRainOnSetupC_ExactValues() {
        let stats = Weather.rain.apply(to: VehicleBuilder.build(from: setupC))
        XCTAssertEqual(stats.grip, 934)     // 1140 * 8200 / 10000 = 934 (truncated)
        XCTAssertEqual(stats.braking, 936)  // 1040 * 9000 / 10000
        XCTAssertEqual(stats.topSpeed, 1_285) // untouched
    }

    // MARK: - Normative rounding rule

    func testBasisPointTruncationTowardZero() {
        // 1150 * 8200 = 9_430_000 → / 10_000 = 943 exactly
        XCTAssertEqual(FixedPoint.applyBasisPoints(1_150, 8_200), 943)
        // 999 * 9999 = 9_989_001 → 998.9001 → truncates to 998
        XCTAssertEqual(FixedPoint.applyBasisPoints(999, 9_999), 998)
        // Identity modifier
        XCTAssertEqual(FixedPoint.applyBasisPoints(1_234, 10_000), 1_234)
        // Zero value
        XCTAssertEqual(FixedPoint.applyBasisPoints(0, 12_345), 0)
    }

    func testLapTimeFormatting() {
        XCTAssertEqual(FixedPoint.formatLapTime(millis: 84_382), "1:24.382")
        XCTAssertEqual(FixedPoint.formatLapTime(millis: 59_999), "0:59.999")
        XCTAssertEqual(FixedPoint.formatLapTime(millis: 60_000), "1:00.000")
        XCTAssertEqual(FixedPoint.formatLapTime(millis: 0), "0:00.000")
    }
}
