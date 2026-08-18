//
//  CrashReporting.swift
//  ProjectApex
//
//  Thin wrapper over FirebaseCrashlytics so the rest of the app never
//  imports Crashlytics directly (same DI discipline as every other
//  service). DEBUG builds print to console instead of uploading —
//  no dev noise in the crash dashboard.
//

import Foundation
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

enum CrashReporting {

    /// Call once at launch, after FirebaseApp.configure().
    static func configure() {
        #if canImport(FirebaseCrashlytics) && !DEBUG
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif
    }

    /// Non-fatal error with context — the DEBUG half of R14 from the
    /// review batch; the production half (this file) was deferred to
    /// the launch checklist and lands here.
    static func log(_ context: String, error: Error? = nil) {
        DebugLog.log(context, error)
        #if canImport(FirebaseCrashlytics) && !DEBUG
        Crashlytics.crashlytics().log(context)
        if let error {
            Crashlytics.crashlytics().record(error: error)
        }
        #endif
    }

    /// Non-fatal breadcrumb without an error (e.g. "reached debrief").
    static func breadcrumb(_ message: String) {
        #if canImport(FirebaseCrashlytics) && !DEBUG
        Crashlytics.crashlytics().log(message)
        #endif
    }

    /// Ties crash reports to an anonymous engineer without any PII —
    /// the same uid already used for the leaderboard.
    static func setUserID(_ uid: String) {
        #if canImport(FirebaseCrashlytics) && !DEBUG
        Crashlytics.crashlytics().setUserID(uid)
        #endif
    }
}
