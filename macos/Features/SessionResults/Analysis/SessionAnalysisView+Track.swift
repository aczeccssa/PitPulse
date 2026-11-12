import AppKit
import Charts
import SwiftUI
import SharedData

extension SessionAnalysisView {
    func track(_ data: SessionAnalysis) -> some View {
        VStack(spacing: 14) {
            AnalysisCard(title: "赛道 · 第 \(data.selectedLap.map(String.init) ?? "—") 圈") {
                Picker("遥测圈", selection: $selectedLap) {
                    Text("最佳完整圈").tag(0)
                    ForEach(Array(timedLaps.enumerated()), id: \.offset) { _, lap in
                        if let number = lap.lapNumber, lap.dateStart != nil, (lap.lapDuration ?? 600) < 600 {
                            Text("L\(number) · \(AnalysisMath.duration(lap.lapDuration))").tag(number)
                        }
                    }
                }
                LiquidSegmented(
                    items: [
                        .init(value: "速度", title: "速度"),
                        .init(value: "油门", title: "油门"),
                        .init(value: "刹车", title: "刹车"),
                    ],
                    selection: $metric,
                    compact: true
                )
                if data.location.count > 1 {
                    TrackHeatmap(location: data.location, telemetry: data.carData, metric: metric)
                        .frame(height: 230)
                    LabeledContent("颜色范围", value: metric == "速度"
                        ? "\(data.carData.compactMap(\.speed).min()?.formatted() ?? "—")–\(data.carData.compactMap(\.speed).max()?.formatted() ?? "—") km/h"
                        : "0–100%")
                    Text("真实行车轨迹；蓝色低、红色高，灰色为无法对齐的遥测。刹车只表示开/关。")
                        .font(.caption2).foregroundStyle(.secondary)
                } else { missing("该圈赛道坐标") }
                Text("\(data.location.count) 个坐标 · \(data.carData.count) 个遥测采样")
                    .font(.caption).foregroundStyle(.secondary)
            }
            AnalysisCard(title: "遥测 · \(metric == "速度" ? "km/h" : "%")") {
                if data.carData.isEmpty { missing("该圈遥测") } else {
                    telemetryChart(data, field: metric)
                    let speeds = data.carData.compactMap(\.speed)
                    LabeledContent("最高速度", value: speeds.max().map { "\($0.formatted()) km/h" } ?? "—")
                    LabeledContent("平均采样速度", value: speeds.isEmpty ? "—" : "\((speeds.reduce(0, +) / Double(speeds.count)).formatted(.number.precision(.fractionLength(1)))) km/h")
                    LabeledContent("最高转速", value: data.carData.compactMap(\.rpm).max().map { "\($0.formatted()) rpm" } ?? "—")
                    LabeledContent("挡位范围", value: gearRange(data))
                    Text("DRS：10/12/14 为开启，8 为可用；其他代码保留原值。")
                        .font(.caption2).foregroundStyle(.secondary)
                    LabeledContent("DRS 开启采样", value: "\(data.carData.filter { [10, 12, 14].contains($0.drs ?? -1) }.count)")
                    DisclosureGroup("采样明细") {
                        ForEach(Array(data.carData.enumerated()), id: \.offset) { _, row in
                            HStack {
                                Text(row.date?.formatted(date: .omitted, time: .standard) ?? "—")
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(row.speed?.formatted() ?? "—") km/h · 油门 \(row.throttle?.formatted() ?? "—")% · 刹车 \(row.brake?.formatted() ?? "—")%")
                                    Text("\(row.rpm?.formatted() ?? "—") rpm · G\(row.nGear.map(String.init) ?? "—") · DRS \(row.drs.map(String.init) ?? "—")")
                                }
                            }.font(.caption2.monospacedDigit())
                        }
                    }.font(.caption)
                }
            }
        }
    }
    func gearRange(_ data: SessionAnalysis) -> String {
        let values = data.carData.compactMap(\.nGear)
        guard let low = values.min(), let high = values.max() else { return "—" }
        return "\(low)–\(high)"
    }
    func telemetryChart(_ data: SessionAnalysis, field: String) -> some View {
        Chart(Array(data.carData.enumerated()), id: \.offset) { _, row in
            if let date = row.date, let value = field == "速度" ? row.speed : field == "油门" ? row.throttle : row.brake {
                LineMark(x: .value("时间", date), y: .value(field, value))
            }
        }.frame(height: 160).accessibilityLabel("该圈\(field)随时间变化")
    }
}
