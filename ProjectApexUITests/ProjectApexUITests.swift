//
//  ProjectApexUITests.swift
//  ProjectApexUITests
//
//  ── WHAT THIS REPLACED, AND WHY ────────────────────────────────────
//  Xcode's template, verbatim: a `testExample` that launched the app
//  and asserted nothing, and a `testLaunchPerformance` wrapping
//  XCTApplicationLaunchMetric.
//
//  The performance test failed on a real device with "Received
//  unexpected number of metrics: 0 in iteration with index 1". That is
//  the well-known shape of that template — the metric runs five
//  iterations and intermittently collects nothing — and it was failing
//  while asserting nothing about this app, which is the worst trade a
//  test can make: it costs attention and buys no information. A launch
//  time we never had a budget for, measured flakily, is not a signal.
//
//  What this target is actually good for is the one thing no unit test
//  can check: that the app STARTS. A crash in App.init, a Firebase
//  misconfiguration, a fatalError in a view body — none of those show
//  up in ProjectApexCoreTests or ProjectApexTests, and all of them are
//  a dead app on a reviewer's device.
//

import XCTest

final class ProjectApexUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The app launches and renders its own first screen.
    ///
    /// Deliberately tolerant about WHICH screen. A fresh install opens
    /// onboarding; an install that has seen it opens the brief, which
    /// itself has three legitimate states depending on the network —
    /// loading, ready, or "Paddock unreachable". Asserting one of those
    /// specifically would make this test fail on a slow connection and
    /// teach everyone to ignore it.
    ///
    /// What it does assert is the thing that matters: within ten
    /// seconds, something this app drew is on screen. A launch crash
    /// shows up as every one of these being absent.
    @MainActor
    func testAppLaunchesAndRendersItsFirstScreen() throws {
        let app = XCUIApplication()
        app.launch()

        let onboarding = app.staticTexts["Enter the paddock"]
        let onboardingNext = app.staticTexts["Next"]
        let homeTitle = app.staticTexts["Project Apex"]
        let loading = app.staticTexts["Preparing today's assignment"]
        let unreachable = app.staticTexts["Paddock unreachable"]

        let appeared = NSPredicate(format: "exists == true")
        let candidates = [onboarding, onboardingNext, homeTitle, loading, unreachable]
        let expectations = candidates.map {
            expectation(for: appeared, evaluatedWith: $0, handler: nil)
        }

        // Any one is enough — XCTWaiter returns as soon as the first
        // is met when the others are allowed to go unfulfilled.
        let result = XCTWaiter().wait(for: expectations, timeout: 10, enforceOrder: false)
        let anyVisible = candidates.contains { $0.exists }

        XCTAssertTrue(
            anyVisible,
            "Nothing the app draws appeared within 10s (waiter: \(result.rawValue)). "
                + "That is a launch failure, not a slow screen."
        )
        XCTAssertEqual(app.state, .runningForeground, "the app is not in the foreground")
    }

    /// The brief is reachable and offers its one call to action.
    ///
    /// ── TWO THINGS THIS GOT WRONG FIRST TIME ───────────────────
    /// It looked for `app.staticTexts["Begin assignment"]`. A
    /// NavigationLink's Text label surfaces in the accessibility tree
    /// as a BUTTON, so that query could never match — the test failed
    /// against a perfectly healthy screen.
    ///
    /// And it assumed one label. There are three legitimate ones:
    /// "Begin assignment" before you play, "View debrief" after, and
    /// "Load today's assignment" when the day closed under an open
    /// session. Pinning copy would have failed again the first time
    /// anyone edited a string.
    ///
    /// So it matches an identifier instead, which survives both.
    @MainActor
    func testBriefOffersItsCallToAction() throws {
        let app = XCUIApplication()
        app.launch()

        // Step past onboarding if this is a fresh install. Bounded:
        // a loop that waits on a screen that never comes is a hang,
        // not a test.
        let advance = app.buttons["apex.onboarding.advance"]
        var guardRail = 0
        while advance.waitForExistence(timeout: 2), guardRail < 6 {
            advance.tap()
            guardRail += 1
        }

        if app.staticTexts["Paddock unreachable"].waitForExistence(timeout: 8) {
            throw XCTSkip("no network or no published challenge — nothing to assert")
        }

        let cta = app.buttons["apex.brief.primaryAction"]
        XCTAssertTrue(
            cta.waitForExistence(timeout: 10),
            "the brief rendered with no call to action at all"
        )
        XCTAssertTrue(cta.isHittable, "the call to action is present but cannot be tapped")
    }
}
