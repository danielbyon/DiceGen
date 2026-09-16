//
//  HistoryUITests.swift
//  DiceGenUITests
//

import XCTest

@MainActor
final class HistoryUITests: XCTestCase {
    func testHistoryEnrollmentFocusesPINFieldOnAppear() {
        continueAfterFailure = false
        let app = launch()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'History'"))
            .firstMatch
            .tap()
        XCTAssertTrue(app.buttons["Enable History"].waitForExistence(timeout: 3))
        app.buttons["Enable History"].tap()
        XCTAssertTrue(app.navigationBars["Enable History"].waitForExistence(timeout: 3))

        let pinField = app.secureTextFields["PIN"]
        XCTAssertTrue(pinField.waitForExistence(timeout: 2))
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 2))
    }

    func testHistoryEnrollmentPlacesEnableButtonInSeparateFormSection() {
        continueAfterFailure = false
        let app = launch()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'History'"))
            .firstMatch
            .tap()
        XCTAssertTrue(app.buttons["Enable History"].waitForExistence(timeout: 3))
        app.buttons["Enable History"].tap()
        XCTAssertTrue(app.navigationBars["Enable History"].waitForExistence(timeout: 3))

        let confirmationField = app.secureTextFields["Confirm PIN"]
        let enableButton = app.buttons["Enable History"]
        XCTAssertTrue(confirmationField.waitForExistence(timeout: 2))
        XCTAssertTrue(enableButton.waitForExistence(timeout: 2))

        let sectionGap = enableButton.frame.minY - confirmationField.frame.maxY
        XCTAssertGreaterThan(sectionGap, 25, "Enable History should be separated from the PIN fields")
    }

    func testMigratedHistoryNoticeAppearsFromMainAppFlow() {
        continueAfterFailure = false
        let app = launch(arguments: ["--ui-testing-seeded-legacy-history"])
        let notice = app.alerts["History now requires a PIN"]
        let message = "Existing history was moved to private local storage. Set a PIN in Settings > History to access it and resume saving copied passphrases."

        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        XCTAssertTrue(
            notice.staticTexts
                .matching(NSPredicate(format: "label == %@", message))
                .firstMatch
                .waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.navigationBars["Settings"].exists)
        XCTAssertFalse(app.staticTexts["View Passphrase History"].exists)

        notice.buttons["OK"].tap()
        XCTAssertFalse(notice.waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["View Passphrase History"].exists)

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'History'"))
            .firstMatch
            .tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 3))
        XCTAssertFalse(notice.exists)
    }

    func testHistoryContextMenuCopyActionIsAvailableForSavedEntry() {
        continueAfterFailure = false
        let app = launch()

        enableHistory(in: app)
        returnToGenerator(in: app)
        app.buttons["Copy to Clipboard"].tap()
        openHistory(in: app)

        let entry = app.cells.firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.press(forDuration: 1.0)

        let copyAction = app.buttons["Copy"]
        XCTAssertTrue(copyAction.waitForExistence(timeout: 2))
        copyAction.tap()
        XCTAssertTrue(app.navigationBars["Passphrase History"].exists)
    }

    func testSetupRecordsOnlyCopiesRelocksAndClearsHistory() {
        continueAfterFailure = false
        let app = launch()

        enableHistory(in: app)
        returnToGenerator(in: app)

        app.buttons["Generate Passphrase"].tap()
        openHistory(in: app)
        XCTAssertTrue(app.staticTexts["No History Yet"].waitForExistence(timeout: 3))

        goBackToGenerator(in: app)
        XCTAssertTrue(app.buttons["Copy to Clipboard"].waitForExistence(timeout: 2))
        app.buttons["Copy to Clipboard"].tap()
        goBackToGenerator(in: app)
        openHistory(in: app)
        XCTAssertFalse(app.staticTexts["No History Yet"].waitForExistence(timeout: 3))

        XCUIDevice.shared.press(.home)
        app.activate()
        let pinField = app.secureTextFields["History PIN"]
        XCTAssertTrue(pinField.waitForExistence(timeout: 5))
        pinField.tap()
        pinField.typeText(testPIN)
        app.buttons["Unlock"].tap()
        XCTAssertTrue(app.navigationBars["Passphrase History"].waitForExistence(timeout: 3))

        app.buttons["Clear All"].tap()
        XCTAssertTrue(app.buttons["Clear History"].waitForExistence(timeout: 2))
        app.buttons["Clear History"].tap()
        XCTAssertTrue(app.staticTexts["No History Yet"].waitForExistence(timeout: 3))
    }

    func testDisablingHistoryRemovesGeneratorEntryAndRequiresSetupAgain() {
        continueAfterFailure = false
        let app = launch()

        enableHistory(in: app)
        app.buttons["Disable History"].tap()
        XCTAssertTrue(app.buttons["Delete History and Disable"].waitForExistence(timeout: 2))
        app.buttons["Delete History and Disable"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["View Passphrase History"].exists)

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'History'"))
            .firstMatch
            .tap()
        XCTAssertTrue(app.buttons["Enable History"].waitForExistence(timeout: 3))
    }

    func testInjectedSystemAuthenticationUnlocksWithoutPINEntry() {
        continueAfterFailure = false
        let app = launch(arguments: ["--ui-testing-local-auth-success"])

        enableHistory(in: app)
        let authToggle = app.switches["Use Face ID / Touch ID / Device Passcode"]
        XCTAssertTrue(authToggle.waitForExistence(timeout: 3))
        let toggleControl = authToggle.descendants(matching: .switch).firstMatch
        if toggleControl.exists {
            toggleControl.tap()
        } else {
            authToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        returnToGenerator(in: app)

        app.buttons["Copy to Clipboard"].tap()
        openHistory(in: app)
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(app.navigationBars["Passphrase History"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Clear All"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["History PIN"].exists)
    }

    private let testPIN = String(repeating: "7", count: 4)

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US_POSIX"
        ] + arguments
        app.launch()
        XCTAssertTrue(app.navigationBars["DiceGen"].waitForExistence(timeout: 5))
        return app
    }

    private func enableHistory(in app: XCUIApplication) {
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'History'"))
            .firstMatch
            .tap()
        XCTAssertTrue(app.buttons["Enable History"].waitForExistence(timeout: 3))
        app.buttons["Enable History"].tap()
        XCTAssertTrue(app.navigationBars["Enable History"].waitForExistence(timeout: 3))

        let pinField = app.secureTextFields["PIN"]
        let confirmationField = app.secureTextFields["Confirm PIN"]
        XCTAssertTrue(pinField.waitForExistence(timeout: 2))
        pinField.tap()
        pinField.typeText(testPIN)
        confirmationField.tap()
        confirmationField.typeText(testPIN)
        app.buttons["Enable History"].tap()
        XCTAssertTrue(app.switches["Use Face ID / Touch ID / Device Passcode"].waitForExistence(timeout: 3))
    }

    private func returnToGenerator(in app: XCUIApplication) {
        if app.navigationBars["Passphrase History"].isHittable {
            app.navigationBars["Passphrase History"].buttons.element(boundBy: 0).tap()
        }
        if app.navigationBars["History"].isHittable {
            app.navigationBars["History"].buttons.element(boundBy: 0).tap()
        }
        if app.navigationBars["Settings"].isHittable {
            app.buttons["Done"].tap()
        }
        XCTAssertTrue(app.navigationBars["DiceGen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["DiceGen"].isHittable)
    }

    private func goBackToGenerator(in app: XCUIApplication) {
        returnToGenerator(in: app)
    }

    private func openHistory(in app: XCUIApplication) {
        let historyLink = app.staticTexts["View Passphrase History"]
        XCTAssertTrue(historyLink.waitForExistence(timeout: 3))
        historyLink.tap()
        XCTAssertTrue(app.navigationBars["Passphrase History"].waitForExistence(timeout: 3))
    }
}
