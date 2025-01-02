//
//  ultravox_client_sdk_ios_exampleUITestsLaunchTests.swift
//  ultravox-client-sdk-ios-exampleUITests
//
//  Created by Ben Lower on 11/15/24.
//

import XCTest

final class ultravox_client_sdk_ios_exampleUITestsLaunchTests: XCTestCase {
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

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
