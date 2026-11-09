import SwiftUI
import PitPulseData
import PitPulseShared

struct LiveScreen: View {
    @EnvironmentObject private var model: MobileModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LiveHeader(
                        snapshot: model.liveSnapshot,
                        connecting: model.liveConnecting,
                        running: model.isLiveRunning
                    )
                }

                if model.sortedDrivers.isEmpty {
                    Section {
                        if model.liveConnecting {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("正在连接 Live…")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text(model.isLiveRunning ? "暂无车手数据，等待下一帧。" : "点右上角「连接」开始接收实时计时。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section("计时 · \(model.sortedDrivers.count) 位") {
                        ForEach(model.sortedDrivers, id: \.number) { driver in
                            DriverRow(driver: driver, isWec: model.liveSnapshot.isWec)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Live")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.isLiveRunning ? "断开" : "连接") {
                        model.toggleLive()
                    }
                }
            }
            .task { model.autoStartLiveOnce() }
        }
    }
}

private struct LiveHeader: View {
    let snapshot: LiveSnapshot
    let connecting: Bool
    let running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(snapshot.meetingName ?? "未连接")
                    .font(.headline)
                Spacer()
                Text(connecting ? "连接中" : snapshot.statusLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(statusColor)
            }
            Text("\(snapshot.sessionName ?? "—") · \(snapshot.sessionStateLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 18) {
                metric("圈数", snapshot.lapLabel)
                metric("赛道", snapshot.trackCondition.label)
                if let remaining = snapshot.remainingLabel {
                    metric("剩余", remaining)
                }
            }
            if let updated = snapshot.lastUpdatedLabel {
                Text("更新于 \(updated) · \(snapshot.drivers.count) 位车手")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.monospacedDigit())
        }
    }

    private var statusColor: Color {
        if connecting { return .orange }
        switch snapshot.sourceStatus {
        case .connected: return .green
        case .stale: return .orange
        case .disconnected: return .gray
        }
    }
}

private struct DriverRow: View {
    let driver: LiveDriver
    let isWec: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(driver.position.map(String.init) ?? "–")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(width: 26, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(driver.name ?? "Car \(driver.number)")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if let tire = driver.tireShortLabel {
                        Text(tire)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(driver.gap ?? driver.interval ?? "—")
                    .font(.caption.monospacedDigit())
                if let laps = driver.lapCount {
                    Text("L\(laps)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let team = driver.team, !team.isEmpty { parts.append(team) }
        if isWec, let classLabel = driver.classLabel { parts.append(classLabel) }
        if let energy = driver.energyLabel { parts.append(energy) }
        return parts.joined(separator: " · ")
    }
}
