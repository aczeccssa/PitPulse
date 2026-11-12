import AppKit
import SwiftUI
import SharedData

struct LiveTrackStatusBadge: View {
    let snapshot: LiveSnapshot
    var compact = false

    private var color: Color {
        switch snapshot.trackCondition {
        case .clear: return .green
        case .yellow, .fullCourseYellow, .safetyCar: return .yellow
        case .virtualSafetyCar, .virtualSafetyCarEnding, .safetyCarEnding: return .orange
        case .red: return .red
        case .unknown: return .gray
        }
    }

    private var label: String {
        switch snapshot.sourceStatus {
        case .stale: return "赛道状态过期"
        case .disconnected: return "赛道状态不可用"
        case .connected: return snapshot.trackCondition.label
        }
    }

    var body: some View {
        Group {
            if let code = snapshot.trackCondition.code {
                HStack(spacing: compact ? 2 : 3) {
                    Image(systemName: snapshot.trackCondition.systemName)
                        .font(.system(size: compact ? 9 : 11, weight: .semibold))
                    Text(code)
                        .font(.system(size: compact ? 9 : 10, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(color)
                .padding(.horizontal, compact ? 5 : 7)
                .frame(height: compact ? 18 : 22)
                .background(color.opacity(0.16), in: Capsule())
            } else {
                Image(systemName: snapshot.trackCondition.systemName)
                    .font(.system(size: compact ? 13 : 20, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: compact ? 22 : 32, height: compact ? 18 : 28)
            }
        }
            .overlay(alignment: .bottomTrailing) {
                if snapshot.trackCondition == .safetyCarEnding || snapshot.trackCondition == .virtualSafetyCarEnding {
                    Image(systemName: "clock.fill")
                        .font(.system(size: compact ? 8 : 10))
                        .foregroundStyle(color)
                        .background(.black, in: Circle())
                }
            }
            .help(label)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier("liveIsland.trackStatus")
    }
}
