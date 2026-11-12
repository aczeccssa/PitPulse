import Charts
import SharedData
import SwiftUI

struct TelemetryChartPanel: View {
    let samples: [LiveTelemetry]
    let driver: LiveDriver
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
        VStack(spacing: 20) {
            PulseCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(driver.telemetry?.speed.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—").font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                        Text("km/h").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(driver.telemetry?.gear.map { "GEAR \($0.formatted(.number.precision(.fractionLength(0))))" } ?? "GEAR —").font(.caption.bold())
                            Text(driver.telemetry?.rpm.map { "\($0.formatted(.number.precision(.fractionLength(0)))) RPM" } ?? "RPM —").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if points.count > 1 {
                        Chart(points) { point in
                            if let speed = point.speed { LineMark(x: .value("时间", point.date), y: .value("速度 km/h", speed)).foregroundStyle(PulseStyle.red).lineStyle(StrokeStyle(lineWidth: 2.5)) }
                        }.frame(height: 160).chartYScale(domain: 0...max(350, points.compactMap(\.speed).max() ?? 350))
                    } else { Text("等待速度样本，收到后自动绘图。").font(.caption).foregroundStyle(.secondary).frame(height: 90) }
                    Text("最近 \(points.count) 个真实遥测样本 · 随数据流更新").font(.caption2).foregroundStyle(.secondary)
                }
            }
            PulseCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("油门 / 刹车").font(.headline)
                    if points.count > 1 {
                        Chart(points) { point in
                            if let throttle = point.throttle { LineMark(x: .value("时间", point.date), y: .value("踏板 %", throttle)).foregroundStyle(by: .value("踏板", "油门")) }
                            if let brake = point.brake { LineMark(x: .value("时间", point.date), y: .value("踏板 %", brake)).foregroundStyle(by: .value("踏板", "刹车")) }
                        }.chartForegroundStyleScale(["油门": Color.green, "刹车": Color.red]).chartYScale(domain: 0...100).frame(height: 140)
                    } else { Text("当前数据源尚未提供足够的踏板样本。").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}
