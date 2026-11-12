import AppKit
import SwiftUI
import SharedData

struct LiveIslandDriverRow: View {
    @ObservedObject var model: AppModel
    @ObservedObject var actions: LiveIslandActions
    let driver: LiveDriver
    let snapshot: LiveSnapshot
    let favoriteID: String?
    let sectorBests: [String: [Double?]]
    let sectorWidth: CGFloat
    let wecTelemetryWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            followButton
            selectionButton
        }
    }

    private var driverID: String? {
        LiveIslandLogic.followableID(
            for: driver,
            favorites: model.favoriteDrivers,
            drivers: snapshot.drivers,
            isWec: snapshot.isWec
        )
    }

    // Follow state is driver identity, not just a car number:
    // a liked driver who has left the car is not "followed" anymore.
    private var followed: Bool {
        LiveIslandLogic.isFavoriteDriver(
            driver,
            favoriteId: favoriteID,
            favorites: model.favoriteDrivers
        )
    }

    private var followButton: some View {
        Button {
            if let driverID {
                model.setFavoriteDriver(
                    followed ? nil : driverID,
                    name: followed ? nil : driver.name,
                    series: snapshot.isWec ? .wec : .f1
                )
            }
        } label: {
            Image(systemName: followed ? "star.fill" : "star")
                .font(.caption)
                .foregroundStyle(followed ? Color.yellow : Color.gray)
                .frame(width: 25)
        }
        .buttonStyle(.plain)
        .disabled(driverID == nil)
        .accessibilityLabel(followed ? "取消关注车手" : "关注车手")
        .accessibilityIdentifier("liveIsland.follow.\(driver.number)")
    }

    private var selectionButton: some View {
        Button {
            actions.selectedNumber = driver.number
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let driverID {
                Button(followed ? "取消关注" : "关注车手") {
                    model.setFavoriteDriver(
                        followed ? nil : driverID,
                        name: followed ? nil : driver.name,
                        series: snapshot.isWec ? .wec : .f1
                    )
                }
            }
        }
        .help("点击查看车辆遥测，右键可关注车手")
        .accessibilityHint("激活后选择这名车手查看遥测")
        .accessibilityValue(followed ? "已关注" : "未关注")
        .accessibilityIdentifier("liveIsland.select.\(driver.number)")
        .accessibilityElement(children: .combine)
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            identity
            timingValue(driver.gap, label: "距领先车手", width: 58)
            timingValue(driver.interval, label: "距前车", width: 58)
            timingValue(driver.lastLap, label: "上一圈", width: 76)
            timingValue(driver.bestLap, label: "最佳圈", width: 76)
            sectorCells
            wecTelemetryCell
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            followed ? Color.blue.opacity(0.22) : Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private var identity: some View {
        HStack(spacing: 7) {
            Text(driver.position.map(String.init) ?? "—")
                .font(.system(.body, design: .rounded).weight(.bold))
                .frame(width: 24)
                .accessibilityLabel("名次 P\(driver.position.map(String.init) ?? "未知")")
            if snapshot.isWec {
                LiveManufacturerLogo(driver: driver, season: model.selectedSeason)
            } else {
                LiveHelmetView(model: model, driver: driver, size: 32, isWec: false)
            }
            identityText
        }
        .frame(width: 199, alignment: .leading)
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(driver.name ?? "#\(driver.number)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            statusLine
        }
    }

    private var statusLine: some View {
        HStack(spacing: 5) {
            if !snapshot.isWec {
                if actions.showTire, driver.tireLabel != nil {
                    LiveTireInline(driver: driver)
                }
                if actions.showEnergy, driver.energyPercent != nil {
                    LiveEnergyInline(percent: driver.energyPercent)
                }
            }
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var statusText: String {
        if driver.retired == true { return "已退赛" }
        if driver.inPit == true { return "进站中" }
        return driver.team ?? "—"
    }

    private var sectorCells: some View {
        ForEach(0..<3) { index in
            LiveSectorView(
                sector: driver.sectors.flatMap { index < $0.count ? $0[index] : nil },
                index: index,
                showsSegments: !snapshot.isWec,
                referenceSeconds: classBestSector(index)
            )
            .frame(width: sectorWidth)
        }
    }

    private func classBestSector(_ index: Int) -> Double? {
        guard snapshot.isWec else { return nil }
        return sectorBests[driver.classId ?? "ALL"]?[index] ?? nil
    }

    private var wecTelemetryCell: some View {
        Group {
            if snapshot.isWec {
                LiveWecTireEnergyCell(
                    driver: driver,
                    showTire: actions.showTire,
                    showEnergy: actions.showEnergy
                )
                .frame(width: wecTelemetryWidth)
            }
        }
    }

    private func timingValue(_ text: String?, label: String, width: CGFloat) -> some View {
        let value = text.flatMap { $0.isEmpty ? nil : $0 }
        return Text(value ?? "—")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
            .accessibilityLabel("\(label)，\(value ?? "未提供")")
    }
}
