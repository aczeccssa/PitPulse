import AppKit
import SwiftUI
import SharedData

struct LiveStrip: View {
    let snapshot: LiveSnapshot
    let favorite: LiveDriver?
    let isVisible: Bool
    let expand: () -> Void

    private var driver: LiveDriver? {
        favorite ?? snapshot.drivers.first
    }

    var body: some View {
        Button(action: expand) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(PitPulseTheme.accent).frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(PitPulseTheme.accent)
                }
                Text(snapshot.meetingName ?? snapshot.sessionName ?? "实时会话")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(snapshot.lapLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                if let driver {
                    Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow)
                    Text(driver.name ?? "#\(driver.number)")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(driver.classLabel ?? "P\(driver.position.map(String.init) ?? "—")")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    if let gap = driver.gap {
                        Text(gap)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(PitPulseTheme.accent.opacity(0.10)).interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("展开 Live Island")
        .accessibilityLabel("展开 Live Island，\(snapshot.meetingName ?? "实时会话")")
    }
}
