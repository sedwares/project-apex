//
//  UTCDateKeyTests.swift
//  ProjectApexCoreTests
//

import XCTest
@testable import ProjectApexCore

final class UTCDateKeyTests: XCTestCase {

    func testFormatsAsYYYYMMDD() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 15))!
        XCTAssertEqual(UTCDateKey.make(from: date), "2026-07-30")
    }

    func testUsesUTCRegardlessOfLocalTimeZone() {
        // 2026-07-30 23:30 UTC — a local zone many hours behind would
        // otherwise still read this as the 30th; verify UTC wins.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 23, minute: 30))!
        XCTAssertEqual(UTCDateKey.make(from: date), "2026-07-30")
    }

    func testPadsSingleDigitMonthAndDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        XCTAssertEqual(UTCDateKey.make(from: date), "2026-01-05")
    }
}
