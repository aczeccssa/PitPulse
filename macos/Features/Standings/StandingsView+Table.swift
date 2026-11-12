import AppKit
import SwiftUI
import SharedData

extension StandingsView {
    // MARK: Table

    var table: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("POS").frame(width: 26, alignment: .leading)
                    Text(isConstructor ? "车队" : "车手")
                    Spacer()
                    Text("胜").frame(width: 22, alignment: .trailing)
                    Text("积分").frame(width: 44, alignment: .trailing)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

                if isConstructor {
                    ForEach(Array(sortedConstructors.enumerated()), id: \.element.id) { index, row in
                        tableRow(
                            rank: row.position,
                            title: row.constructorName,
                            subtitle: "\(row.wins) 场胜利",
                            wins: row.wins,
                            points: row.points,
                            selected: effectiveSelection == row.constructorId,
                            image: MotorsportAsset.image(kind: .teamLogo, id: row.constructorId, season: model.selectedSeason),
                            isLast: index == sortedConstructors.count - 1
                        ) {
                            selectedID = row.constructorId
                            openDetail(row.constructorId)
                        }
                    }
                } else {
                    ForEach(Array(sortedDrivers.enumerated()), id: \.element.id) { index, row in
                        tableRow(
                            rank: row.position,
                            title: row.driverName,
                            subtitle: row.constructor,
                            wins: row.wins,
                            points: row.points,
                            selected: effectiveSelection == row.driverId,
                            image: MotorsportAsset.f1HelmetImage(id: row.driverId, season: model.selectedSeason),
                            isLast: index == sortedDrivers.count - 1
                        ) {
                            selectedID = row.driverId
                            openDetail(row.driverId)
                        }
                    }
                }
            }
        }
    }

    func tableRow(
        rank: Int,
        title: String,
        subtitle: String,
        wins: Int,
        points: Double,
        selected: Bool,
        image: NSImage?,
        isLast: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Text(String(rank))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(rank == 1 ? PitPulseTheme.accent : .secondary)
                        .frame(width: 26, alignment: .leading)

                    if let image {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                    } else if isConstructor {
                        Text(MotorsportAsset.abbreviation(title))
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 24, height: 24)
                            .background(.primary.opacity(0.06), in: Circle())
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "helmet.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(.primary.opacity(0.06), in: Circle())
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Text(String(wins))
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)

                    Text(points.formatted())
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(PitPulseTheme.accentSoft)
                            .padding(.horizontal, 6)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("第 \(rank) 名 \(title)，\(points.formatted()) 分，\(wins) 胜")
            .accessibilityHint("查看赛季分析")
            .accessibilityIdentifier("standings.row.\(rank)")

            if !isLast {
                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1)
                    .padding(.leading, 52)
            }
        }
    }

    func openDetail(_ id: String) {
        if isConstructor, let row = sortedConstructors.first(where: { $0.constructorId == id }) {
            detail = StandingDetailTarget(
                kind: "constructors",
                id: row.constructorId,
                title: row.constructorName,
                season: row.season,
                position: row.position,
                points: row.points,
                wins: row.wins,
                team: nil
            )
        } else if let row = sortedDrivers.first(where: { $0.driverId == id }) {
            detail = StandingDetailTarget(
                kind: "drivers",
                id: row.driverId,
                title: row.driverName,
                season: row.season,
                position: row.position,
                points: row.points,
                wins: row.wins,
                team: row.constructor
            )
        }
    }

    func selectedTitle(_ id: String) -> String {
        isConstructor
            ? sortedConstructors.first { $0.constructorId == id }?.constructorName ?? id
            : sortedDrivers.first { $0.driverId == id }?.driverName ?? id
    }

    func selectedPoints(_ id: String) -> Double {
        isConstructor
            ? sortedConstructors.first { $0.constructorId == id }?.points ?? 0
            : sortedDrivers.first { $0.driverId == id }?.points ?? 0
    }
}
