import SharedData
import SwiftUI

extension View {
    func liveLandscapePanel<Fill: ShapeStyle>(_ fill: Fill, line: Color = WebDashboardStyle.homeLine) -> some View {
        clipShape(PulseStyle.cardShape)
            .dashboardPanel(fill, line: line)
    }
}

struct LiveLandscapeDriverPanel: View {
    @EnvironmentObject private var model: MobileModel
    let driver: LiveDriver
    let close: () -> Void

    var body: some View {
        GeometryReader { layout in
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        AssetImage(name: model.helmetAsset(for: driver)).frame(width: 28, height: 27)
                        Text(driver.name ?? "#\(driver.number)")
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if let position = driver.position ?? driver.classPosition {
                            PulseNumber("P\(position)").font(.subheadline.bold().monospacedDigit())
                        }
                        Button("Close driver details", systemImage: "xmark", action: close)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .frame(width: 30, height: 32)
                    }
                    HStack(spacing: 5) {
                        LiveTireBadge(driver: driver, size: 15)
                        PulseNumber(driver.tireAgeLaps.map { "\($0) laps" } ?? "—")
                        LiveDriverTrackStatus(driver: driver, showsOnTrack: true)
                        Spacer(minLength: 4)
                        PulseNumber("Best \(driver.bestLap ?? "—")")
                        PulseNumber("Last lap \(driver.lastLap ?? "—")")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    Divider()
                    LiveSectorTimes(sectors: driver.sectors ?? [], showsSegments: true)
                }
                .padding(8)
                .liveLandscapePanel(WebDashboardStyle.homePanel)
                TelemetryChartPanel(samples: model.liveHistory[driver.number] ?? [], driver: driver,
                                    pedalHeight: max(46, layout.size.height * 0.20))
            }
        }
        .accessibilityIdentifier("live.landscape.driver")
    }
}

struct LiveBattleDashboard: View {
    @EnvironmentObject private var model: MobileModel
    let front: LiveDriver
    let back: LiveDriver

    private var gap: String? { IslandBattleSelection.gap(between: [front, back]) }
    private var lapHistory: [String: [LiveCompletedLap]] { model.recentLiveLaps[model.series] ?? [:] }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                driverIdentity(front)
                VStack(spacing: 1) {
                    Text("LIVE GAP").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    PulseNumber(gap ?? "—")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(PulseStyle.red)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("live.landscape.battle.gap")
                }
                .frame(minWidth: 84)
                driverIdentity(back)
            }
            sectors
            HStack(spacing: 8) {
                LiveBattleGauge(driver: front)
                LiveBattleGauge(driver: back)
            }
            lapTimes
        }
        .accessibilityIdentifier("live.landscape.battle")
    }

    private func driverIdentity(_ driver: LiveDriver) -> some View {
        let team = LiveIslandLogic.teamAssetID(for: driver, isWec: model.liveSnapshot.isWec)
        return HStack(spacing: 6) {
            Text((driver.position ?? driver.classPosition).map { "P\($0)" } ?? "—")
                .font(.caption.bold().monospacedDigit())
            if let team {
                AssetImage(name: MotorsportAssetName.name(kind: .teamLogo, id: team, season: model.season))
                    .frame(width: 24, height: 20)
            }
            Text(driver.name ?? "#\(driver.number)")
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            LiveTireBadge(driver: driver, size: 15)
            if let age = driver.tireAgeLaps { Text("\(age)").font(.caption2.monospacedDigit()) }
        }
        .padding(8)
        .liveLandscapePanel(WebDashboardStyle.homePanel, line: team.map(DashboardArt.teamColor) ?? WebDashboardStyle.homeLine)
    }

    private var sectors: some View {
        let left = front.sectors ?? []
        let right = back.sectors ?? []
        return HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                let a = left.indices.contains(index) ? left[index].value : nil
                let b = right.indices.contains(index) ? right[index].value : nil
                let difference = delta(a, b)
                let tint = difference.map { $0 <= 0 ? Color.green : PulseStyle.red } ?? .secondary
                HStack(spacing: 5) {
                    Text("S\(index + 1)").foregroundStyle(.secondary)
                    PulseNumber(difference.map(formatDelta) ?? "—").foregroundStyle(tint)
                }
                .font(.caption2.bold().monospacedDigit())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(tint.opacity(0.13), in: .rect(cornerRadius: 5))
            }
        }
    }

    private var lapTimes: some View {
        let left = lapHistory[front.number] ?? []
        let right = lapHistory[back.number] ?? []
        let numbers = Array(Set((left + right).map(\.number)).sorted().suffix(2))
        return HStack(spacing: 8) {
            Text("Last Two Laps").font(.caption2.bold()).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if numbers.isEmpty {
                Text("No lap times received").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            ForEach(numbers, id: \.self) { number in
                let a = left.first { $0.number == number }?.time
                let b = right.first { $0.number == number }?.time
                HStack(spacing: 6) {
                    Text("L\(number)").foregroundStyle(.secondary)
                    PulseNumber(a ?? "—")
                    PulseNumber(b ?? "—")
                    if let difference = delta(a, b) {
                        PulseNumber(formatDelta(difference)).foregroundStyle(difference <= 0 ? .green : PulseStyle.red)
                    }
                }
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Lap \(number), left \(a ?? "Unavailable"), right \(b ?? "Unavailable")")
            }
        }
        .padding(8)
        .liveLandscapePanel(WebDashboardStyle.homePanel)
    }

    private func delta(_ left: String?, _ right: String?) -> Double? {
        guard let a = left.flatMap(LiveIslandLogic.sectorSeconds),
              let b = right.flatMap(LiveIslandLogic.sectorSeconds),
              a.isFinite, b.isFinite, a > 0, b > 0 else { return nil }
        return b - a
    }

    private func formatDelta(_ value: Double) -> String {
        String(format: "%+.3f", value)
    }
}

private struct LiveBattleGauge: View {
    let driver: LiveDriver
    private var telemetry: LiveTelemetry? { driver.telemetry }

    var body: some View {
        GeometryReader { layout in
            let size = max(0, min(layout.size.height - 8, layout.size.width * 0.60, 164))
            HStack(spacing: 12) {
                ZStack {
                    gaugeTrack(value: telemetry?.speed, limit: 360, start: 140, sweep: 260, tint: .blue)
                    let inset = size * 0.14
                    gaugeTrack(value: telemetry?.throttle, limit: 100, start: 135, sweep: 98, tint: .green)
                        .padding(inset)
                    gaugeTrack(value: telemetry?.brake, limit: 100, start: 307, sweep: 98, tint: PulseStyle.red)
                        .padding(inset)
                    VStack(spacing: 1) {
                        PulseNumber(number(telemetry?.speed))
                            .font(.system(size: max(12, size * 0.23), weight: .bold, design: .rounded).monospacedDigit())
                        Text("KM/H").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: size, height: size)
                .pulseChart()
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(MotorsportAssetName.abbreviation(driver.name ?? driver.number)).font(.headline)
                    PulseNumber("RPM \(number(telemetry?.rpm))")
                    PulseNumber("GEAR \(number(telemetry?.gear))")
                    Label("Throttle \(percent(telemetry?.throttle))", systemImage: "circle.fill")
                        .foregroundStyle(.green)
                    Label("Brake \(percent(telemetry?.brake))", systemImage: "circle.fill")
                        .foregroundStyle(PulseStyle.red)
                }
                .font(.caption2.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .liveLandscapePanel(WebDashboardStyle.homePanel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(driver.name ?? driver.number), speed \(number(telemetry?.speed)), RPM \(number(telemetry?.rpm)), gear \(number(telemetry?.gear)), throttle \(percent(telemetry?.throttle)), brake \(percent(telemetry?.brake))")
    }

    private func gaugeTrack(value: Double?, limit: Double, start: Double, sweep: Double, tint: Color) -> some View {
        let end = sweep / 360
        let fraction = value.flatMap { $0.isFinite ? min(max($0 / limit, 0), 1) : nil } ?? 0
        return ZStack {
            Circle().trim(from: 0, to: end)
                .stroke(.secondary.opacity(0.20), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            if fraction > 0 {
                Circle().trim(from: 0, to: end * fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }
        .rotationEffect(.degrees(start))
        .padding(4)
    }

    private func number(_ value: Double?) -> String {
        value.flatMap { $0.isFinite ? $0.formatted(.number.grouping(.never).precision(.fractionLength(0))) : nil } ?? "—"
    }

    private func percent(_ value: Double?) -> String {
        value.map { number($0) + "%" } ?? "—"
    }
}
