//
//  UTCDateKey.swift
//  ProjectApexCore
//
//  Single source of truth for "what UTC day is it" — this exact
//  calendar snippet was duplicated across DailyCoordinator,
//  DailyViewModel.isRevealAllowed, TestSessionViewModel, and the
//  publisher CLI. One helper, one place to get it right.
//

import Foundation

public nonisolated enum UTCDateKey {
    /// Formats a Date as "yyyy-MM-dd" in the UTC calendar day.
    public static func make(from date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
