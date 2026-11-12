import AppKit
import SwiftUI
import SharedData

struct SeasonLeaderCard: View {
    @EnvironmentObject var model: AppModel

    var leaders: [DriverStanding] {
        Array(model.driverStandings.sorted { $0.position < $1.position }.prefix(3))
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "\(String(model.selectedSeason)) 车手积分")
                if leaders.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("积分榜载入后显示领跑者")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(leaders.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 8) {
                                Text(String(row.position))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(index == 0 ? PitPulseTheme.accent : .secondary)
                                    .frame(width: 18, alignment: .trailing)
                                DriverHelmetAvatar(
                                    driverID: row.driverId,
                                    name: row.driverName,
                                    season: model.selectedSeason,
                                    size: 26
                                )
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.driverName)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .lineLimit(1)
                                    Text(row.constructor)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                Text("\(row.points.formatted()) 分")
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                Text("\(row.wins) 胜")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                            .padding(.vertical, 8)
                            if index != leaders.count - 1 {
                                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
        .task(id: "\(model.selectedSeason)-\(model.serverAddress)") {
            model.ensureDriverStandingsLoaded()
        }
    }
}
