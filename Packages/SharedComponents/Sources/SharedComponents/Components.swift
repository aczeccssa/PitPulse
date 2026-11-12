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
    public init(countryCode: String?) { self.countryCode = countryCode }
    public var body: some View { Text(CountryFlag.emoji(for: countryCode) ?? "🏁") }
}

/// Widget-facing compact view; depends only on the value contract.
public struct LiveWidgetCard: View {
    public let content: WidgetContent
    public init(content: WidgetContent) { self.content = content }
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.meetingName ?? "PitPulse").font(.headline).lineLimit(1)
            Text(content.sessionName ?? "—").font(.subheadline)
            HStack {
                Text(content.statusLabel ?? "离线").font(.caption)
                if let lap = content.lapLabel { Text(lap).font(.caption.monospacedDigit()) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(content.isStale ? 0.7 : 1)
    }
}
