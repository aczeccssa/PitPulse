import Charts
import SharedData
import SwiftUI

struct DriverAnalysisScreen: View {
    @EnvironmentObject private var model: MobileModel
    let sessionID: String
    let driverID: String
    let name: String
    @State private var analysis: SessionAnalysis?
    @State private var error: String?
    @State private var mode = 0
    @State private var selectedLap: Int?
    @State private var focusedLap: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PulseHeading(eyebrow: "Driver Analytics", title: name)
                Picker("分析图表", selection: $mode) {
                    Text("圈速").tag(0); Text("分段").tag(1); Text("遥测").tag(2); Text("轮胎").tag(3)
                }.pickerStyle(.segmented)
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                if let analysis {
                    switch mode {
                    case 0: lapChart(analysis)
                    case 1: sectorChart(analysis)
                    case 2: telemetryCharts(analysis)
                    default: stintChart(analysis)
                    }
                    ForEach(analysis.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                } else if error == nil { ProgressView("加载车手数据…") }
            }.padding(20)
        }.background(PulseStyle.background).navigationTitle("车手图表").navigationBarTitleDisplayMode(.inline)
            .refreshable { await load() }
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: mode)
            .task(id: "\(model.dataContext):\(selectedLap.map(String.init) ?? "best")") { await load() }
    }
    private func lapChart(_ analysis: SessionAnalysis) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("每圈节奏").font(.headline)
                Chart(Array(analysis.laps.enumerated()), id: \.offset) { _, lap in
                    if let number = lap.lapNumber, let duration = lap.lapDuration {
                        LineMark(x: .value("圈", number), y: .value("圈速 秒", duration)).foregroundStyle(PulseStyle.red)
                        PointMark(x: .value("圈", number), y: .value("圈速 秒", duration)).foregroundStyle(PulseStyle.red).symbolSize(14)
                    }
                    if let focusedLap { RuleMark(x: .value("选中圈", focusedLap)).foregroundStyle(.secondary.opacity(0.5)) }
                }.frame(height: 240).chartXSelection(value: $focusedLap).chartYScale(domain: .automatic(includesZero: false))
                if let focusedLap, let row = analysis.laps.first(where: { $0.lapNumber == focusedLap }) {
                    Text("L\(focusedLap) · \(row.lapDuration.map { String(format: "%.3f s", $0) } ?? "—")").font(.caption.monospacedDigit()).foregroundStyle(.red)
                } else { Text("按住图表查看单圈值；进站慢圈保留真实耗时。").font(.caption2).foregroundStyle(.secondary) }
                if analysis.laps.isEmpty { Text("暂无逐圈数据").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private func sectorChart(_ analysis: SessionAnalysis) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("分段耗时构成").font(.headline)
                Chart(Array(analysis.laps.enumerated()), id: \.offset) { _, lap in
                    if let number = lap.lapNumber {
                        ForEach(0..<3, id: \.self) { index in
                            if let value = lap.sectors[index] { BarMark(x: .value("圈", number), y: .value("秒", value)).foregroundStyle(by: .value("分段", "S\(index + 1)")) }
                        }
                    }
                }.chartForegroundStyleScale(["S1": PulseStyle.red, "S2": Color.orange, "S3": Color.purple]).frame(height: 260)
                Text("每个柱形对应一圈，颜色表示三个分段；缺失分段不补零。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func telemetryCharts(_ analysis: SessionAnalysis) -> some View {
        VStack(spacing: 20) {
            Picker("遥测圈", selection: $selectedLap) {
                Text("最快圈").tag(Int?.none)
                ForEach(analysis.laps.compactMap(\.lapNumber), id: \.self) { lap in Text("L\(lap)").tag(Int?.some(lap)) }
            }.pickerStyle(.menu)
            PulseCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("速度 · L\(analysis.selectedLap ?? selectedLap ?? 0)").font(.headline)
                    Chart(Array(analysis.carData.enumerated()), id: \.offset) { _, point in
                        if let date = point.date, let speed = point.speed { LineMark(x: .value("时间", date), y: .value("km/h", speed)).foregroundStyle(PulseStyle.red) }
                    }.frame(height: 190)
                    if analysis.carData.isEmpty { Text("此圈暂无速度遥测").font(.caption).foregroundStyle(.secondary) }
                }
            }
            PulseCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("油门与刹车").font(.headline)
                    Chart(Array(analysis.carData.enumerated()), id: \.offset) { _, point in
                        if let date = point.date {
                            if let throttle = point.throttle { LineMark(x: .value("时间", date), y: .value("%", throttle)).foregroundStyle(by: .value("踏板", "油门")) }
                            if let brake = point.brake { LineMark(x: .value("时间", date), y: .value("%", brake)).foregroundStyle(by: .value("踏板", "刹车")) }
                        }
                    }.chartForegroundStyleScale(["油门": Color.green, "刹车": Color.red]).chartYScale(domain: 0...100).frame(height: 160)
                }
            }
        }
    }
    private func stintChart(_ analysis: SessionAnalysis) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("轮胎使用区间").font(.headline)
                Chart(Array(analysis.stints.enumerated()), id: \.offset) { index, stint in
                    if let start = stint.lapStart, let end = stint.lapEnd ?? analysis.laps.compactMap(\.lapNumber).max() {
                        BarMark(xStart: .value("起始圈", start), xEnd: .value("结束圈", end), y: .value("Stint", "Stint \(stint.stintNumber ?? index + 1)"))
                            .foregroundStyle(by: .value("轮胎", stint.compound ?? "未知"))
                            .annotation(position: .overlay) { Text("\(stint.compound ?? "?") · L\(start)–\(end)").font(.system(size: 10, weight: .bold)).foregroundStyle(["MEDIUM", "HARD"].contains(stint.compound ?? "") ? Color.black : Color.white) }
                    }
                }.chartForegroundStyleScale(["SOFT": Color.red, "MEDIUM": Color.yellow, "HARD": Color.gray, "INTERMEDIATE": Color.green, "WET": Color.blue, "未知": Color.secondary]).frame(height: max(150, CGFloat(analysis.stints.count) * 42))
                if analysis.stints.isEmpty { Text("暂无轮胎使用记录").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private func load() async {
        guard let url = model.serverURL else { error = "服务器地址无效"; return }
        error = nil
        do {
            for attempt in 0..<10 {
                let response = try await APIClient(baseURL: url).sessionAnalysis(sessionId: sessionID, driverId: driverID, lap: selectedLap, token: model.currentToken)
                try Task.checkCancellation()
                let pending = response.meta.analysisStatus == "loading" || response.meta.analysisStatus == "refreshing"
                if pending {
                    if attempt == 9 { error = "历史数据仍在后台同步，请下拉刷新。"; return }
                    try await Task.sleep(for: .seconds(2))
                    continue
                }
                analysis = response.data
                if response.meta.analysisStatus == "failed" { error = response.meta.analysisError ?? "当前场次的数据源暂不可用，请下拉重试。" }
                return
            }
        } catch { if !Task.isCancelled { self.error = MobileModel.message(for: error) } }
    }
}
