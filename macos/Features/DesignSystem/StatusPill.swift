import AppKit
import SwiftUI
import SharedData

struct StatusPill: View {
    let text: String
    var tint: Color = .secondary
    var showsDot = true

    var body: some View {
        HStack(spacing: 5) {
            if showsDot {
                Circle().fill(tint).frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.3)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: Capsule())
    }
}
