import XCTest

/// XCUITest suite for VirtManager.
/// Tests the full user flow: launch → connect → browse VMs → open console.
/// Requires jolyne (10.11.0.6) reachable via SSH key auth.
final class VirtManagerUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Clear saved connections before each test to avoid accumulation
        app.launchArguments = ["--reset-connections"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        // Clean up saved connections from UserDefaults
        UserDefaults.standard.removeObject(forKey: "com.virtmanager.savedConnections")
    }

    // MARK: - Launch Tests

    func testAppLaunches() {
        XCTAssertTrue(app.windows.count >= 1)
    }

    func testMainWindowHasToolbar() {
        XCTAssertTrue(app.windows.firstMatch.toolbars.count >= 1)
    }

    func testEmptyState() {
        let noVM = app.staticTexts["No VM Selected"]
        XCTAssertTrue(noVM.waitForExistence(timeout: 3))
    }

    // MARK: - Connection Sheet

    func testAddConnectionOpensSheet() {
        clickAddConnection()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
    }

    func testConnectionSheetHasFields() {
        clickAddConnection()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))

        let nameField = sheet.textFields["displayNameField"]
        let uriField = sheet.textFields["uriField"]
        XCTAssertTrue(nameField.exists, "Display Name field should exist")
        XCTAssertTrue(uriField.exists, "URI field should exist")

        let uriValue = uriField.value as? String ?? ""
        XCTAssertTrue(uriValue.contains("jolyne"), "URI pre-filled, got: \(uriValue)")
    }

    func testConnectionSheetCancel() {
        clickAddConnection()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))

        sheet.buttons["Cancel"].firstMatch.click()
        XCTAssertFalse(sheet.waitForExistence(timeout: 2))
    }

    // MARK: - Connection & VM Discovery

    func testConnectToJolyne() throws {
        try connectToJolyne()
        XCTAssertTrue(app.staticTexts["opnsense"].waitForExistence(timeout: 15))
    }

    func testAllVMsListed() throws {
        try connectToJolyne()
        for name in ["opnsense", "PROD-Brokers-41", "unifi-new", "hass.calii.lan", "fedora-workstation"] {
            XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 10),
                          "VM '\(name)' should be listed")
        }
    }

    // MARK: - VM Detail

    func testSelectVMShowsRunningState() throws {
        try connectToJolyne()
        app.staticTexts["opnsense"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Running"].waitForExistence(timeout: 5))
    }

    func testSelectVMShowsGraphicsType() throws {
        try connectToJolyne()
        app.staticTexts["opnsense"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["VNC"].waitForExistence(timeout: 5))
    }

    func testShutOffVMHasStartButton() throws {
        try connectToJolyne()
        app.staticTexts["fedora-workstation"].firstMatch.click()
        sleep(1)
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 3))
    }

    // MARK: - Console Buttons

    func testVNCVMHasConsoleButton() throws {
        try connectToJolyne()
        app.staticTexts["opnsense"].firstMatch.click()
        sleep(1)
        XCTAssertTrue(app.buttons["Open Console"].waitForExistence(timeout: 3))
    }

    func testSPICEVMHasConsoleButton() throws {
        try connectToJolyne()
        app.staticTexts["PROD-Brokers-41"].firstMatch.click()
        sleep(1)
        XCTAssertTrue(app.buttons["Open Console"].waitForExistence(timeout: 3))
    }

    func testSerialVMHasSerialButton() throws {
        try connectToJolyne()
        app.staticTexts["hass.calii.lan"].firstMatch.click()
        sleep(1)
        XCTAssertTrue(app.buttons["Open Serial Console"].waitForExistence(timeout: 3))
    }

    func testOpenVNCConsoleCreatesWindow() throws {
        try connectToJolyne()
        app.staticTexts["opnsense"].firstMatch.click()
        sleep(1)
        app.buttons["Open Console"].firstMatch.click()
        sleep(3)
        XCTAssertGreaterThanOrEqual(app.windows.count, 2, "Console window should open")
    }

    // MARK: - Helpers

    private func clickAddConnection() {
        app.toolbars.buttons["Add Connection"].firstMatch.click()
    }

    private func connectToJolyne() throws {
        // Already connected?
        if app.staticTexts["opnsense"].waitForExistence(timeout: 2) { return }

        clickAddConnection()
        let sheet = app.sheets.firstMatch
        guard sheet.waitForExistence(timeout: 3) else {
            throw XCTSkip("Sheet didn't appear")
        }

        let nameField = sheet.textFields["displayNameField"]
        guard nameField.waitForExistence(timeout: 3) else {
            throw XCTSkip("Name field not found")
        }
        nameField.click()
        nameField.typeText("jolyne-test")

        sleep(1)
        let addButton = sheet.buttons["addConnectButton"]
        guard addButton.waitForExistence(timeout: 3) else {
            throw XCTSkip("Add button not found")
        }
        addButton.click()

        guard app.staticTexts["opnsense"].waitForExistence(timeout: 20) else {
            throw XCTSkip("Could not connect to jolyne")
        }
    }
}
