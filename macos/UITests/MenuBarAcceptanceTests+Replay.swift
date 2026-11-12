import AppKit
import XCTest

extension MenuBarAcceptanceTests {
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
}
