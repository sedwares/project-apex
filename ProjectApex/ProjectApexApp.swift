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

        // Settle the install state HERE, before any view exists.
        //
        // DailyHomeView attaches several `.task` blocks and one of them
        // writes an apex.* preference synchronously before its first
        // await. Resolving inside ensureSignedIn — which is only
        // reached through an await — meant a genuine reinstall could
        // lose that race, be classified as an upgrade, and keep the
        // identity it was supposed to replace. Nothing can get in front
        // of App.init.
        //
        // The return value is deliberately ignored: a failure here just
        // leaves the state unresolved, and ensureSignedIn re-runs it and
        // throws, which surfaces as a retryable state on the brief
        // rather than a crash at launch.
        FirebaseBootstrap.resolveInstallState()
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
