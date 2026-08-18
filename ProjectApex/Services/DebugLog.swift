//
//  DebugLog.swift
//  ProjectApex
//
//  R14: users see friendly messages; developers see the truth.
//  DEBUG-only prints; Crashlytics lands with the launch checklist.
//

import Foundation

enum DebugLog {
    static func log(_ context: String, _ error: Error? = nil) {
        #if DEBUG
        if let error {
            print("🔎 APEX [\(context)] \(error)")
        } else {
            print("🔎 APEX [\(context)]")
        }
        #endif
    }
}
