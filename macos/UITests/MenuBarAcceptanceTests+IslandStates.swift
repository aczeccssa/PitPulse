import AppKit
import XCTest

extension MenuBarAcceptanceTests {
    @MainActor
    func testLiveIslandMenuBarManualAndFavoriteSelection() throws {
        let app = XCUIApplication(bundleIdentifier: "com.pitpulse.F1Companion")
        app.launchArguments = ["-serverAddress", "http://127.0.0.1:38701", "-notchAutoShowEnabled", "NO", "-selectedSeason", "2026", "-favoriteDriverId", "sample-one"]
        app.launch()
        defer { app.terminate() }

        let island = app.descendants(matching: .any).matching(identifier: "opennook.panel").firstMatch
        XCTAssertFalse(island.waitForExistence(timeout: 3), app.debugDescription)
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), app.debugDescription)
        guard statusItem.isHittable else {
            let diagnostic = XCTAttachment(string: app.debugDescription)
            diagnostic.name = "T14 AX snapshot: status item outside hittable area"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            XCTFail("Status item is not hittable; AX frame=\(statusItem.frame). Compare LiveIsland AppKit screen logs; do not change display configuration.")
            return
        }
        statusItem.click()
        let popup = app.dialogs.containing(.staticText, identifier: "PitPulse").firstMatch
        XCTAssertTrue(popup.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(staticText(containing: "Live：回放", in: popup).waitForExistence(timeout: 10), popup.debugDescription)
        attachScreenshot("T14 menu bar works with automatic display off", from: popup)
        popup.buttons["menuBar.liveIsland"].click()
        XCTAssertTrue(island.waitForExistence(timeout: 10), app.debugDescription)
        let picker = island.popUpButtons["liveIsland.favoriteDriver"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), island.debugDescription)
        picker.click()
        XCTAssertTrue(app.menuItems["Sample Driver Two"].waitForExistence(timeout: 5), app.debugDescription)
        app.menuItems["Sample Driver Two"].click()
        XCTAssertTrue(staticText(containing: "Sample Driver Two  P2  +1.200", in: island).waitForExistence(timeout: 10), island.debugDescription)
        attachScreenshot("T14 stable favorite ID selection and timing", from: island)
        statusItem.click()
        XCTAssertTrue(popup.waitForExistence(timeout: 5), app.debugDescription)
        popup.buttons["menuBar.liveIsland"].click()
        let hiddenPanel = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !self.isIslandOnScreen()
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hiddenPanel], timeout: 5), .completed, app.debugDescription)
        XCTAssertTrue(staticText(containing: "Live：回放", in: popup).exists, popup.debugDescription)
    }

    @MainActor
    func testLiveIslandFinishedHidesAfterThirtySeconds() throws {
        let app = XCUIApplication(bundleIdentifier: "com.pitpulse.F1Companion")
        app.launchArguments = ["-serverAddress", "http://127.0.0.1:38701", "-notchAutoShowEnabled", "YES"]
        app.launch()
        defer { app.terminate() }
        let island = app.descendants(matching: .any).matching(identifier: "opennook.panel").firstMatch
        XCTAssertTrue(island.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(isIslandOnScreen(), "No rendered island window")
        XCTAssertEqual(NSRunningApplication.runningApplications(withBundleIdentifier: "com.pitpulse.F1Companion").count, 1)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !self.isIslandOnScreen()
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 28), .timedOut, "Finished panel hid before its 30-second stay")
        attachScreenshot("T14 finished session stays briefly", from: island)
        // AX retains hidden windows here; WindowServer is the independent visibility source.
        let hiddenAfterDelay = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !self.isIslandOnScreen()
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hiddenAfterDelay], timeout: 30), .completed, app.debugDescription)
        XCTAssertNotEqual(app.state, .notRunning)
        XCTAssertEqual(NSRunningApplication.runningApplications(withBundleIdentifier: "com.pitpulse.F1Companion").count, 1)
        attachScreenshot("T14 finished session panel hidden", from: app)
    }

    @MainActor
    func testLiveIslandSessionSwitchCancelsOldFinishedHide() async throws {
        let app = XCUIApplication(bundleIdentifier: "com.pitpulse.F1Companion")
        app.launchArguments = ["-serverAddress", "http://127.0.0.1:38701", "-notchAutoShowEnabled", "YES"]
        app.launch()
        defer { app.terminate() }
        let island = app.descendants(matching: .any).matching(identifier: "opennook.panel").firstMatch
        XCTAssertTrue(island.waitForExistence(timeout: 20), app.debugDescription)
        island.buttons["liveIsland.expand"].click()
        XCTAssertTrue(staticText(containing: "Replay Practice", in: island).waitForExistence(timeout: 5), island.debugDescription)
        let newSession = island.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Qualifying")).firstMatch
        XCTAssertTrue(newSession.waitForExistence(timeout: 40), island.debugDescription)
        XCTAssertFalse(staticText(containing: "Replay Practice", in: island).waitForExistence(timeout: 5), island.debugDescription)
        try await Task.sleep(for: .seconds(32))
        XCTAssertTrue(isIslandOnScreen(), "Old finished-session timer hid the new Session")
        XCTAssertTrue(newSession.exists, island.debugDescription)
        attachScreenshot("T14 new session survives old finished hide timer", from: island)
    }
}
