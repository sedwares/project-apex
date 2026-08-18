//
//  Analytics.swift
//  ProjectApex
//
//  Four events. Deliberately four.
//
//  Launch week produces exactly one useful question — "where do people
//  fall out?" — and four events answer it end to end:
//
//      onboarding_completed  → did they get past the pitch?
//      first_submission      → did they finish an assignment?
//      return_day_2          → did the daily loop take?
//      share_tapped          → is the growth engine firing?
//
//  Every additional event costs a decision at read time and buys nothing
//  until there's traffic to slice. Add the fifth when a real question
//  needs it, not in anticipation of one.
//
//  Wrapped rather than called directly so the analytics vendor is one
//  file, tests don't emit events, and DEBUG builds print instead of
//  reporting.
//

import Foundation
import FirebaseAnalytics
import ProjectApexCore

@MainActor
enum Analytics {

    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let firstOpenDay = "apex.analytics.firstOpenDayNumber"
        static let loggedFirstSubmission = "apex.analytics.loggedFirstSubmission"
        static let loggedReturnDay2 = "apex.analytics.loggedReturnDay2"
    }

    // MARK: - Events

    static func onboardingCompleted() {
        log("onboarding_completed")
    }

    /// Fires on every submission; the FIRST one also fires its own event,
    /// because "installed but never finished a day" is the drop-off that
    /// matters most and it's painful to reconstruct after the fact.
    static func submitted(dayNumber: Int?, streak: Int, usedRegulation: Bool) {
        log("daily_submission", [
            "day_number": dayNumber ?? -1,
            "streak": streak,
            "regulated_day": usedRegulation
        ])
        if !defaults.bool(forKey: Keys.loggedFirstSubmission) {
            defaults.set(true, forKey: Keys.loggedFirstSubmission)
            log("first_submission", ["day_number": dayNumber ?? -1])
        }
    }

    static func shareTapped(dayNumber: Int?) {
        log("share_tapped", ["day_number": dayNumber ?? -1])
    }

    /// Call on every launch. Records the first day seen, then fires once
    /// when the player comes back on a LATER day — the single number that
    /// says whether a daily game has a loop or just a launch.
    static func trackOpen(todayDayNumber: Int?) {
        guard let today = todayDayNumber else { return }

        let firstDay = defaults.integer(forKey: Keys.firstOpenDay)
        if firstDay == 0 {
            defaults.set(today, forKey: Keys.firstOpenDay)
            return
        }
        guard today > firstDay, !defaults.bool(forKey: Keys.loggedReturnDay2) else { return }
        defaults.set(true, forKey: Keys.loggedReturnDay2)
        log("return_day_2", ["days_since_first_open": today - firstDay])
    }

    /// Account deletion must not leave the analytics identity behind.
    static func resetForDeletedAccount() {
        for key in [Keys.firstOpenDay, Keys.loggedFirstSubmission, Keys.loggedReturnDay2] {
            defaults.removeObject(forKey: key)
        }
        FirebaseAnalytics.Analytics.resetAnalyticsData()
    }

    // MARK: - Transport

    private static func log(_ name: String, _ parameters: [String: Any] = [:]) {
        #if DEBUG
        // Printing instead of reporting keeps development traffic out of
        // the numbers you'll be reading in launch week.
        DebugLog.log("analytics: \(name) \(parameters)")
        #else
        FirebaseAnalytics.Analytics.logEvent(name, parameters: parameters)
        #endif
    }
}
