import XCTest

final class NavigationTests: XCTestCase {
    @MainActor
    func testRecordedLiveLaunchWithoutURLConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["-serverAddress", "http://127.0.0.1:38702"]
        app.launchEnvironment["PITPULSE_LIVE_SERVER_URL"] = "http://127.0.0.1:38702"
        app.launchEnvironment["PITPULSE_OPEN_LIVE"] = "1"
        app.launch()
        defer { app.terminate() }
        let close = app.buttons["Close Live"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), app.debugDescription)
        close.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testTabsAndRecordedLiveReturn() {
        let app = XCUIApplication()
        app.launchArguments = ["-serverAddress", "http://127.0.0.1:38702"]
        app.launchEnvironment["PITPULSE_LIVE_SERVER_URL"] = "http://127.0.0.1:38702"
        app.launch()
        defer { app.terminate() }
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 20))
        for label in ["Results", "Head to Head", "Drivers", "Constructors", "Home"] {
            let button = tabs.buttons[label]
            XCTAssertTrue(button.exists, app.debugDescription)
            button.tap()
            XCTAssertTrue(tabs.exists)
        }
        let settings = app.buttons["Open PitPulse settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let configure = app.buttons["Configure server"]
        XCTAssertTrue(configure.waitForExistence(timeout: 10))
        configure.tap()
        let closeConfiguration = app.buttons["Close server configuration"]
        XCTAssertTrue(closeConfiguration.waitForExistence(timeout: 10))
        closeConfiguration.tap()
        app.buttons["Close settings"].tap()
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        let live = app.descendants(matching: .any).matching(identifier: "live.open").firstMatch
        XCTAssertTrue(live.waitForExistence(timeout: 30), app.debugDescription)
        live.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let close = app.buttons["Close Live"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        close.tap()
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
    }
    @MainActor
    func testConsistencyIsNestedUnderHeadToHead() {
        let app = XCUIApplication()
        app.launchArguments = ["-serverAddress", "http://127.0.0.1:38702"]
        app.launch()
        defer { app.terminate() }

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 20))
        let headToHead = tabs.buttons["Head to Head"]
        headToHead.tap()
        XCTAssertFalse(tabs.buttons["Consistency"].exists, app.debugDescription)
        let consistency = app.buttons["section.Consistency"]
        XCTAssertTrue(consistency.waitForExistence(timeout: 5))
        consistency.tap()
        XCTAssertTrue(app.switches["consistency.excludeDNF"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(headToHead.isSelected, app.debugDescription)
    }

    @MainActor
    func testFavoriteDriverUsesSearchableDedicatedPage() {
        let app = XCUIApplication()
        app.launchArguments = ["-serverAddress", "http://127.0.0.1:38702"]
        app.launch()
        defer { app.terminate() }

        app.buttons["Open PitPulse settings"].tap()
        let favorite = app.buttons["settings.favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 10), app.debugDescription)
        favorite.tap()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
        search.tap()
        search.typeText("Norris")

        let driver = app.buttons["driver.choice.norris"]
        XCTAssertTrue(driver.waitForExistence(timeout: 10), app.debugDescription)
        driver.tap()
        XCTAssertTrue(app.buttons["settings.favorite"].label.contains("Norris"), app.debugDescription)
    }
}
