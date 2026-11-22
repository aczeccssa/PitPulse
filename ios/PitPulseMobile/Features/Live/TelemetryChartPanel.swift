import Charts
import SharedData
import SwiftUI

struct TelemetryChartPanel: View {
    let samples: [LiveTelemetry]
    let driver: LiveDriver
    var pedalHeight: CGFloat? = nil

    var isTablet = false

    private var compact: Bool { isTablet || pedalHeight != nil }
    private struct Point: Identifiable {
        let id: String
        let date: Date
        let speed: Double?
        let throttle: Double?
        let brake: Double?
    }
    private var points: [Point] {
        samples.compactMap { sample in
            guard let date = RFC3339.parse(sample.utc) else { return nil }
            return Point(id: sample.utc, date: date, speed: sample.speed, throttle: sample.throttle, brake: sample.brake)
        }
    }
    var body: some View {
        let points = self.points
        let latest = points.last?.date ?? .now
        if isTablet {
            tabletHistory(points, latest: latest)
        } else {
            phoneHistory(points, latest: latest)
        }
    }

    private func tabletHistory(_ points: [Point], latest: Date) -> some View {
        let maximum = max(350, ceil((points.compactMap(\.speed).max() ?? 0) / 50) * 50)
        let domain = timeDomain(for: points, endingAt: latest)
        return GeometryReader { geometry in
            let pedalHeight = max(40, geometry.size.height * 0.20)
            VStack(alignment: .leading, spacing: 8) {
                historyLane("Speed", scale: "0–\(Int(maximum)) km/h", points: points, latest: latest,
                            domain: domain, maximum: maximum, channel: \.speed, tint: .cyan)
                historyLane("Throttle", scale: "0–100%", points: points, latest: latest,
                            domain: domain, maximum: 100, channel: \.throttle, tint: .green)
                    .frame(height: pedalHeight)
                historyLane("Brake", scale: "0–100%", points: points, latest: latest,
                            domain: domain, maximum: 100, channel: \.brake, tint: PulseStyle.red,
                            showsTime: true)
                    .frame(height: pedalHeight + 16)
            }
        }
    }

    private func historyLane(_ title: String, scale: String, points: [Point], latest: Date,
                             domain: ClosedRange<Double>, maximum: Double, channel: KeyPath<Point, Double?>,
                             tint: Color, showsTime: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption.bold())
                Spacer()
                Text(scale).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            if points.contains(where: { $0[keyPath: channel] != nil }) {
                Chart(points) { point in
                    if let value = point[keyPath: channel] {
                        let x = PlottableValue.value("Seconds from latest sample", point.date.timeIntervalSince(latest))
                        AreaMark(x: x, yStart: .value("Zero", 0), yEnd: .value(title, value))
                            .foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.06)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: x, y: .value(title, value))
                            .foregroundStyle(tint)
                            .lineStyle(StrokeStyle(lineWidth: 1.6))
                    }
                }
                .chartYScale(domain: 0...maximum)
                .chartXScale(domain: domain)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { tick in
                        AxisGridLine()
                        if showsTime, let seconds = tick.as(Double.self) {
                            AxisValueLabel { Text("\(Int(seconds))s").font(.caption2.monospacedDigit()) }
                        }
                    }
                }
                .chartPlotStyle { $0.background(.primary.opacity(0.035)).clipped() }
            } else {
                Text("Waiting for data").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func phoneHistory(_ points: [Point], latest: Date) -> some View {
        VStack(spacing: compact ? 8 : 20) {
            chartCard {
                VStack(alignment: .leading, spacing: compact ? 4 : 14) {
                    if isTablet {
                        Text("Speed (km/h)").font(.caption.bold())
                    } else {
                        HStack(alignment: .center) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                PulseNumber(driver.telemetry?.speed.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                                    .font(.system(size: compact ? 25 : 46, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                Text("km/h").font(.caption).foregroundStyle(.secondary)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            Spacer()
                            VStack(alignment: .trailing, spacing: compact ? 2 : 5) {
                                PulseNumber(driver.telemetry?.gear.map { "GEAR \($0.formatted(.number.precision(.fractionLength(0))))" } ?? "GEAR —").font(.caption.bold())
                                PulseNumber(driver.telemetry?.rpm.map { "\($0.formatted(.number.precision(.fractionLength(0)))) RPM" } ?? "RPM —").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if points.count > 1 {
                        Chart(points) { point in
                            if let speed = point.speed { LineMark(x: .value("Seconds from latest sample", point.date.timeIntervalSince(latest)), y: .value("Speed (km/h)", speed)).foregroundStyle(PulseStyle.red).lineStyle(StrokeStyle(lineWidth: 2.5)) }
                        }.pulseChart()
                        .chartXAxis { if !isTablet { secondsAxis } }
                        .chartXScale(domain: timeDomain(for: points, endingAt: latest))
                        .chartYScale(domain: 0...max(350, points.compactMap(\.speed).max() ?? 350))
                        .chartYAxis { AxisMarks(values: isTablet ? .automatic(desiredCount: 3) : .automatic) }
                        .frame(height: compact ? nil : 160)
                        .frame(maxHeight: compact ? .infinity : nil)
                    } else { Text("Waiting for speed data").font(.caption).foregroundStyle(.secondary).frame(height: compact ? nil : 90)
                            .frame(maxHeight: compact ? .infinity : nil) }
                }
            }
            chartCard {
                VStack(alignment: .leading, spacing: compact ? 2 : 12) {
                    HStack(spacing: 6) {
                        Text("Throttle").foregroundStyle(isTablet ? Color.green : .primary)
                        Text("/")
                        Text("Brake").foregroundStyle(isTablet ? PulseStyle.red : .primary)
                    }
                    .font(isTablet ? .caption.bold() : compact ? .caption2.bold() : .headline)
                    .accessibilityElement(children: .combine)
                    if points.count > 1 {
                        Chart(points) { point in
                            if let throttle = point.throttle { LineMark(x: .value("Seconds from latest sample", point.date.timeIntervalSince(latest)), y: .value("Pedal (%)", throttle)).foregroundStyle(by: .value("Pedal", "Throttle")) }
                            if let brake = point.brake { LineMark(x: .value("Seconds from latest sample", point.date.timeIntervalSince(latest)), y: .value("Pedal (%)", brake)).foregroundStyle(by: .value("Pedal", "Brake")) }
                        }.pulseChart()
                        .chartXAxis { if isTablet || !compact { secondsAxis } }
                        .chartYAxis { if isTablet || !compact { AxisMarks(values: isTablet ? .automatic(desiredCount: 3) : .automatic) } }
                        .chartLegend(compact ? .hidden : .automatic)
                        .chartXScale(domain: timeDomain(for: points, endingAt: latest))
                        .chartForegroundStyleScale(["Throttle": Color.green, "Brake": Color.red])
                        .chartYScale(domain: 0...100)
                        .frame(height: compact ? nil : 140)
                        .frame(maxHeight: compact ? .infinity : nil)
                    } else {
                        Text("Waiting for throttle and brake data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxHeight: isTablet ? .infinity : nil)
                    }
                }
            }
            .frame(height: pedalHeight)
        }
    }

    @ViewBuilder
    private func chartCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let card = content()
            .padding(isTablet ? 0 : compact ? 8 : 16)
            .frame(maxWidth: .infinity, maxHeight: compact ? .infinity : nil, alignment: .topLeading)
        if isTablet {
            card
        } else if compact {
            card.liveLandscapePanel(PulseStyle.surface)
        } else {
            card.dashboardPanel(PulseStyle.surface, line: .clear)
        }
    }

    private func timeDomain(for points: [Point], endingAt latest: Date) -> ClosedRange<Double> {
        min(-1, points.first?.date.timeIntervalSince(latest) ?? 0)...0
    }

    private var secondsAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { value in
            AxisGridLine()
            AxisValueLabel {
                if let seconds = value.as(Double.self) {
                    PulseNumber(seconds.formatted(.number.precision(.fractionLength(0))) + "s")
                }
            }
        }
    }
}
