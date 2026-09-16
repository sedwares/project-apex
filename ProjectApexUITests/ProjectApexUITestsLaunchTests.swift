//
//  ProjectApexUITestsLaunchTests.swift
//  ProjectApexUITests
//
//  Kept as the screenshot harness, not as a test of anything: it
//  launches under each target application UI configuration and attaches
//  what it sees. The attachment is the point — a launch that renders
//  the wrong thing is visible in the report even when nothing asserts.
//
//  The real launch assertion lives in ProjectApexUITests.
//

import XCTest

final class ProjectApexUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Give the first screen a moment to draw, otherwise the
        // attachment is a black window and tells you nothing.
        _ = app.staticTexts.firstMatch.waitForExistence(timeout: 10)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
