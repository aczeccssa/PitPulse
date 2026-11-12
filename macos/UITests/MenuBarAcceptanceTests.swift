import AppKit
import XCTest

final class MenuBarAcceptanceTests: XCTestCase {
    @MainActor
    func isIslandOnScreen() -> Bool {
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
    func checkSettingsWindow(appearance: String) throws {
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
    func staticText(containing value: String, in popup: XCUIElement) -> XCUIElement {
        popup.staticTexts.matching(NSPredicate(format: "value CONTAINS[c] %@", value)).firstMatch
    }

    @MainActor
    func attachScreenshot(_ name: String, from popup: XCUIElement) {
        // OpenNook content appears in AX before its 0.3-second blur transition settles.
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let screenshot = XCTAttachment(screenshot: popup.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func postControl(_ path: String) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:38702\(path)")!)
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, String(decoding: data, as: UTF8.self))
    }

    @MainActor
    func reopenResults(in popup: XCUIElement) {
        popup.radioButtons["比赛"].click()
        popup.radioButtons["成绩"].click()
    }
}
