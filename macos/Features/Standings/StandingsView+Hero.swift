import AppKit
import SwiftUI
import SharedData

extension StandingsView {
    // MARK: Hero — top three entries

    struct HeroEntry: Identifiable {
        let id: String
        let rank: Int
        let name: String
        let detail: String
        let points: Double
        let image: NSImage?
    }

    var heroEntries: [HeroEntry] {
        if isConstructor {
            return sortedConstructors.prefix(3).map { row in
                HeroEntry(
                    id: row.constructorId,
                    rank: row.position,
                    name: row.constructorName,
                    detail: "\(row.wins) 胜",
                    points: row.points,
                    image: MotorsportAsset.image(kind: .teamLogo, id: row.constructorId, season: model.selectedSeason)
                )
            }
        }
        return sortedDrivers.prefix(3).map { row in
            HeroEntry(
                id: row.driverId,
                rank: row.position,
                name: row.driverName,
                detail: "\(row.wins) 胜",
                points: row.points,
                image: MotorsportAsset.f1HelmetImage(id: row.driverId, season: model.selectedSeason)
            )
        }
    }

    // MARK: Hero — the top three in plain 1 · 2 · 3 order

    var hero: some View {
        GlassCard(padding: 12) {
            VStack(spacing: 8) {
                CardHeader(title: "前三名")
                HStack(spacing: 6) {
                    ForEach(heroEntries) { entry in
                        heroCard(entry)
                    }
                }
            }
        }
    }

    func heroCard(_ entry: HeroEntry) -> some View {
        Button { selectedID = entry.id } label: {
            VStack(spacing: 4) {
                heroImage(entry, size: 46)

                Text(entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 4) {
                    Text("\(entry.points.formatted()) 分")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("·")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("P\(entry.rank)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PitPulseTheme.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(entry.rank) 名 \(entry.name)，\(entry.points.formatted()) 分，\(entry.detail)")
    }

    @ViewBuilder
    func heroImage(_ entry: HeroEntry, size: CGFloat) -> some View {
        if isConstructor {
            Group {
                if let image = entry.image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Circle().fill(.primary.opacity(0.07))
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else {
            DriverHelmetAvatar(
                driverID: entry.id,
                name: entry.name,
                season: model.selectedSeason,
                size: size
            )
        }
    }
}
