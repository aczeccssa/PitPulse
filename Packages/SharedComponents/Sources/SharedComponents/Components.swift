import Foundation
import SwiftUI
import SharedData

public struct StatusPill: View {
    public let text: String
    public let systemName: String
    public init(_ text: String, systemName: String) { self.text = text; self.systemName = systemName }
    public var body: some View {
        Label(text, systemImage: systemName).font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

public struct CountdownText: View {
    public let until: Date
    public init(until: Date) { self.until = until }
    public var body: some View { Text(until, style: .relative).font(.caption.monospacedDigit()) }
}

public struct FlagBadge: View {
    public let countryCode: String?
    private let width: CGFloat
    private let height: CGFloat?

    public init(countryCode: String?, width: CGFloat = 18, fitsWidth: Bool = false, height: CGFloat? = nil) {
        self.countryCode = countryCode
        self.width = width
        self.height = height ?? (fitsWidth ? nil : width * 0.7)
    }

    public var body: some View {
        Group {
            if let code = CountryFlag.normalizedCode(countryCode)?.lowercased(),
               let flag = flagImage(named: "flag-\(code)") {
                flag.resizable().scaledToFit().clipShape(.rect(cornerRadius: 2))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: width * 0.65))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height)
    }

    private func flagImage(named name: String) -> Image? {
        #if os(macOS)
        MotorsportImages.nsImage(named: name).map { Image(nsImage: $0) }
        #else
        MotorsportImages.uiImage(named: name).map { Image(uiImage: $0) }
        #endif
    }
}

/// Widget-facing compact view; depends only on the value contract.
public struct LiveWidgetCard: View {
    public let content: WidgetContent
    public init(content: WidgetContent) { self.content = content }
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.meetingName ?? "PitPulse").font(.headline).lineLimit(1)
            Text(widgetDisplayLabel(content.sessionName ?? "—")).font(.subheadline)
            HStack {
                Text(widgetDisplayLabel(content.statusLabel ?? widgetCopy("Offline", "离线"))).font(.caption)
                if let lap = content.lapLabel { Text(widgetDisplayLabel(lap)).font(.caption.monospacedDigit()) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(content.isStale ? 0.7 : 1)
    }
}

func widgetCopy(_ english: @autoclosure () -> String, _ original: @autoclosure () -> String) -> String {
    #if os(iOS)
    english()
    #else
    original()
    #endif
}

func widgetDisplayLabel(_ value: String) -> String {
    #if os(iOS)
    switch value {
    case "正赛": "Race"
    case "排位赛": "Qualifying"
    case "Sprint 排位": "Sprint Qualifying"
    case "已结束", "已完赛": "Finished"
    case "进行中": "In Progress"
    case "实时": "Live"
    case "回放": "Replay"
    case "回放 · 数据过期": "Replay · Stale"
    case "回放 · 已断开": "Replay · Disconnected"
    case "等待实时数据": "Waiting for data"
    case "数据过期": "Stale"
    case "已断开": "Disconnected"
    case "— 圈": "—"
    default: value
    }
    #else
    value
    #endif
}
