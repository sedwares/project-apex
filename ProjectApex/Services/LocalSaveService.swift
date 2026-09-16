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

    /// The account that submitted this, so the app can tell whether the
    /// row on the leaderboard is still ours.
    ///
    /// ── WHY A RECORD NEEDS TO KNOW WHOSE IT IS ─────────────────
    /// Records are keyed by date alone, and `restoreIfSubmitted` asks
    /// only "is there a record for today". The uid is separate state,
    /// living in the keychain rather than UserDefaults — and the two
    /// can come apart:
    ///
    ///   · the auth user is deleted server-side, so the next launch
    ///     signs in as somebody new while today's record survives;
    ///   · an iPhone backup is restored onto another device, which
    ///     carries UserDefaults across but not necessarily the keychain.
    ///
    /// Either way the app restored the old result under a NEW identity,
    /// showed "View debrief", and `refreshStanding` then re-submitted
    /// that stored record via `submitAndStand` under the new uid —
    /// putting one person on the same day's board twice, with the same
    /// lap time and two different callsigns. It is how three identical
    /// times reached the live board during testing.
    ///
    /// Optional, so every record written before build 24 decodes and is
    /// treated as legacy: unknown owner, no guard. New records carry it.
    let submittedByUID: String?

    init(
        dateKey: String,
        selections: [EngineeringCategoryID: EngineeringOptionID],
        result: SimulationResult,
        submittedAt: Date,
        simulationVersion: String?,
        submittedByUID: String? = nil
    ) {
        self.dateKey = dateKey
        self.selections = selections
        self.result = result
        self.submittedAt = submittedAt
        self.simulationVersion = simulationVersion
        self.submittedByUID = submittedByUID
    }
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
