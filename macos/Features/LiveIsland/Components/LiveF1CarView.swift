import AppKit
import SwiftUI
import SharedData

struct LiveF1CarView: View {
    @ObservedObject var model: AppModel
    let driver: LiveDriver?
    let snapshot: LiveSnapshot

    private var followed: Bool {
        guard let driver else { return false }
        return LiveIslandLogic.isFavoriteDriver(
            driver,
            favoriteId: model.favoriteDriverId(for: .f1),
            favorites: model.favoriteDrivers
        )
    }

    private var followID: String? {
        guard let driver else { return nil }
        return LiveIslandLogic.followableDriverID(
            for: driver,
            favorites: model.favoriteDrivers,
            drivers: snapshot.drivers
        )
    }

    private var detail: String {
        guard let driver else { return "" }
        return [driver.team, driver.tireLabel].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                if let driver {
                    LiveHelmetView(model: model, driver: driver, size: 30, isWec: false)
                    if let teamID = LiveIslandLogic.carSideAssetID(for: driver, isWec: false),
                       let image = MotorsportAsset.image(kind: .carSide, id: teamID, season: model.selectedSeason) {
                        Image(nsImage: image)
                            .resizable().scaledToFit()
                            .frame(width: 132, height: 32)
                    }
                    LiveTeamLogo(driver: driver, season: model.selectedSeason, isWec: false, size: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("#\(driver.number) \(driver.name ?? "车手")")
                                .font(.caption.weight(.semibold)).lineLimit(1)
                            if let position = driver.position {
                                Text("P\(position)")
                                    .font(.caption2.weight(.bold)).monospacedDigit()
                            }
                            if let gap = driver.gap, !gap.isEmpty {
                                Text(gap)
                                    .font(.caption2).monospacedDigit()
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                            Button {
                                guard let followID else { return }
                                model.setFavoriteDriver(
                                    followed ? nil : followID,
                                    name: followed ? nil : driver.name,
                                    series: .f1
                                )
                            } label: {
                                Image(systemName: followed ? "star.fill" : "star")
                                    .font(.caption2)
                                    .foregroundStyle(followed ? Color.yellow : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(followID == nil)
                            .help(followed ? "取消关注该车手" : "关注该车手")
                            .accessibilityLabel(followed ? "取消关注该车手" : "关注该车手")
                        }
                        Text(detail)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if let data = driver.telemetry,
                       snapshot.sourceMode == .replay || LiveFreshness.isFresh(data.receivedAt ?? data.utc, now: context.date) {
                        HStack(spacing: 10) {
                            metric("速度", data.speed, "km/h")
                            metric("RPM", data.rpm, "")
                            metric("挡位", data.gear, "")
                        }
                    }
                } else {
                    Text("No selected").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ label: String, _ value: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.0f", $0) + unit } ?? "—").monospacedDigit()
        }
        .font(.caption2)
    }
}

