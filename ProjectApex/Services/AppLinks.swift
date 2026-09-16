//
//  AppLinks.swift
//  ProjectApex
//
//  Every URL the app opens, in one place.
//
//  ── WHY A FILE FOR TWO URLS ────────────────────────────────────────
//  The privacy policy URL appears in three places that must agree: this
//  app's Settings screen, the Privacy Policy URL field in App Store
//  Connect, and the Support URL field beside it. A mismatch between the
//  first and the second is a rejection; a mismatch nobody notices is
//  worse, because the store listing points somewhere real and the app
//  points somewhere dead.
//
//  The page is served by GitHub Pages from `docs/` on this repo, so the
//  source of truth for its CONTENT is docs/index.html in this same
//  repository — edit there, push, and this URL serves the new version.
//

import Foundation

enum AppLinks {

    /// Privacy policy, also used as the App Store support URL.
    ///
    /// Force-unwrapped deliberately: a literal that fails to parse is a
    /// programming error that must fail loudly in development, not a
    /// runtime condition to handle. It is covered by a test.
    static let privacyPolicy = URL(string: "https://sedwares.github.io/project-apex/")!
}
