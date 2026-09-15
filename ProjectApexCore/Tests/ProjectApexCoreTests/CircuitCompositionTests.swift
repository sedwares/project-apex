//
//  CircuitCompositionTests.swift
//  ProjectApexCoreTests
//
//  The sentence printed under the circuit bar strip. It is the only thing
//  that makes the strip legible, so it has to be stable and it has to
//  agree with the bars — both read from `TrackSectionType.family`.
//

import XCTest
@testable import ProjectApexCore

final class CircuitCompositionTests: XCTestCase {

    func testEverySectionTypeHasAFamily() {
        // No default branch in `family`, so this guards the mapping
        // staying exhaustive if a 13th section type is ever added.
        for section in TrackSectionType.allCases {
            XCTAssertTrue(
                TrackSectionFamily.allCases.contains(section.family),
                "\(section) has no family"
            )
        }
    }

    func testHairpinIsACornerNotABrakingZone() {
        // It used to be grouped with braking zones because it LOOKED like
        // caution. Its demand is grip and acceleration first.
        XCTAssertEqual(TrackSectionType.hairpin.family, .corner)
        XCTAssertEqual(TrackSectionType.heavyBrakingZone.family, .braking)
    }

    func testReferenceCircuitSummary() {
        // Reference Ring: 3 straights (long, short, final), 1 braking,
        // 5 corners (medium, hairpin, fast, technical, slow),
        // 1 climb, 1 drop, 1 bumpy.
        let composition = Circuit.reference.sections.composition
        XCTAssertEqual(composition.first?.family, .corner)
        XCTAssertEqual(composition.first?.count, 5)
        XCTAssertEqual(
            Circuit.reference.compositionSummary(),
            "5 corners · 3 straights · 1 braking zone · 1 climb · 1 drop · 1 bumpy sector"
        )
    }

    /// The whole point of dropping the old `limit: 3` default: the line
    /// sits directly above a "N sections" readout, so if it does not add
    /// up to N it reads as a miscount. A Mountain Circuit printed
    /// "7 elevation changes · 2 corners · 1 straight" next to "11 sections".
    func testSummaryAccountsForEverySection() {
        for circuit in [Circuit.reference] {
            let named = circuit.sections.composition.reduce(0) { $0 + $1.count }
            XCTAssertEqual(named, circuit.sections.count)
            // Every family in the summary, so the counts a player can add
            // up match the section total.
            let mentioned = circuit.compositionSummary()
                .components(separatedBy: " · ").count
            XCTAssertEqual(mentioned, circuit.sections.composition.count)
        }
    }

    func testClimbAndDropAreSeparate() {
        // A climb wants power and cooling; a drop wants braking and
        // stability. Merging them hid that on exactly the circuit where
        // it decides the lap.
        XCTAssertEqual(TrackSectionType.elevationClimb.family, .climb)
        XCTAssertEqual(TrackSectionType.elevationDrop.family, .drop)
    }

    func testCountsSumToSectionCount() {
        let total = Circuit.reference.sections.composition
            .reduce(0) { $0 + $1.count }
        XCTAssertEqual(total, Circuit.reference.sections.count)
    }

    func testSingularAtOne() {
        let oneOfEach: [TrackSectionType] = [.longStraight, .heavyBrakingZone, .hairpin]
        // Ties on count break on family order: straight, braking, corner.
        XCTAssertEqual(
            oneOfEach.compositionSummary(),
            "1 straight · 1 braking zone · 1 corner"
        )
    }

    func testSummaryIsDeterministic() {
        let a = Circuit.reference.compositionSummary()
        let b = Circuit.reference.compositionSummary()
        XCTAssertEqual(a, b)
    }

    func testLimitTrimsTheTail() {
        XCTAssertEqual(
            Circuit.reference.compositionSummary(limit: 1),
            "5 corners"
        )
    }
}
