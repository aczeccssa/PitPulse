import AppKit
import SwiftUI
import SharedData

extension SessionResultsView {
    var classificationTable: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("分类").font(.system(size: 12.5, weight: .semibold)).tracking(0.6)
                    Spacer()
                    Text("用时 / 差距").font(.system(size: 10.5, weight: .medium))
                    Text("积分").font(.system(size: 10.5, weight: .medium)).frame(width: 30, alignment: .trailing)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 11)
                .padding(.bottom, 7)

                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

                ForEach(Array(sortedResults.enumerated()), id: \.element.id) { index, result in
                    VStack(spacing: 0) {
                        Button {
                            selectedResult = result
                        } label: {
                            resultRow(result)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("查看完整比赛数据")
                        .accessibilityIdentifier("results.row.\(result.driverId)")

                        if index != sortedResults.count - 1 {
                            Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1)
                                .padding(.leading, 46)
                        }
                    }
                }
            }
        }
    }

    func resultRow(_ result: SessionResult) -> some View {
        HStack(spacing: 8) {
            Text(result.position.map(String.init) ?? "—")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
                .foregroundStyle(result.position == 1 ? PitPulseTheme.accent : .secondary)

            helmetImage(result, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.driverName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(result.team)
                    if result.classification != "classified" {
                        Text("· \(result.classificationLabel)")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(resultTime(result))
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 92, alignment: .trailing)

            Text(result.points.map { String(format: "%g", $0) } ?? "—")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    func resultTime(_ result: SessionResult) -> String {
        switch selectedSession?.session.sessionType {
        case .qualifying, .sprintQualifying:
            return result.q3 ?? result.q2 ?? result.q1 ?? "—"
        case .fp1, .fp2, .fp3:
            return result.bestLap ?? "—"
        default:
            if let raceTime = result.raceTime ?? result.time, !raceTime.isEmpty { return raceTime }
            return result.gap ?? result.bestLap ?? "—"
        }
    }
}
