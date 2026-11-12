import AppKit
import SwiftUI
import SharedData

/// Shared Liquid Glass segmented control used by secondary pages.
struct LiquidSegmented<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: String

        var id: Value { value }
    }

    let items: [Item]
    @Binding var selection: Value
    var compact = false

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(items) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selection = item.value }
                    } label: {
                        Text(item.title)
                            .font(.system(size: compact ? 11 : 11.5, weight: .semibold))
                            .foregroundStyle(selection == item.value ? PitPulseTheme.accent : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, compact ? 4 : 6)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        selection == item.value
                            ? .regular.tint(PitPulseTheme.accent.opacity(0.18)).interactive()
                            : .regular.interactive(),
                        in: Capsule()
                    )
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(selection == item.value ? .isSelected : [])
                }
            }
        }
    }
}
