//
//  VehicleProfileTests.swift
//  ProjectApexCoreTests
//

import XCTest
@testable import ProjectApexCore

final class VehicleProfileTests: XCTestCase {

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

    func testProfileHasFiveAxesAllInRange() {
        let profile = VehicleProfile.from(setup: setupA)
        XCTAssertEqual(profile.axes.count, 5)
        for axis in profile.axes {
            XCTAssertTrue((0.0...1.0).contains(axis.fraction), axis.name)
        }
    }

    func testGlassCannonShapeIsVisible() {
        let profile = VehicleProfile.from(setup: setupC)
        func axis(_ name: String) -> Double {
            profile.axes.first { $0.name == name }!.fraction
        }
        XCTAssertGreaterThan(axis("Top Speed"), axis("Tire Life"),
                             "glass cannon: fast, fragile tires")
        XCTAssertGreaterThan(axis("Top Speed"), axis("Reliability"))
    }

    func testProfileIsDeterministic() {
        XCTAssertEqual(VehicleProfile.from(setup: setupC), VehicleProfile.from(setup: setupC))
    }
}
