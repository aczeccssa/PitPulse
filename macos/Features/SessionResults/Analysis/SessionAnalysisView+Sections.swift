import AppKit
import Charts
import SwiftUI
import SharedData

extension SessionAnalysisView {

    func strategy(_ data: SessionAnalysis) -> some View {
        VStack(spacing: 14) {
            AnalysisCard(title: "轮胎与 Stint") {
                if data.stints.isEmpty { missing("轮胎") }
                ForEach(Array(data.stints.enumerated()), id: \.offset) { _, stint in
                    HStack(spacing: 10) {
                        Circle().fill(compoundColor(stint.compound)).frame(width: 16, height: 16)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stint.compound ?? "轮胎未知").font(.callout.bold())
                            Text("L\(stint.lapStart.map(String.init) ?? "—")–\(stint.lapEnd.map(String.init) ?? "—") · 起始胎龄 \(stint.tyreAgeAtStart.map(String.init) ?? "—") 圈")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityElement(children: .combine)
                }
            }
            AnalysisCard(title: "进站 · \(data.pit.count) 次记录") {
                if data.pit.isEmpty { missing("进站") }
                ForEach(Array(data.pit.enumerated()), id: \.offset) { _, pit in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("L\(pit.lapNumber.map(String.init) ?? "—") · \(pit.date?.formatted(date: .omitted, time: .standard) ?? "—")").font(.callout.bold())
                        LabeledContent("进站通道", value: seconds(pit.laneDuration ?? pit.pitDuration))
                        LabeledContent("静止换胎", value: seconds(pit.stopDuration))
                    }
                    Divider()
                }
            }
            AnalysisCard(title: "名次走势") {
                if data.positions.isEmpty { missing("名次变化") } else {
                    Chart(Array(data.positions.enumerated()), id: \.offset) { _, row in
                        if let date = row.date, let position = row.position {
                            LineMark(x: .value("时间", date), y: .value("名次", -position))
                                .interpolationMethod(.stepEnd)
                        }
                    }.frame(height: 170).chartYScale(domain: -22 ... -1)
                        .chartYAxis { AxisMarks { value in AxisValueLabel { if let rank = value.as(Int.self) { Text(String(-rank)) } }; AxisGridLine() } }
                }
                let start = data.grid.first { $0.driverNumber == data.driver?.driverNumber }?.position
                LabeledContent("发车 / 完赛", value: "\(start.map(String.init) ?? "—") / \(result.position.map(String.init) ?? "—")")
                if let start, start > 0, let finish = result.position { LabeledContent("名次变化", value: String(format: "%+d", start - finish)) }
            }
        }
    }
    func events(_ data: SessionAnalysis) -> some View {
        VStack(spacing: 14) {
            AnalysisCard(title: "赛道与天气") {
                if data.weather.isEmpty { missing("天气") } else {
                    Chart(Array(data.weather.enumerated()), id: \.offset) { _, row in
                        if let date = row.date {
                            if let value = row.trackTemperature { LineMark(x: .value("时间", date), y: .value("°C", value)).foregroundStyle(by: .value("温度", "赛道")) }
                            if let value = row.airTemperature { LineMark(x: .value("时间", date), y: .value("°C", value)).foregroundStyle(by: .value("温度", "空气")) }
                        }
                    }.frame(height: 150)
                    if let weather = data.weather.last {
                        LabeledContent("湿度", value: weather.humidity.map { "\($0.formatted())%" } ?? "—")
                        LabeledContent("降雨", value: weather.rainfall.map { $0 > 0 ? "有雨" : "无雨" } ?? "—")
                        LabeledContent("风速 / 风向", value: "\(weather.windSpeed?.formatted() ?? "—") m/s · \(weather.windDirection?.formatted() ?? "—")°")
                        LabeledContent("气压", value: weather.pressure.map { "\($0.formatted()) mbar" } ?? "—")
                    }
                }
            }
            AnalysisCard(title: "赛事控制") {
                let rows = data.raceControl.filter { $0.driverNumber == nil || $0.driverNumber == data.driver?.driverNumber }
                if rows.isEmpty { missing("全场或该车手的赛事事件") }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, event in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "flag.fill").foregroundStyle(eventColor(event.flag))
                            .accessibilityLabel(event.flag ?? event.category ?? "赛事事件")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.message ?? "—").font(.caption)
                            Text("\(event.date?.formatted(date: .omitted, time: .shortened) ?? "—") · L\(event.lapNumber.map(String.init) ?? "—")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                }
            }
        }
    }
    func missing(_ field: String) -> some View { Text("\(field)未提供").font(.caption).foregroundStyle(.secondary) }
    func seconds(_ value: Double?) -> String { value.map { String(format: "%.3f 秒", $0) } ?? "未提供" }
    func compoundColor(_ value: String?) -> Color {
        switch value?.uppercased() { case "SOFT": .red; case "MEDIUM": .yellow; case "HARD": .white; case "INTERMEDIATE": .green; case "WET": .blue; default: .gray }
    }
    func eventColor(_ value: String?) -> Color {
        switch value?.uppercased() { case "RED": .red; case "YELLOW", "DOUBLE YELLOW": .yellow; case "GREEN": .green; case "BLUE": .blue; default: .secondary }
    }
}
