import AppKit
import SwiftUI
import SharedData

struct CalendarScrollAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollStyleAnchor {
        ScrollStyleAnchor()
    }

    func updateNSView(_ nsView: ScrollStyleAnchor, context: Context) {
        nsView.applyToEnclosingScrollView()
    }

    static func configure(_ scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.controlSize = .small
        scrollView.horizontalScroller?.controlSize = .small
        scrollView.drawsBackground = false
    }

    final class ScrollStyleAnchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyToEnclosingScrollView()
        }

        func applyToEnclosingScrollView() {
            // SwiftUI may install the background before attaching its NSScrollView.
            DispatchQueue.main.async { [weak self] in
                guard let scrollView = self?.enclosingScrollView else { return }
                CalendarScrollAppearance.configure(scrollView)
            }
        }
    }
}
