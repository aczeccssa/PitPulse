import AppKit
import SwiftUI
import SharedData

/// Liquid Glass card used by every page, so the popup reads as one system.
struct GlassCard<Content: View>: View {
    var radius: CGFloat = PitPulseTheme.cardRadius
    var padding: CGFloat = 14
    @ViewBuilder let content: () -> Content

    init(radius: CGFloat = PitPulseTheme.cardRadius, padding: CGFloat = 14, @ViewBuilder content: @escaping () -> Content) {
        self.radius = radius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct CardHeader: View {
    let title: String
    var actionTitle: String? = nil
    var actionSymbol: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(actionTitle)
                        if let actionSymbol {
                            Image(systemName: actionSymbol).font(.system(size: 9, weight: .bold))
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PitPulseTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
