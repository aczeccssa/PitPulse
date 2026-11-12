#if os(iOS) || os(macOS)
import SwiftUI
import WidgetKit

#if DEBUG
struct WidgetSizePreview<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let families: [WidgetFamily]
    let content: (WidgetFamily) -> Content

    @State private var family: WidgetFamily
    @Namespace private var tabNamespace

    // 统一交互动画
    private let spring = Animation.bouncy(
        duration: 0.48,
        extraBounce: 0.06
    )

    private let contentFade = Animation.easeInOut(
        duration: 0.22
    )

    init(
        families: [WidgetFamily],
        @ViewBuilder content: @escaping (WidgetFamily) -> Content
    ) {
        self.families = families
        self.content = content
        _family = State(initialValue: families[0])
    }

    private var size: CGSize {
        switch family {
        case .systemMedium:
            CGSize(width: 338, height: 158)
        case .systemLarge:
            CGSize(width: 338, height: 354)
        default:
            CGSize(width: 158, height: 158)
        }
    }

    private var widgetBackground: Color {
        colorScheme == .dark
            ? Color(white: 0.11)
            : .white
    }

    var body: some View {
        VStack(spacing: 16) {
            // 固定预览空间，Widget 始终居中
            ZStack {
                widgetPreview
            }
            .frame(maxWidth: .infinity)
            .frame(height: 354)

            sizeSelector
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .frame(width: 400, height: 470)
        .background(
            colorScheme == .dark
                ? .black
                : Color(
                    red: 242 / 255,
                    green: 242 / 255,
                    blue: 247 / 255
                )
        )
    }

    // MARK: - Widget Preview

    private var widgetPreview: some View {
        ZStack {
            content(family)
                .padding(16)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .id(family)
                .transition(
                    .opacity.animation(contentFade)
                )
        }
        .frame(
            width: size.width,
            height: size.height
        )
        .background(
            widgetBackground,
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
    }

    // MARK: - Size Selector

    private var sizeSelector: some View {
        HStack(spacing: 4) {
            ForEach(families, id: \.self) { option in
                sizeButton(for: option)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: Capsule())
    }

    private func sizeButton(
        for option: WidgetFamily
    ) -> some View {
        let selected = family == option

        return Button {
            guard family != option else { return }

            withAnimation(spring) {
                family = option
            }
        } label: {
            Image(systemName: symbol(for: option))
                .font(.system(
                    size: 16,
                    weight: .semibold
                ))
                .foregroundStyle(
                    selected ? Color.accentColor : Color.secondary
                )
                .scaleEffect(selected ? 1.1 : 1.0)
                .frame(width: 60, height: 36)
                .contentShape(Capsule())
                .background {
                    if selected {
                        Capsule()
                            .fill(
                                Color.accentColor.opacity(0.18)
                            )
                            .matchedGeometryEffect(
                                id: "selectedTab",
                                in: tabNamespace
                            )
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            selected ? [.isSelected] : []
        )
    }

    private func symbol(
        for family: WidgetFamily
    ) -> String {
        switch family {
        case .systemLarge: "widget.large"
        case .systemMedium: "widget.medium"
        default: "widget.small"
        }
    }
}

#endif
#endif
