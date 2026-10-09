import XCTest

final class MenuBarAcceptanceTests: XCTestCase {
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
        XCTAssertTrue(staticText(containing: "在线", in: popup).waitForExistence(timeout: 10), popup.debugDescription)

        popup.radioButtons["成绩"].click()
        XCTAssertTrue(staticText(containing: "Charles", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        XCTAssertTrue(staticText(containing: "DSQ", in: popup).exists, popup.debugDescription)
        XCTAssertTrue(staticText(containing: "— 圈", in: popup).exists, popup.debugDescription)
        attachScreenshot("T08 normal, missing-image, unclassified and no-lap results", from: popup)

        try await postControl("/revision/2")
        try await postControl("/sync")
        reopenResults(in: popup)
        XCTAssertTrue(staticText(containing: "26 分", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        XCTAssertTrue(staticText(containing: "revision 2", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        attachScreenshot("T11 fixture revision 2 visible in MenuBar results", from: popup)

        try await postControl("/penalty-correction/true")
        try await postControl("/sync")
        reopenResults(in: popup)
        XCTAssertTrue(staticText(containing: "1:25.123", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        XCTAssertTrue(staticText(containing: "18 分", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        XCTAssertTrue(staticText(containing: "revision 3", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        attachScreenshot("T08 penalty-corrected result revision 3", from: popup)

        popup.radioButtons["积分"].click()
        XCTAssertTrue(staticText(containing: "Charles", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        attachScreenshot("T08 current-season driver standings", from: popup)

        let seasonPicker = popup.popUpButtons
            .matching(NSPredicate(format: "label CONTAINS %@", "选择积分赛季"))
            .firstMatch
        XCTAssertTrue(seasonPicker.exists, popup.debugDescription)
        seasonPicker.click()
        let previousSeason = app.menuItems["2025"]
        XCTAssertTrue(previousSeason.waitForExistence(timeout: 5), app.debugDescription)
        previousSeason.click()
        XCTAssertEqual(seasonPicker.value as? String, "2025", popup.debugDescription)
        XCTAssertTrue(staticText(containing: "Charles", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        attachScreenshot("T08 previous-season asset fallback", from: popup)

        seasonPicker.click()
        let currentSeason = app.menuItems["2026"]
        XCTAssertTrue(currentSeason.waitForExistence(timeout: 5), app.debugDescription)
        currentSeason.click()
        XCTAssertEqual(seasonPicker.value as? String, "2026", popup.debugDescription)
    }

    @MainActor
    private func staticText(containing value: String, in popup: XCUIElement) -> XCUIElement {
        popup.staticTexts.matching(NSPredicate(format: "value CONTAINS[c] %@", value)).firstMatch
    }

    @MainActor
    private func attachScreenshot(_ name: String, from popup: XCUIElement) {
        let screenshot = XCTAttachment(screenshot: popup.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func postControl(_ path: String) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:38702\(path)")!)
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, String(decoding: data, as: UTF8.self))
    }

    @MainActor
    private func reopenResults(in popup: XCUIElement) {
        popup.radioButtons["下一站"].click()
        popup.radioButtons["成绩"].click()
    }
}
