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
}
