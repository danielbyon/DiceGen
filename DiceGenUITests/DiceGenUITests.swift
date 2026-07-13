//
//  DiceGenUITests.swift
//  DiceGenUITests
//

import XCTest

@MainActor
final class DiceGenUITests: XCTestCase {
    func testGeneratorAndSettingsSmokeFlow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US_POSIX"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["DiceGen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Generate Passphrase"].exists)
        XCTAssertTrue(app.buttons["Copy to Clipboard"].exists)
        XCTAssertTrue(app.staticTexts["5 words"].exists)
        XCTAssertFalse(app.staticTexts["View Passphrase History"].exists)

        let stepper = app.steppers.firstMatch
        XCTAssertTrue(stepper.exists)
        stepper.buttons["Increment"].tap()
        XCTAssertTrue(app.staticTexts["6 words"].waitForExistence(timeout: 2))

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.switches["Save copied passphrases/passwords"].exists)
        XCTAssertFalse(app.buttons["Clear passphrase/password history"].exists)

        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["DiceGen"].waitForExistence(timeout: 2))
    }
}
