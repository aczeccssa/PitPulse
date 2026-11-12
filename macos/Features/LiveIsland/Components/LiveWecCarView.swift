import AppKit
import SwiftUI
import SharedData

struct LiveWecCarView: View {
    @ObservedObject var model: AppModel
    let driver: LiveDriver?
    let showTire: Bool
    let showEnergy: Bool

    private var detail: String {
        guard let driver else { return "" }
        return [driver.classLabel, driver.team].compactMap { $0 }.joined(separator: " · ")
    }

    private var followed: Bool {
        guard let driver else { return false }
        return LiveIslandLogic.isFavoriteDriver(
            driver,
            favoriteId: model.favoriteDriverId(for: .wec),
            favorites: model.favoriteDrivers
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            if let driver {
                LiveHelmetView(model: model, driver: driver, size: 30, isWec: true)
                if let carID = LiveIslandLogic.carSideAssetID(for: driver, isWec: true),
                   let image = MotorsportAsset.image(kind: .carSide, id: carID, season: model.selectedSeason) {
                    Image(nsImage: image)
                        .resizable().scaledToFit()
                        .frame(width: 120, height: 35)
                }
                LiveTeamLogo(driver: driver, season: model.selectedSeason, isWec: true, size: 18)
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
                            model.setFavoriteDriver(
                                followed ? nil : "wec:\(driver.number)",
                                name: followed ? nil : driver.name,
                                series: .wec
                            )
                        } label: {
                            Image(systemName: followed ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundStyle(followed ? Color.yellow : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(followed ? "取消关注该车手" : "关注该车手")
                        .accessibilityLabel(followed ? "取消关注该车手" : "关注该车手")
                    }
                    Text(detail)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                if showTire, driver.tireLabel != nil {
                    HStack(spacing: 4) {
                        Text("轮胎").foregroundStyle(.secondary)
                        LiveTireInline(driver: driver, fontSize: 11)
                    }
                    .font(.caption2)
                }
                if showEnergy, driver.energyPercent != nil {
                    HStack(spacing: 4) {
                        Text("能量").foregroundStyle(.secondary)
                        LiveEnergyInline(percent: driver.energyPercent)
                    }
                    .font(.caption2)
                }
            } else {
                Text("No selected").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

