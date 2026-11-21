import Charts
import SharedData
import SwiftUI

extension View {
    func liveTabletPanelTitle() -> some View {
        font(.subheadline.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .accessibilityAddTraits(.isHeader)
    }

    func liveLandscapePanel<Fill: ShapeStyle>(_ fill: Fill, line: Color = WebDashboardStyle.homeLine) -> some View {
        clipShape(PulseStyle.cardShape)
            .dashboardPanel(fill, line: line)
    }
}

struct LiveLandscapeDriverPanel: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let driver: LiveDriver
    var isTablet = false
    var panelHandle: AnyView? = nil
    let close: () -> Void

    var body: some View {
        GeometryReader { layout in
            if isTablet {
                let sideBySide = layout.size.width >= 340
                    || (layout.size.width >= 286 && layout.size.height < 360)
                let dialWidth = sideBySide ? min(118, layout.size.width * 0.30) : nil
                let contentHeight = max(layout.size.height, sideBySide ? 276 : 480)
                ScrollView {
                    tabletPanel(dialWidth: dialWidth)
                        .frame(height: contentHeight)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                panel(pedalHeight: max(46, layout.size.height * 0.20))
            }
        }
        .accessibilityIdentifier("live.landscape.driver")
    }

    private var driverHeading: some View {
        HStack(spacing: 6) {
            AssetImage(name: model.helmetAsset(for: driver)).frame(width: 28, height: 27)
            Text(driver.name ?? "#\(driver.number)")
                .font(isTablet ? .headline : .subheadline.bold())
                .lineLimit(1)
            Spacer(minLength: 2)
            if let position = driver.position ?? driver.classPosition {
                PulseNumber("P\(position)").font(.subheadline.bold().monospacedDigit())
            }
            panelHandle
            Button(action: close) {
                if isTablet {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(.primary.opacity(0.08), in: .circle)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                } else {
                    Image(systemName: "xmark")
                        .frame(width: 30, height: 32)
                        .contentShape(.rect)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close driver details")
            .accessibilityIdentifier("live.driver.close")
        }
    }

    private var driverSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            driverHeading
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    trackSummary.fixedSize()
                    Spacer(minLength: 4)
                    lapSummary.fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    trackSummary
                    lapSummary
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            Divider()
            LiveSectorTimes(sectors: driver.sectors ?? [], showsSegments: true, compactSegments: isTablet)
        }
        .padding(isTablet ? 10 : 8)
        .liveLandscapePanel(WebDashboardStyle.homePanel)
    }

    private var trackSummary: some View {
        HStack(spacing: 5) {
            LiveTireBadge(driver: driver, size: 15)
            PulseNumber(driver.tireAgeLaps.map { "\($0) laps" } ?? "—")
            LiveDriverTrackStatus(driver: driver, showsOnTrack: true)
        }
    }

    private var lapSummary: some View {
        HStack(spacing: 6) {
            PulseNumber("Best \(driver.bestLap ?? "—")")
            PulseNumber("Last lap \(driver.lastLap ?? "—")")
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func tabletPanel(dialWidth: CGFloat?) -> some View {
        let sideBySide = dialWidth != nil
        let layout = sideBySide ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 6))
        let tint = LiveIslandLogic.teamAssetID(for: driver, isWec: model.liveSnapshot.isWec)
            .map(DashboardArt.teamColor) ?? .blue
        return VStack(spacing: 8) {
            driverSummary
            layout {
                LiveTabletBattleDial(driver: driver, tint: tint, expanded: false, identifierPrefix: "live.driver.gauge")
                    .frame(width: dialWidth)
                TelemetryChartPanel(samples: model.liveHistory[driver.number] ?? [], driver: driver, isTablet: true)
            }
            .padding(10)
            .liveLandscapePanel(PulseStyle.surface)
            .animation(reduceMotion ? nil : .snappy(duration: 0.26), value: sideBySide)
        }
    }

    private func panel(pedalHeight: CGFloat) -> some View {
        VStack(spacing: 8) {
            driverSummary
            TelemetryChartPanel(samples: model.liveHistory[driver.number] ?? [], driver: driver, pedalHeight: pedalHeight)
        }
    }

}

struct LiveTabletBattleMetrics: View {
    @EnvironmentObject private var model: MobileModel
    let front: LiveDriver
    let back: LiveDriver
    var expanded = false
    var availableHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                tabletDriver(front)
                tabletDriver(back)
            }
            .overlay {
                Text("VS")
                    .font(.system(size: expanded ? 14 : 10, weight: .black, design: .rounded).italic())
                    .foregroundStyle(.secondary)
                    .frame(width: expanded ? 33 : 23, height: expanded ? 33 : 23)
                    .background(WebDashboardStyle.homePanel, in: .circle)
                    .overlay { Circle().strokeBorder(WebDashboardStyle.homeLine) }
                    .accessibilityHidden(true)
            }
            if expanded {
                comparisonDetails
                speedHistory
            } else {
                Divider()
                HStack(spacing: 8) {
                    LiveSectorTimes(sectors: front.sectors ?? [], showsSegments: true, compactSegments: true)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(front.name ?? front.number)
                    liveGap
                    LiveSectorTimes(sectors: back.sectors ?? [], showsSegments: true, compactSegments: true)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(back.name ?? back.number)
                }
                .font(.caption.monospacedDigit())
            }
        }
        .accessibilityIdentifier("live.landscape.battle")
    }

    private func tabletDriver(_ driver: LiveDriver) -> some View {
        let name = driver.name ?? "#\(driver.number)"
        let tint = driverColor(driver)
        return VStack(spacing: expanded ? 8 : 4) {
            Text(model.liveSnapshot.isWec ? "#\(driver.number)" : MotorsportAssetName.abbreviation(name))
                .font(.system(size: expanded ? 25 : 16, weight: .black))
                .foregroundStyle(tint)
                .accessibilityLabel(name)
                .lineLimit(1)
            LiveTabletBattleDial(driver: driver, tint: tint, expanded: expanded,
                                 diameterLimit: expanded ? max(42, min(225, (availableHeight - 295) / 0.84)) : nil)
        }
        .frame(maxWidth: .infinity)
    }

    private var comparisonDetails: some View {
        let left = model.recentLiveLaps[model.series]?[front.number] ?? []
        let right = model.recentLiveLaps[model.series]?[back.number] ?? []
        let laps = Set((left + right).map(\.number)).sorted(by: >).prefix(2)
        return VStack(spacing: 5) {
            Divider()
            HStack(spacing: 8) {
                driverSummary(front)
                liveGap
                driverSummary(back)
            }
            Divider()
            ForEach(0..<3) { index in
                sectorComparison(index)
            }
            Divider()
            Grid(horizontalSpacing: 8, verticalSpacing: 5) {
                metric("Best lap", front.bestLap, back.bestLap)
                ForEach(Array(laps), id: \.self) { lap in
                    metric("Lap \(lap)", left.first { $0.number == lap }?.time, right.first { $0.number == lap }?.time)
                }
            }
        }
        .font(.caption.monospacedDigit())
    }

    private var liveGap: some View {
        VStack(spacing: 3) {
            Text("Live gap").foregroundStyle(.secondary)
            Text(IslandBattleSelection.gap(between: [front, back]) ?? "—")
                .foregroundStyle(PulseStyle.red)
                .accessibilityIdentifier("live.landscape.battle.gap")
        }
        .frame(width: 66)
    }

    private func driverSummary(_ driver: LiveDriver) -> some View {
        HStack(spacing: 5) {
            Text((driver.position ?? driver.classPosition).map { "P\($0)" } ?? "—")
                .fontWeight(.bold)
            LiveTireBadge(driver: driver, size: 14)
            Text(driver.lapCount.map { "Lap \($0)" } ?? "Lap —")
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func sectorComparison(_ index: Int) -> some View {
        let left = sector(front, index)
        let right = sector(back, index)
        let gap: String
        if let a = left?.value.flatMap(LiveIslandLogic.sectorSeconds),
           let b = right?.value.flatMap(LiveIslandLogic.sectorSeconds),
           a.isFinite, b.isFinite, a > 0, b > 0 {
            let milliseconds = ((b - a) * 1000).rounded()
            gap = milliseconds == 0 ? "0.000" : String(format: "%+.3f", milliseconds / 1000)
        } else {
            gap = "—"
        }
        return HStack(spacing: 8) {
            LiveSectorTimingCell(sector: left, index: index, showsSegments: true, compactSegments: true)
            VStack(spacing: 2) {
                Text("S\(index + 1)").font(.caption2.bold()).foregroundStyle(.secondary)
                Text(gap).fontWeight(.semibold)
                    .accessibilityLabel("Right driver minus left, \(gap) seconds")
            }
            .frame(width: 66)
            LiveSectorTimingCell(sector: right, index: index, showsSegments: true, compactSegments: true)
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var speedHistory: some View {
        let frontSamples = speedSamples(for: front)
        let backSamples = speedSamples(for: back)
        if frontSamples.count > 1, backSamples.count > 1,
           let latest = (frontSamples + backSamples).map(\.time).max() {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("Speed").font(.caption.bold())
                    Spacer(minLength: 4)
                    speedLegend(front, symbol: "minus")
                    speedLegend(back, symbol: "ellipsis")
                }
                .font(.caption2.weight(.semibold))
                Chart {
                    speedLine(frontSamples, endingAt: latest, driver: front, dashed: false)
                    speedLine(backSamples, endingAt: latest, driver: back, dashed: true)
                }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text("\(Int(seconds))s")
                            }
                        }
                    }
                }
                .chartYAxisLabel("km/h")
                .chartLegend(.hidden)
                .accessibilityLabel("Speed over time for \(front.name ?? front.number) and \(back.name ?? back.number)")
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func speedSamples(for driver: LiveDriver) -> [(time: Date, speed: Double)] {
        (model.liveHistory[driver.number] ?? []).compactMap { sample in
            guard let time = RFC3339.parse(sample.utc), let speed = sample.speed, speed.isFinite else { return nil }
            return (time, speed)
        }
    }

    @ChartContentBuilder
    private func speedLine(_ samples: [(time: Date, speed: Double)], endingAt latest: Date,
                           driver: LiveDriver, dashed: Bool) -> some ChartContent {
        ForEach(samples.indices, id: \.self) { index in
            let sample = samples[index]
            LineMark(x: .value("Elapsed seconds", sample.time.timeIntervalSince(latest)),
                     y: .value("Speed", sample.speed),
                     series: .value("Car", driver.number))
                .foregroundStyle(driverColor(driver))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: dashed ? [4, 3] : []))
        }
    }

    private func speedLegend(_ driver: LiveDriver, symbol: String) -> some View {
        Label(model.liveSnapshot.isWec ? "#\(driver.number)" : MotorsportAssetName.abbreviation(driver.name ?? driver.number),
              systemImage: symbol)
            .foregroundStyle(driverColor(driver))
    }

    private func driverColor(_ driver: LiveDriver) -> Color {
        LiveIslandLogic.teamAssetID(for: driver, isWec: model.liveSnapshot.isWec).map(DashboardArt.teamColor) ?? .blue
    }

    private func metric(_ label: String, _ left: String?, _ right: String?) -> some View {
        GridRow {
            Text(left ?? "—").frame(maxWidth: .infinity)
            Text(label).foregroundStyle(.secondary).frame(width: 66)
            Text(right ?? "—").frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    private func sector(_ driver: LiveDriver, _ index: Int) -> LiveSector? {
        let sectors = driver.sectors ?? []
        return sectors.indices.contains(index) ? sectors[index] : nil
    }
}

private struct LiveTabletBattleDial: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let driver: LiveDriver
    let tint: Color
    let expanded: Bool
    var diameterLimit: CGFloat? = nil
    var identifierPrefix = "live.battle.gauge"

    private var telemetry: LiveTelemetry? { driver.telemetry }
    private var gear: String { telemetry?.gear == 0 ? "N" : number(telemetry?.gear) }

    var body: some View {
        VStack(spacing: expanded ? 3 : 0) {
            GeometryReader { geometry in
                let diameter = geometry.size.width
                let readings = [
                    finite(telemetry?.speed), finite(telemetry?.rpm),
                    finite(telemetry?.throttle), finite(telemetry?.brake)
                ]
                LiveTabletDialFace(tint: tint, diameter: diameter,
                                   speed: readings[0], rpm: readings[1],
                                   throttle: readings[2], brake: readings[3])
                    .id(readings.map { $0 != nil })
                    .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: readings)
                    .frame(width: diameter, height: diameter)
                    .position(x: diameter / 2, y: diameter / 2)
            }
            .aspectRatio(1 / 0.84, contentMode: .fit)
            .frame(maxWidth: diameterLimit ?? (expanded ? 240 : 158))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("GEAR")
                    .font(expanded ? .caption.bold() : .caption2.bold())
                    .foregroundStyle(.secondary)
                Text(gear)
                    .font(expanded ? .title3.bold().monospacedDigit() : .subheadline.bold().monospacedDigit())
                    .contentTransition(reduceMotion ? .identity : .numericText(value: finite(telemetry?.gear) ?? 0))
                    .animation(reduceMotion || finite(telemetry?.gear) == nil ? nil : .easeOut(duration: 0.16), value: gear)
            }
            .lineLimit(1)
        }
        .id(driver.number)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(driver.name ?? driver.number), speed \(number(telemetry?.speed)) kilometers per hour, RPM \(number(telemetry?.rpm)), gear \(gear), throttle \(percentage(telemetry?.throttle)), brake \(percentage(telemetry?.brake))")
        .accessibilityIdentifier("\(identifierPrefix).\(driver.number)")
    }

    private func finite(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite ? $0 : nil }
    }

    private func number(_ value: Double?) -> String {
        value.flatMap { $0.isFinite ? $0.formatted(.number.grouping(.never).precision(.fractionLength(0))) : nil } ?? "—"
    }

    private func percentage(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return number(value) + "%"
    }
}

private struct LiveTabletDialFace: View, Animatable {
    let tint: Color
    let diameter: CGFloat
    nonisolated var speed: Double?
    nonisolated var rpm: Double?
    nonisolated var throttle: Double?
    nonisolated var brake: Double?

    nonisolated var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get {
            AnimatablePair(AnimatablePair(speed ?? 0, rpm ?? 0), AnimatablePair(throttle ?? 0, brake ?? 0))
        }
        set {
            if speed != nil { speed = newValue.first.first }
            if rpm != nil { rpm = newValue.first.second }
            if throttle != nil { throttle = newValue.second.first }
            if brake != nil { brake = newValue.second.second }
        }
    }

    var body: some View {
        ZStack {
            arc(speed, limit: 360, start: 145, sweep: 250, color: tint,
                radius: diameter * 0.451, width: diameter * 0.074)
            ForEach(0...6, id: \.self) { step in
                let angle = 145.0 + Double(step) * 250 / 6
                polarLabel("\(step * 60)", angle: angle, radius: diameter * 0.451, fontSize: diameter * 0.049,
                           color: (speed ?? -1) >= Double(step * 60) ? .black.opacity(0.85) : .secondary)
            }
            arc(throttle, limit: 100, start: 145, sweep: 85, color: .green.opacity(0.78),
                radius: diameter * 0.337, width: diameter * 0.105)
            arc(brake, limit: 100, start: 310, sweep: 85, color: PulseStyle.red.opacity(0.78),
                radius: diameter * 0.337, width: diameter * 0.105)
            curvedLabel("THROTTLE", start: 161, end: 212, diameter: diameter)
            curvedLabel("BRAKE", start: 340, end: 377, diameter: diameter)

            VStack(spacing: 0) {
                Text(number(speed))
                    .font(.system(size: diameter * 0.195, weight: .black).monospacedDigit())
                Text("KM/H")
                    .font(.system(size: diameter * 0.055, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(number(rpm))
                    .font(.system(size: diameter * 0.105, weight: .black).monospacedDigit())
                    .padding(.top, diameter * 0.052)
                Text("RPM")
                    .font(.system(size: diameter * 0.048, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .offset(y: -diameter * 0.004)
        }
    }

    private func curvedLabel(_ label: String, start: Double, end: Double, diameter: CGFloat) -> some View {
        let letters = Array(label)
        return ZStack {
            ForEach(letters.indices, id: \.self) { index in
                let progress = Double(index) / Double(letters.count - 1)
                polarLabel(String(letters[index]), angle: start + progress * (end - start),
                           radius: diameter * 0.337, fontSize: diameter * 0.043, color: .primary)
            }
        }
    }

    private func polarLabel(_ label: String, angle: Double, radius: CGFloat, fontSize: CGFloat, color: Color) -> some View {
        let radians = angle * .pi / 180
        return Text(label)
            .font(.system(size: fontSize, weight: .black).monospacedDigit())
            .foregroundStyle(color)
            .fixedSize()
            .rotationEffect(.degrees(angle + 90))
            .offset(x: cos(radians) * radius, y: sin(radians) * radius)
    }

    private func arc(_ value: Double?, limit: Double, start: Double, sweep: Double, color: Color,
                     radius: CGFloat, width: CGFloat) -> some View {
        let span = sweep / 360
        let fraction = value.flatMap { $0.isFinite ? min(max($0 / limit, 0), 1) : nil } ?? 0
        let stroke = StrokeStyle(lineWidth: width, lineCap: .round)
        return ZStack {
            Circle().trim(from: 0, to: span).stroke(.primary.opacity(0.10), style: stroke)
            if fraction > 0 {
                Circle().trim(from: 0, to: span * fraction).stroke(color, style: stroke)
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .rotationEffect(.degrees(start))
    }

    private func number(_ value: Double?) -> String {
        value.flatMap { $0.isFinite ? $0.formatted(.number.grouping(.never).precision(.fractionLength(0))) : nil } ?? "—"
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

struct LiveLapBenchmarks: View {
    @EnvironmentObject private var model: MobileModel
    let handle: AnyView?
    let expanded: Bool

    @State private var historical: Historical?
    @State private var loading = false

    private struct Lap {
        let time: String
        let seconds: Double
        let driver: String
        let detail: String
        let team: String?

        init?(time: String?, driver: String, detail: String = "", team: String? = nil) {
            guard let time, let seconds = LiveIslandLogic.sectorSeconds(time), seconds.isFinite, seconds > 0 else {
                return nil
            }
            self.time = time
            self.seconds = seconds
            self.driver = driver
            self.detail = detail
            self.team = team
        }
    }

    private struct Historical {
        let key: String
        let weekend: Lap?
        let qualifying: Lap?
    }

    private var sessionBest: Lap? {
        model.liveSnapshot.drivers.compactMap {
            Lap(time: $0.bestLap, driver: $0.name ?? "#\($0.number)", team: $0.team)
        }.min { $0.seconds < $1.seconds }
    }

    private var archiveYear: Int? {
        guard model.series == .f1 else { return nil }
        let snapshot = model.liveSnapshot
        let date: Date
        if snapshot.sourceMode == .replay {
            guard let recordedDate = (snapshot.weather?.utc).flatMap(RFC3339.parse) else { return nil }
            date = recordedDate
        } else {
            date = model.liveScheduleForDisplay?.meeting.startDate ?? .now
        }
        return Calendar(identifier: .gregorian).component(.year, from: date)
    }

    private var archiveKey: String {
        "\(model.dataContext)|\(model.displayedLiveSessionKey ?? "")|\(model.liveMeetingName)|\(archiveYear ?? 0)"
    }

    var body: some View {
        let best = sessionBest
        let archive = historical?.key == archiveKey ? historical : nil
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: "bolt")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text("Best Lap Benchmarks").liveTabletPanelTitle()
                }
                Spacer(minLength: 4)
                handle
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            Divider()
            ScrollView {
                VStack(spacing: 6) {
                    benchmark("Session best", lap: best, featured: true)
                    benchmark("Weekend best", lap: archive?.weekend, reference: best)
                    benchmark("Previous edition · Qualifying", lap: archive?.qualifying, reference: best)
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liveLandscapePanel(WebDashboardStyle.homePanel)
        .task(id: archiveKey) { await loadArchive(key: archiveKey) }
    }

    private func benchmark(_ title: String, lap: Lap?, featured: Bool = false, reference: Lap? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            if let lap {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(lap.time)
                        .font(featured ? (expanded ? .title3.bold() : .headline.bold()) : .subheadline.weight(.semibold))
                        .foregroundStyle(featured ? Color.purple : .primary)
                    if let reference {
                        let delta = reference.seconds - lap.seconds
                        Text("\(delta, format: .number.sign(strategy: .always()).precision(.fractionLength(3)))s")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(delta < 0 ? Color.purple : .secondary)
                    }
                    Spacer(minLength: 0)
                    if featured {
                        if let team = lap.team {
                            AssetImage(name: MotorsportAssetName.name(kind: .teamLogo,
                                                                       id: LiveIslandLogic.assetSlug(team),
                                                                       season: archiveYear ?? model.season))
                                .frame(width: 14, height: 12)
                                .accessibilityHidden(true)
                        }
                        Text(MotorsportAssetName.abbreviation(lap.driver)).font(.caption.bold())
                            .accessibilityLabel(lap.driver)
                    }
                }
                if !featured {
                    Text([lap.driver, lap.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(!featured && loading ? "Loading…" : "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(!featured && loading ? "Loading benchmark" : "Benchmark unavailable")
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 10)
        .padding(.vertical, featured || expanded ? 9 : 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(featured ? Color.purple.opacity(0.10) : Color.primary.opacity(0.035), in: .rect(cornerRadius: 7))
        .accessibilityElement(children: .combine)
    }

    private func loadArchive(key: String) async {
        guard historical?.key != key, let year = archiveYear, let url = model.serverURL else { return }
        loading = true
        defer { if key == archiveKey { loading = false } }
        let client = APIClient(baseURL: url)
        let token = model.currentToken
        async let current = try? client.seasonResults(season: year, token: token)
        async let past = try? client.seasonResults(season: year - 1, token: token)
        let (currentSeason, pastSeason) = await (current, past)
        guard !Task.isCancelled, key == archiveKey else { return }

        let meetingName = archiveMeetingName(model.liveMeetingName)
        let currentMeeting = currentSeason?.data.first { archiveMeetingName($0.meeting.name) == meetingName }
        let previousMeeting = pastSeason?.data.first { candidate in
            if let circuit = currentMeeting?.meeting.circuit?.id,
               let previousCircuit = candidate.meeting.circuit?.id {
                return circuit == previousCircuit
            }
            return archiveMeetingName(candidate.meeting.name) == meetingName
        }
        let sessionType = model.liveSnapshot.sessionType ?? model.liveSessionName
        let liveStart = currentMeeting?.meeting.sessions.first {
            LiveIslandLogic.sessionTypeMatches(sessionType, $0.sessionType)
        }?.startTime
        let earlierLaps = currentMeeting?.meeting.sessions.filter { session in
            liveStart.map { session.startTime < $0 } ?? false
        }.compactMap { session in
            currentMeeting.flatMap { fastestLap($0, type: session.sessionType) }
        } ?? []
        historical = Historical(key: key, weekend: earlierLaps.min { $0.seconds < $1.seconds },
                                qualifying: previousMeeting.flatMap { fastestLap($0, type: .qualifying) })
    }

    private func archiveMeetingName(_ name: String) -> String {
        let normalized = LiveIslandLogic.assetSlug(name)
        return normalized == "sao-paulo-grand-prix" ? "brazilian-grand-prix" : normalized
    }

    private func fastestLap(_ weekend: SeasonResultWeekend, type: SessionType) -> Lap? {
        weekend.sessions[type.rawValue]?.rows.flatMap { row in
            [row.bestLap, row.q1, row.q2, row.q3].compactMap { time in
                Lap(time: time, driver: row.driverName, detail: "\(type.resultLabel), \(weekend.meeting.season)")
            }
        }.min { $0.seconds < $1.seconds }
    }
}
