import AppKit
import SwiftUI
import SharedData

extension SessionResultsView {
    func leaderCard(_ result: SessionResult) -> some View {
        Button { selectedResult = result } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("P\(result.position ?? 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(podiumTime(result))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .foregroundStyle(PitPulseTheme.accent)

                helmetImage(result, size: 52)

                Text(result.driverName)
                    .font(.system(size: 16.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("\(result.points.map { String(format: "%g", $0) } ?? "—") 分")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PitPulseTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("冠军 \(result.driverName)，\(result.team)，\(podiumTime(result))")
        .accessibilityHint("查看完整比赛数据")
    }

    func runnerCard(_ result: SessionResult, rank: Int) -> some View {
        Button { selectedResult = result } label: {
            VStack(spacing: 4) {
                helmetImage(result, size: 44)

                Text(result.driverName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 4) {
                    Text("\(result.points.map { String(format: "%g", $0) } ?? "—") 分")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("·")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("P\(result.position ?? rank)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PitPulseTheme.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(result.position ?? rank) 名 \(result.driverName)，\(podiumTime(result))")
        .accessibilityHint("查看完整比赛数据")
    }

    func helmetImage(_ result: SessionResult, size: CGFloat) -> some View {
        DriverHelmetAvatar(
            driverID: result.driverId,
            name: result.driverName,
            season: model.selectedSeason,
            size: size
        )
    }

    func podiumTime(_ result: SessionResult) -> String {
        if let raceTime = result.raceTime ?? result.time { return raceTime }
        if let gap = result.gap, !gap.isEmpty { return gap }
        return result.bestLap ?? "—"
    }
}
