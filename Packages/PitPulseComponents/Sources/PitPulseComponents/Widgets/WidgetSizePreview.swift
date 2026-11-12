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

    init(families: [WidgetFamily], @ViewBuilder content: @escaping (WidgetFamily) -> Content) {
        self.families = families
        self.content = content
        _family = State(initialValue: families[0])
    }

    private var size: CGSize {
        switch family {
        case .systemMedium: CGSize(width: 338, height: 158)
        case .systemLarge: CGSize(width: 338, height: 354)
        default: CGSize(width: 158, height: 158)
        }
    }

    var body: some View {
        VStack {
            Spacer()

            content(family)
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background(colorScheme == .dark ? Color(white: 0.11) : .white,
                            in: RoundedRectangle(cornerRadius: 20))

            Spacer(minLength: 72)
        }
        .overlay(alignment: .bottom, content: {
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    ForEach(families, id: \.self) { option in
                        Button {
                            family = option
                        } label: {
    //                        Text(
    //                            option == .systemLarge ? "大" :
    //                            option == .systemMedium ? "中" : "小"
    //                        )
                            Image(systemName:
                                option == .systemLarge ? "widget.large" :
                                    option == .systemMedium ? "widget.medium" : "widget.small"
                            )
                            .font(.system(
                                size: 16,
                                weight: family == option ? .bold : .regular
                            ))
                            .foregroundStyle(
                                family == option ? Color.accentColor : Color.gray
                            )
                            .contentTransition(.interpolate)
                            .animation(.bouncy(duration: 0.35, extraBounce: 0.12), value: family)
                            .frame(width: 60, height: 36)
                            .contentShape(Capsule())
                            .background {
                                if family == option {
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.18))
                                        .matchedGeometryEffect(
                                            id: "selectedTab",
                                            in: tabNamespace
                                        )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            family == option ? [.isSelected] : []
                        )
                    }
                }
                .padding(4)
                .glassEffect(.regular, in: Capsule())
                .animation(.smooth(duration: 0.28), value: family)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        })
        .padding(24)
        .frame(width: 400, height: 470)
        .background(colorScheme == .dark ? .black : Color(red: 242 / 255, green: 242 / 255, blue: 247 / 255))
    }
}
#endif
#endif
