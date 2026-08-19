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
                // Locked dark. The Livery palette is built on a
                // near-black ground; a light-mode variant would be a
                // second design, not a setting, and the app has no
                // screen where light mode is the better read.
                //
                // This also makes the theme rollout safe to do screen by
                // screen: any view still using .primary/.secondary gets
                // sensible light-on-dark from the system rather than
                // black text on an ink background.
                .preferredColorScheme(.dark)
                .tint(Theme.Color.signal)
        }
    }
}
