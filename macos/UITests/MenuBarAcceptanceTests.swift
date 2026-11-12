import AppKit
import XCTest

final class MenuBarAcceptanceTests: XCTestCase {
    @MainActor
    private func isIslandOnScreen() -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.pitpulse.F1Companion")
        XCTAssertEqual(apps.count, 1, "UI acceptance must use exactly one main App")
        guard apps.count == 1 else { return false }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // The pinned OpenNook panel uses statusBar + 8; this avoids hidden AX remnants.
        let panels = windows.filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == apps[0].processIdentifier
                && ($0[kCGWindowLayer as String] as? Int) == NSWindow.Level.statusBar.rawValue + 8
        }
        XCTAssertLessThanOrEqual(panels.count, 1, "Multiple rendered Nook panels")
        return !panels.isEmpty
    }

    @MainActor
    func testLiveIslandFloatingOnExistingExternalDisplay() throws {
        guard let external = NSScreen.screens.first(where: {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) == 0 && $0.safeAreaInsets.top == 0
        }), let id = external.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            XCTFail("An actual connected external display without a notch is required")
            return
        }
        let app = XCUIApplication(bundleIdentifier: "com.pitpulse.F1Companion")
        app.launchArguments = ["-serverAddress", "http://127.0.0.1:38701", "-notchAutoShowEnabled", "YES"]
        app.launchEnvironment["PITPULSE_ACCEPTANCE_SCREEN"] = "external"
        app.launch()
        defer { app.terminate() }
        let island = app.descendants(matching: .any).matching(identifier: "opennook.panel").firstMatch
        XCTAssertTrue(island.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(isIslandOnScreen())
        let collapse = island.buttons["liveIsland.collapse"]
        if collapse.exists { collapse.click() }
        let expand = island.buttons["liveIsland.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5), app.debugDescription)
        let screenBounds = CGDisplayBounds(id.uint32Value)
        XCTAssertTrue(screenBounds.contains(CGPoint(x: expand.frame.midX, y: expand.frame.midY)), "Actual external screen: \(screenBounds), content: \(expand.frame)")
        XCTAssertGreaterThanOrEqual(expand.frame.minY, screenBounds.minY + NSStatusBar.system.thickness)
        attachScreenshot("T14 real external display floating compact", from: island)
        expand.click()
        XCTAssertTrue(staticText(containing: "Race Control", in: island).waitForExistence(timeout: 5))
        attachScreenshot("T14 real external display floating expanded", from: island)
    }

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

    @MainActor
    func testLiveIslandAutoShowsReplayAndExpands() throws {
        let app = XCUIApplication(bundleIdentifier: "com.pitpulse.F1Companion")
        app.launchArguments = [
            "-serverAddress", "http://127.0.0.1:38701",
            "-notchAutoShowEnabled", "YES"
        ]
        app.launch()
        defer { app.terminate() }

        let island = app.descendants(matching: .any)
            .matching(identifier: "opennook.panel")
            .firstMatch
        XCTAssertTrue(island.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(staticText(containing: "回放", in: island).waitForExistence(timeout: 10), island.debugDescription)
        let collapse = island.buttons["liveIsland.collapse"]
        if collapse.exists { collapse.click() }
        XCTAssertTrue(island.buttons["liveIsland.expand"].waitForExistence(timeout: 5), island.debugDescription)
        attachScreenshot("T14 compact replay Live Island", from: island)

        let expandButton = island.buttons.matching(identifier: "liveIsland.expand").firstMatch
        XCTAssertTrue(expandButton.waitForExistence(timeout: 5), island.debugDescription)
        expandButton.click()
        XCTAssertTrue(staticText(containing: "Race Control", in: island).waitForExistence(timeout: 10), island.debugDescription)
        XCTAssertTrue(staticText(containing: "轮胎与进站 · 未提供", in: island).exists, island.debugDescription)
        XCTAssertTrue(
            island.descendants(matching: .any).matching(identifier: "liveIsland.favoriteDriver").firstMatch.exists,
            island.debugDescription
        )
        attachScreenshot("T14 expanded replay Live Island", from: island)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(expandButton.waitForExistence(timeout: 5), "Escape should compact the explicitly focused panel")
        attachScreenshot("T14 keyboard Escape compacts Live Island", from: island)
    }

    @MainActor
    func testLiveIslandMissingFieldsUsePlaceholdersAndIgnoreUnknownRaceControlFields() throws {
        let app = XCUIApplication(bundleIdentifier: "com.pitpulse.F1Companion")
        app.launchArguments = [
            "-serverAddress", "http://127.0.0.1:38701",
            "-notchAutoShowEnabled", "YES",
            "-favoriteDriverId", "max-verstappen"
        ]
        app.launch()
        defer { app.terminate() }

        let island = app.descendants(matching: .any)
            .matching(identifier: "opennook.panel")
            .firstMatch
        XCTAssertTrue(island.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(staticText(containing: "第 — 圈", in: island).waitForExistence(timeout: 10), island.debugDescription)

        island.buttons.matching(identifier: "liveIsland.expand").firstMatch.click()
        XCTAssertTrue(staticText(containing: "Other", in: island).waitForExistence(timeout: 10), island.debugDescription)
        XCTAssertTrue(staticText(containing: "No selected", in: island).exists, island.debugDescription)
        XCTAssertFalse(staticText(containing: "Replay fixture only", in: island).exists, island.debugDescription)
        attachScreenshot("T14 missing fields and unknown Race Control fields", from: island)
    }

    @MainActor
    func testLiveIslandStaleRemovesTimingValues() throws {
        let app = XCUIApplication(bundleIdentifier: "com.pitpulse.F1Companion")
        app.launchArguments = [
            "-serverAddress", "http://127.0.0.1:38701",
            "-notchAutoShowEnabled", "YES"
        ]
        app.launch()
        defer { app.terminate() }

        let island = app.descendants(matching: .any)
            .matching(identifier: "opennook.panel")
            .firstMatch
        XCTAssertTrue(island.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(staticText(containing: "回放 · 数据过期", in: island).waitForExistence(timeout: 30), island.debugDescription)
        let collapse = island.buttons["liveIsland.collapse"]
        if collapse.exists { collapse.click() }
        let expand = island.buttons.matching(identifier: "liveIsland.expand").firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 5), island.debugDescription)
        XCTAssertFalse(expand.label.contains("圈"), expand.label)
        XCTAssertFalse(expand.label.contains("名次"), expand.label)
        XCTAssertFalse(expand.label.contains("间隔"), expand.label)
        attachScreenshot("T14 degraded compact without timing labels", from: island)
        expand.click()
        XCTAssertTrue(staticText(containing: "Replay Practice", in: island).waitForExistence(timeout: 5), island.debugDescription)
        XCTAssertFalse(staticText(containing: "Sample Driver", in: island).exists, island.debugDescription)
        XCTAssertFalse(staticText(containing: "Race Control", in: island).exists, island.debugDescription)
        attachScreenshot("T14 stale Live Island", from: island)
    }

    @MainActor
    func testLiveIslandDisconnectedRetainsSessionWithoutTimingValues() throws {
        let app = XCUIApplication(bundleIdentifier: "com.pitpulse.F1Companion")
        app.launchArguments = [
            "-serverAddress", "http://127.0.0.1:38701",
            "-notchAutoShowEnabled", "YES"
        ]
        app.launch()
        defer { app.terminate() }

        let island = app.descendants(matching: .any)
            .matching(identifier: "opennook.panel")
            .firstMatch
        XCTAssertTrue(island.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(staticText(containing: "回放 · 已断开", in: island).waitForExistence(timeout: 30), island.debugDescription)
        let collapse = island.buttons["liveIsland.collapse"]
        if collapse.exists { collapse.click() }
        let expand = island.buttons.matching(identifier: "liveIsland.expand").firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 5), island.debugDescription)
        XCTAssertFalse(expand.label.contains("圈"), expand.label)
        XCTAssertFalse(expand.label.contains("名次"), expand.label)
        XCTAssertFalse(expand.label.contains("间隔"), expand.label)
        attachScreenshot("T14 degraded compact without timing labels", from: island)
        expand.click()
        XCTAssertTrue(staticText(containing: "Replay Practice", in: island).waitForExistence(timeout: 5), island.debugDescription)
        XCTAssertFalse(staticText(containing: "Sample Driver", in: island).exists, island.debugDescription)
        XCTAssertFalse(staticText(containing: "Race Control", in: island).exists, island.debugDescription)
        attachScreenshot("T14 disconnected Live Island", from: island)
    }

    @MainActor
    func testLiveReplayAndDisconnectedMenuBarStates() throws {
        let replayApp = XCUIApplication(bundleIdentifier: "com.pitpulse.F1Companion")
        replayApp.launchArguments = ["-serverAddress", "http://127.0.0.1:38701"]
        replayApp.launch()
        defer { replayApp.terminate() }

        let replayStatusItem = replayApp.statusItems.firstMatch
        XCTAssertTrue(replayStatusItem.waitForExistence(timeout: 10), replayApp.debugDescription)
        guard replayStatusItem.isHittable else {
            throw XCTSkip("macOS reports the status item outside the hittable area on this multi-display desktop")
        }
        let replayPopup = replayApp.dialogs.firstMatch
        if !replayPopup.exists { replayStatusItem.click() }
        XCTAssertTrue(replayPopup.waitForExistence(timeout: 5), replayApp.debugDescription)
        XCTAssertTrue(staticText(containing: "回放", in: replayPopup).waitForExistence(timeout: 15), replayPopup.debugDescription)
        attachScreenshot("T13 replay state in Menu Bar", from: replayPopup)

        replayApp.terminate()

        let disconnectedApp = XCUIApplication(bundleIdentifier: "com.pitpulse.F1Companion")
        disconnectedApp.launchArguments = ["-serverAddress", "http://127.0.0.1:38709"]
        disconnectedApp.launch()
        defer { disconnectedApp.terminate() }

        let disconnectedStatusItem = disconnectedApp.statusItems.firstMatch
        XCTAssertTrue(disconnectedStatusItem.waitForExistence(timeout: 10), disconnectedApp.debugDescription)
        guard disconnectedStatusItem.isHittable else {
            throw XCTSkip("macOS reports the status item outside the hittable area on this multi-display desktop")
        }
        let disconnectedPopup = disconnectedApp.dialogs.firstMatch
        if !disconnectedPopup.exists { disconnectedStatusItem.click() }
        XCTAssertTrue(disconnectedPopup.waitForExistence(timeout: 5), disconnectedApp.debugDescription)
        XCTAssertTrue(staticText(containing: "PitPulse", in: disconnectedPopup).waitForExistence(timeout: 15), disconnectedPopup.debugDescription)
        attachScreenshot("T13 disconnected state in Menu Bar", from: disconnectedPopup)
    }

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

    @MainActor
    private func checkSettingsWindow(appearance: String) throws {
        let app = XCUIApplication(bundleIdentifier: "com.pitpulse.F1Companion")
        app.launchArguments = [
            "-serverAddress", "http://127.0.0.1:38701",
            "-notchAutoShowEnabled", "NO",
            "-AppleInterfaceStyle", appearance,
            "-NSRequiresAquaSystemAppearance", appearance == "Light" ? "YES" : "NO"
        ]
        app.launch()
        defer { app.terminate() }

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), app.debugDescription)

        // The status item can settle a moment after launch on a crowded menu
        // bar; wait briefly before falling back to the suite-wide skip.
        let deadline = Date().addingTimeInterval(5)
        while !statusItem.isHittable, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        guard statusItem.isHittable else {
            throw XCTSkip("macOS reports the status item outside the hittable area on this multi-display desktop")
        }

        let popup = app.dialogs.firstMatch
        if !popup.exists { statusItem.click() }
        XCTAssertTrue(popup.waitForExistence(timeout: 5), app.debugDescription)
        popup.buttons["menuBar.settings"].click()

        let settingsWindow = app.windows.matching(
            NSPredicate(format: "title CONTAINS[c] %@ OR title CONTAINS[c] %@", "Settings", "设置")
        ).firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10), app.debugDescription)

        XCTAssertTrue(
            settingsWindow.staticTexts["服务器地址"].waitForExistence(timeout: 5),
            settingsWindow.debugDescription
        )
        XCTAssertFalse(
            settingsWindow.toolbars.buttons["Hide Sidebar"].exists,
            "NavigationSplitView's Hide Sidebar toolbar item should be removed"
        )

        let promoted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.pitpulse.F1Companion")
                .first?.activationPolicy == .regular
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [promoted], timeout: 5), .completed, "App should become .regular while Settings is open")

        attachScreenshot("T05 \(appearance) connection", from: settingsWindow)

        for (section, content) in [
            ("reminders", "preferences.reminders"),
            ("liveIsland", "preferences.notchAutoShow")
        ] {
            settingsWindow.staticTexts["preferences.section.\(section)"].click()
            XCTAssertTrue(settingsWindow.switches[content].waitForExistence(timeout: 5), settingsWindow.debugDescription)
            attachScreenshot("T05 \(appearance) \(section)", from: settingsWindow)
        }
        settingsWindow.staticTexts["preferences.section.favoriteDriver"].click()
        XCTAssertTrue(settingsWindow.staticTexts["按稳定车手 ID 保存；车队变更不会改变关注对象。"].waitForExistence(timeout: 5), settingsWindow.debugDescription)
        attachScreenshot("T05 \(appearance) favoriteDriver", from: settingsWindow)
        settingsWindow.staticTexts["preferences.section.connection"].click()
        XCTAssertTrue(settingsWindow.textFields["preferences.serverAddress"].waitForExistence(timeout: 5))

        app.typeKey("w", modifierFlags: [.command])
        XCTAssertTrue(settingsWindow.waitForNonExistence(timeout: 10), "Cmd+W should close the Settings window")

        let demoted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.pitpulse.F1Companion")
                .first?.activationPolicy == .accessory
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [demoted], timeout: 5), .completed, "App should return to .accessory after Settings closes")

        statusItem.click()
        XCTAssertTrue(popup.waitForExistence(timeout: 5))
        popup.buttons["menuBar.settings"].click()
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        let promotedAgain = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.pitpulse.F1Companion")
                .first?.activationPolicy == .regular
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [promotedAgain], timeout: 5), .completed)
        app.typeKey(",", modifierFlags: [.command])
        XCTAssertTrue(settingsWindow.exists)
        XCTAssertEqual(app.windows.matching(NSPredicate(format: "identifier == %@", "com_apple_SwiftUI_Settings_window")).count, 1)
        app.typeKey("w", modifierFlags: [.command])
        XCTAssertTrue(settingsWindow.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func staticText(containing value: String, in popup: XCUIElement) -> XCUIElement {
        popup.staticTexts.matching(NSPredicate(format: "value CONTAINS[c] %@", value)).firstMatch
    }

    @MainActor
    private func attachScreenshot(_ name: String, from popup: XCUIElement) {
        // OpenNook content appears in AX before its 0.3-second blur transition settles.
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
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
        popup.radioButtons["比赛"].click()
        popup.radioButtons["成绩"].click()
    }
}
