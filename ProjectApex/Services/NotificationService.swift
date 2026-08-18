//
//  NotificationService.swift
//  ProjectApex
//
//  The reminder that makes a daily game daily.
//
//  Two decisions worth stating, because both are easy to get wrong and
//  expensive to change once shipped:
//
//  1. WE ASK LATE. The permission prompt fires on the third completed
//     day, never at launch. A player who has finished three assignments
//     has demonstrated the habit the notification protects; a player on
//     their first launch has no idea what they'd be agreeing to. iOS
//     gives one prompt, ever — spending it on a stranger is how you end
//     up with a 30% grant rate instead of 70%.
//
//  2. WE DON'T NAG. Notifications are scheduled as a rolling week of
//     one-shots rather than a repeating trigger, and rescheduled after
//     every submission. Play today and today's reminder disappears —
//     a repeating trigger cannot do that, and "today's assignment is
//     ready" arriving after you've already raced reads as a bug.
//
//  Local, not push: the challenge changes on a fixed UTC schedule that
//  the device already knows. Nothing here needs a server.
//

import Foundation
import UserNotifications
import ProjectApexCore

@MainActor
final class NotificationService {

    static let shared = NotificationService()

    /// Local hour to remind at. The challenge is available all day, so
    /// this is a civil-time choice, not a technical one — waking someone
    /// at the UTC rollover would mean 1am for a third of the world.
    static let reminderHour = 9

    /// How many days ahead to keep scheduled. iOS caps pending local
    /// notifications at 64; seven is plenty and leaves room to spare.
    static let horizonDays = 7

    /// Completed days before we spend the one permission prompt we get.
    static let promptAfterCompletedDays = 3

    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults

    private enum Keys {
        static let didRequest = "apex.notifications.didRequestAuthorization"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Permission

    var hasAskedBefore: Bool { defaults.bool(forKey: Keys.didRequest) }

    /// Asks only once the habit is real. Returns whether we're allowed
    /// to schedule anything.
    @discardableResult
    func requestAuthorizationIfEarned(completedDays: Int) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            guard completedDays >= Self.promptAfterCompletedDays else { return false }
            defaults.set(true, forKey: Keys.didRequest)
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                DebugLog.log("notification authorization failed", error)
                return false
            }
        @unknown default:
            return false
        }
    }

    // MARK: - Scheduling

    /// Rebuilds the whole schedule. Call after every submission and on
    /// launch — it is cheap and idempotent, and rebuilding is the only
    /// way to honour "don't remind me about a day I've already played".
    func refreshSchedule(hasPlayedToday: Bool, now: Date = Date()) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        center.removeAllPendingNotificationRequests()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        // Skip today entirely when it's already raced, and skip it also
        // when the hour has passed — a reminder scheduled into the past
        // is silently dropped by iOS, which would leave a hole.
        let firstOffset = hasPlayedToday ? 1 : 0

        for offset in firstOffset..<(firstOffset + Self.horizonDays) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = Self.reminderHour
            components.minute = 0
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Today's assignment is ready"
            content.body = Self.body(forOffset: offset)
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: fireDate
                ),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "apex.daily.\(UTCDateKey.make(from: fireDate))",
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                DebugLog.log("failed to schedule reminder for \(fireDate)", error)
            }
        }
    }

    /// Cancels everything — used by account deletion, where leaving a
    /// week of reminders for a deleted account would be indefensible.
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    /// Deterministic, varied copy. Rotating by day index keeps a week of
    /// reminders from reading like the same message seven times, without
    /// any randomness to make behaviour unreproducible.
    static func body(forOffset offset: Int) -> String {
        let lines = [
            "A new circuit, new weather, one budget.",
            "Every engineer in the world gets the same problem today.",
            "Eight decisions. One submission.",
            "Yesterday's optimal setup is unlocked too.",
            "Three laps, and the third one tells the truth.",
            "Same circuit for everyone. Different answers.",
            "The stewards have published today's regulations."
        ]
        return lines[((offset % lines.count) + lines.count) % lines.count]
    }
}
