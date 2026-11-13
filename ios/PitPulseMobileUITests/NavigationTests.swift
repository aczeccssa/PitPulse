import XCTest

final class NavigationTests: XCTestCase {
    @MainActor
    func testTabsAndRecordedLiveReturn() {
        let app = XCUIApplication()
        app.launchArguments = ["-serverAddress", "http://127.0.0.1:38702"]
        app.launchEnvironment["PITPULSE_LIVE_SERVER_URL"] = "http://127.0.0.1:38702"
        app.launch()
        defer { app.terminate() }
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 20))
        for label in ["赛历", "车手积分", "车队积分", "下一场总览"] {
            let button = tabs.buttons[label]
            XCTAssertTrue(button.exists, app.debugDescription)
            button.tap()
            XCTAssertTrue(tabs.exists)
        }
        let settings = app.buttons["打开 PitPulse 设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let configure = app.buttons["配置服务器"]
        XCTAssertTrue(configure.waitForExistence(timeout: 10))
        configure.tap()
        let closeConfiguration = app.buttons["关闭服务器配置"]
        XCTAssertTrue(closeConfiguration.waitForExistence(timeout: 10))
        closeConfiguration.tap()
        app.buttons["关闭设置"].tap()
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        let live = app.buttons["live.open"]
        XCTAssertTrue(live.waitForExistence(timeout: 30), app.debugDescription)
        live.tap()
        let close = app.buttons["收起 Live"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        close.tap()
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
    }
    @MainActor
    func testHistoricalRaceResultsAndLapDataReturn() {
        let app = XCUIApplication()
        app.launchArguments = ["-serverAddress", "http://127.0.0.1:38702"]
        app.launchEnvironment["PITPULSE_LIVE_SERVER_URL"] = "http://127.0.0.1:38702"
        app.launch()
        defer { app.terminate() }
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 20))
        tabs.buttons["赛历"].tap()
        let meeting = app.buttons["meeting.2026:20"]
        _ = meeting.waitForExistence(timeout: 20)
        for _ in 0..<8 {
            if meeting.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(meeting.isHittable, app.debugDescription)
        meeting.tap()
        let race = app.buttons["session.2026:20:race"]
        for _ in 0..<8 {
            if race.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(race.isHittable, app.debugDescription)
        race.tap()
        let driver = app.buttons["result.norris"]
        _ = driver.waitForExistence(timeout: 30)
        for _ in 0..<8 {
            if driver.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(driver.isHittable, app.debugDescription)
        driver.tap()
        let count = app.staticTexts["analysis.lapCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 150), app.debugDescription)
        XCTAssertEqual(count.label, "每圈节奏 · 71 圈")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        for _ in 0..<3 { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
    }

}
