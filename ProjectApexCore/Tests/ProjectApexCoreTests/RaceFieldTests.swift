//
//  RaceFieldTests.swift
//  ProjectApexCoreTests
//

import XCTest
@testable import ProjectApexCore

final class RaceFieldTests: XCTestCase {

    private func challenge(budget: Int = 100, banned: EngineeringOptionID? = nil) -> DailyChallenge {
        DailyChallenge(
            id: "t", dateKey: "test-day", seed: 1, circuit: .reference, weather: .sunny,
            budget: budget, simulationVersion: ResultHasher.simulationVersion,
            minPossibleAverageLapMillis: 0, bannedOption: banned
        )
    }

    func testRivalsObeyBudgetAndRegulation() {
        for budget in [92, 100, 108] {
            for banned in [nil, EngineeringOptionID.enginePower, .tiresSoft, .aeroLowDrag] {
                for rival in RivalField.rivals(for: challenge(budget: budget, banned: banned)) {
                    let picks = rival.result.setup.selectedOptions
                    XCTAssertEqual(picks.count, 8, rival.name)
                    let cost = picks.values.reduce(0) { $0 + OptionLibrary.option($1).cost }
                    XCTAssertLessThanOrEqual(cost, budget, "\(rival.name) over budget")
                    if let banned { XCTAssertFalse(picks.values.contains(banned), rival.name) }
                }
            }
        }
    }

    func testRivalsAreDeterministic() {
        XCTAssertEqual(RivalField.rivals(for: challenge()), RivalField.rivals(for: challenge()))
    }

    /// Magnifying the gaps must never change who is ahead: the order at
    /// every sector line and at the flag is the real one.
    func testOrderAtTheFlagIsTheRealOrder() {
        let field = RivalField.rivals(for: challenge())
        let timeline = RaceTimeline(entrants: field)
        XCTAssertGreaterThanOrEqual(timeline.gapScale, 1)

        let byRealTotal = field.indices.sorted { a, b in
            // The timeline is built from sector times, so compare those.
            let ta = field[a].result.lapResults.reduce(0) { $0 + $1.sectorTimesMillis.reduce(0, +) }
            let tb = field[b].result.lapResults.reduce(0) { $0 + $1.sectorTimesMillis.reduce(0, +) }
            return ta != tb ? ta < tb : a < b
        }
        XCTAssertEqual(timeline.order(at: timeline.lastFinishClock + 1), byRealTotal)
    }

    func testEveryCarAlwaysMovesForward() {
        let timeline = RaceTimeline(entrants: RivalField.rivals(for: challenge()))
        for i in timeline.entrants.indices {
            var last = -1.0
            var clock = 0.0
            while clock <= timeline.lastFinishClock {
                let p = timeline.sectorProgress(of: i, at: clock)
                XCTAssertGreaterThanOrEqual(p, last)
                last = p
                clock += timeline.lastFinishClock / 400
            }
            XCTAssertEqual(timeline.sectorProgress(of: i, at: timeline.lastFinishClock + 1),
                           Double(timeline.laps * 3))
        }
    }
}
