//
//  ProjectApexApp.swift
//  ProjectApex
//

import SwiftUI
import FirebaseCore

@main
struct ProjectApexApp: App {
    init() {
        FirebaseApp.configure()
        CrashReporting.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
