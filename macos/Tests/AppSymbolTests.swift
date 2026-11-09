import AppKit
import XCTest
@testable import PitPulseData
@testable import PitPulseDesktop

@MainActor
final class AppSymbolTests: XCTestCase {
    func testEverySemanticSymbolAlwaysResolves() {
        for symbol in AppSymbol.allCases {
            let resolved = symbol.resolvedSystemName()
            XCTAssertNotNil(
                NSImage(systemSymbolName: resolved, accessibilityDescription: symbol.accessibilityLabel),
                "Missing symbol for \(symbol.rawValue): \(resolved)"
            )
        }
    }

    func testStatusMappingIncludesNonColorStatus() {
        XCTAssertEqual(StatusSymbolResolver.symbol(for: .offline), .offline)
        XCTAssertEqual(StatusSymbolResolver.symbol(for: .requiresToken), .offline)
        XCTAssertEqual(StatusSymbolResolver.symbol(for: .stale), .cache)
        XCTAssertEqual(StatusSymbolResolver.symbol(for: .failed), .warning)
    }
}

@MainActor
final class CalendarScrollAppearanceTests: XCTestCase {
    func testCalendarScrollUsesTransparentAutoHidingOverlay() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .legacy
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = true
        CalendarScrollAppearance.configure(scrollView)
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertEqual(scrollView.verticalScroller?.controlSize, .small)
        XCTAssertFalse(scrollView.drawsBackground)
    }
}
