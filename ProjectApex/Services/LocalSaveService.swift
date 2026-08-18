//
//  LocalSaveService.swift
//  ProjectApex
//
//  Persistence for the Daily loop, UserDefaults-backed (the portfolio
//  pattern for lighter state). One record per dateKey: the locked
//  setup, the full result, and the submission timestamp. Streak is
//  tracked by day number (UTC), consecutive-day rule.
//
//  The protocol exists so tests inject an in-memory store — the
//  ViewModel never touches UserDefaults directly.
//

import Foundation
import ProjectApexCore

struct DailyRecord: Codable, Equatable {
    let dateKey: String
    let selections: [EngineeringCategoryID: EngineeringOptionID]
    let result: SimulationResult
    let submittedAt: Date
    /// R6: optional so pre-Phase-5 records decode as legacy-valid.
    /// nil = written before versioning; treated as current.
    let simulationVersion: String?
}

@MainActor
protocol DailySaveStore: AnyObject {
    func loadRecord(forDateKey dateKey: String) -> DailyRecord?
    func saveRecord(_ record: DailyRecord)
    /// Registers a completed day and updates the streak.
    func registerCompletion(dayNumber: Int)
    /// Streak as of a given day: alive if the last completion was
    /// today or yesterday; otherwise 0.
    func currentStreak(asOfDayNumber dayNumber: Int) -> Int
}

@MainActor
final class UserDefaultsSaveStore: DailySaveStore {

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Keys {
        static func record(_ dateKey: String) -> String { "apex.daily.\(dateKey)" }
        static let lastCompletedDay = "apex.streak.lastDay"
        static let streakCount = "apex.streak.count"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadRecord(forDateKey dateKey: String) -> DailyRecord? {
        guard let data = defaults.data(forKey: Keys.record(dateKey)) else { return nil }
        return try? decoder.decode(DailyRecord.self, from: data)
    }

    func saveRecord(_ record: DailyRecord) {
        guard let data = try? encoder.encode(record) else { return }
        defaults.set(data, forKey: Keys.record(record.dateKey))
    }

    func registerCompletion(dayNumber: Int) {
        let last = defaults.integer(forKey: Keys.lastCompletedDay)
        let streak = defaults.integer(forKey: Keys.streakCount)
        if dayNumber == last { return }                       // same day, no-op
        let newStreak = (dayNumber == last + 1) ? streak + 1 : 1
        defaults.set(dayNumber, forKey: Keys.lastCompletedDay)
        defaults.set(newStreak, forKey: Keys.streakCount)
    }

    func currentStreak(asOfDayNumber dayNumber: Int) -> Int {
        let last = defaults.integer(forKey: Keys.lastCompletedDay)
        let streak = defaults.integer(forKey: Keys.streakCount)
        guard last == dayNumber || last == dayNumber - 1 else { return 0 }
        return streak
    }
}
