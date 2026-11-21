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
        VStack(spacing: isTablet ? 6 : compact ? 8 : 20) {
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
