import AppKit
import XCTest

extension MenuBarAcceptanceTests {
    @MainActor
    func testMenuBarResultsStandingsFallbackAndPenaltyCorrection() async throws {
        let app = XCUIApplication(bundleIdentifier: "com.pitpulse.F1Companion")
        app.launchArguments = [
            "-serverAddress", "http://127.0.0.1:38701",
            "-selectedSeason", "2026"
        ]
        app.launch()
        defer { app.terminate() }

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), app.debugDescription)

        let popup = app.dialogs.firstMatch
        if !popup.exists {
            statusItem.click()
        }
        XCTAssertTrue(popup.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(staticText(containing: "PitPulse", in: popup).waitForExistence(timeout: 5), popup.debugDescription)

        popup.radioButtons["成绩"].click()
        XCTAssertTrue(staticText(containing: "Charles", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        XCTAssertTrue(staticText(containing: "DSQ", in: popup).exists, popup.debugDescription)
        XCTAssertTrue(staticText(containing: "— 圈", in: popup).exists, popup.debugDescription)
        attachScreenshot("T08 normal, missing-image, unclassified and no-lap results", from: popup)

        try await postControl("/revision/2")
        try await postControl("/sync")
        reopenResults(in: popup)
        XCTAssertTrue(staticText(containing: "26 分", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        attachScreenshot("T11 fixture revision 2 visible in MenuBar results", from: popup)

        try await postControl("/penalty-correction/true")
        try await postControl("/sync")
        reopenResults(in: popup)
        XCTAssertTrue(staticText(containing: "1:25.123", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        XCTAssertTrue(staticText(containing: "18 分", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        attachScreenshot("T08 penalty-corrected result revision 3", from: popup)

        popup.radioButtons["积分"].click()
        XCTAssertTrue(staticText(containing: "Charles", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        attachScreenshot("T08 current-season driver standings", from: popup)

        popup.buttons["上一年"].click()
        XCTAssertTrue(staticText(containing: "2025", in: popup).waitForExistence(timeout: 5), popup.debugDescription)
        XCTAssertTrue(staticText(containing: "Charles", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        attachScreenshot("T08 previous-season asset fallback", from: popup)

        popup.buttons["下一年"].click()
        XCTAssertTrue(staticText(containing: "2026", in: popup).waitForExistence(timeout: 5), popup.debugDescription)
    }

    @MainActor
    func testSettingsWindowPromotesAppAndRestoresAccessoryPolicy() throws {
        try checkSettingsWindow(appearance: "Dark")
    }

    @MainActor
    func testSettingsWindowLightAppearance() throws {
        try checkSettingsWindow(appearance: "Light")
    }
}
