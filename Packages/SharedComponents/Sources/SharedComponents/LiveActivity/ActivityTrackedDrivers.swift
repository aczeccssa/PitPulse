#if os(iOS)
import SwiftUI
import SharedData

struct TrackedDriverView: View {
    let driver: PitPulseActivityAttributes.Driver
    let weather: PitPulseActivityAttributes.Weather?
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                DriverPortrait(driver: driver, size: 66)
                VStack(alignment: .leading, spacing: 5) {
                    Text(driver.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    HStack { metric("距领先", driver.gap); metric("距前车", driver.interval) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                DriverWeatherView(weather: weather)
            }
            SectorStrip(sectors: driver.sectors)
            HStack {
                metric("速度", driver.speed.map { "\($0) km/h" })
                Spacer(minLength: 4)
                metric("轮胎", driver.tire)
                Spacer(minLength: 4)
                metric("上圈", driver.lastLap)
            }
        }
    }
    private func metric(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            ActivityNumberText(value ?? "—").font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BattleView: View {
    let state: PitPulseActivityAttributes.ContentState
    private var drivers: [PitPulseActivityAttributes.Driver] {
        state.battleDrivers ?? [.init(name: state.leaderName ?? "—", position: 1, asset: state.leaderAsset), .init(name: state.challengerName ?? "—", position: 2, asset: state.challengerAsset)]
    }
    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                if let first = drivers.first { driverColumn(first) }
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    ActivityNumberText((state.battleDrivers == nil ? state.challengerGap : state.battleGap) ?? "—").font(.system(size: 27, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    Text("两车差距").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if drivers.count > 1 { driverColumn(drivers[1]) }
            }

        }
    }
    private func driverColumn(_ driver: PitPulseActivityAttributes.Driver) -> some View {
        VStack(spacing: 9) {
            DriverPortrait(driver: driver, size: 58)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    let sector = driver.sectors.indices.contains(index) ? driver.sectors[index] : nil
                    VStack(spacing: 3) {
                        Text("S\(index + 1)").font(.system(size: 9)).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 2).fill(sectorColor(sector)).frame(height: 5)
                    }
                    .accessibilityLabel("S\(index + 1)，\(sector?.time ?? "未完成")")
                }
            }
            ActivityNumberText(driver.tire ?? "—").font(.system(size: 9)).foregroundStyle(.secondary)
        }.frame(width: 88)
    }

    private func sectorColor(_ sector: PitPulseActivityAttributes.Sector?) -> Color {
        guard let sector, let time = sector.time, !time.isEmpty else { return .white.opacity(0.15) }
        if sector.overallFastest == true { return .purple }
        if sector.personalFastest == true { return .green }
        return .yellow
    }

}

#endif
