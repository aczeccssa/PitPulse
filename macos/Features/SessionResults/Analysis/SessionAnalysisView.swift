import AppKit
import Charts
import SwiftUI
import SharedData

struct SessionAnalysisView: View {
    @ObservedObject var model: AppModel
    let result: SessionResult
    let season: Int
    @State var response: APIEnvelope<SessionAnalysis>?
    @State var error: String?
    @State var loading = true
    @State var selectedLap = 0
    @State var reload = 0
    @State var tab = 0
    @State var metric = "速度"
    var data: SessionAnalysis? { response?.data }
    var laps: [AnalysisLap] { (data?.laps ?? []).sorted { ($0.lapNumber ?? 0) < ($1.lapNumber ?? 0) } }
    var timedLaps: [AnalysisLap] { laps.filter { ($0.lapDuration ?? 0) > 0 && $0.isPitOutLap != true } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if loading { ProgressView().controlSize(.small).help("读取赛后分析").accessibilityLabel("读取赛后分析") }
            if let error {
                HStack {
                    Text(error).font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button { reload += 1 } label: { Image(systemName: "arrow.clockwise") }
                        .help("重试分析").accessibilityLabel("重试分析")
                }
            }
            if let data, !loading || data.hasData {
                LiquidSegmented(
                    items: [
                        .init(value: 0, title: "圈速"),
                        .init(value: 1, title: "赛道"),
                        .init(value: 2, title: "策略"),
                        .init(value: 3, title: "赛事"),
                    ],
                    selection: $tab
                )
                switch tab {
                case 0: timing
                case 1: track(data)
                case 2: strategy(data)
                default: events(data)
                }
                if !data.warnings.isEmpty {
                    DisclosureGroup("部分分析数据未提供") {
                        ForEach(Array(data.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }.font(.caption)
                }
            }
        }
        .task(id: "\(result.sessionId)-\(result.driverId)-\(selectedLap)-\(reload)") {
            loading = true; error = nil
            if let cached = await model.cachedAnalysis(key: "analysis-\(result.sessionId)-\(result.driverId)-\(selectedLap)", season: season, as: SessionAnalysis.self) {
                response = cached
            }
            do {
                for _ in 0..<60 {
                    let value = try await model.sessionAnalysis(sessionID: result.sessionId, driverID: result.driverId,
                        season: season, lap: selectedLap == 0 ? nil : selectedLap)
                    try Task.checkCancellation()
                    error = value.meta.analysisError
                    if let old = response, old.data.hasData,
                        value.meta.analysisStatus == "failed" || (value.meta.analysisIsLoading && !value.data.hasData) {
                        var meta = old.meta; meta.stale = true
                        response = APIEnvelope(data: old.data, meta: meta)
                    } else { response = value }
                    if !value.meta.analysisIsLoading {
                        loading = false; return
                    }
                    try await Task.sleep(for: .seconds(2))
                }
                error = "服务器仍在后台准备，已有内容保留，可稍后重试。"
            } catch is CancellationError { return }
            catch {
                if let apiError = error as? APIClientError, apiError == .unauthorized { response = nil }
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    var timing: some View {
        VStack(spacing: 14) {
            AnalysisCard(title: "圈速概览") {
                LabeledContent("最佳圈", value: AnalysisMath.duration(timedLaps.compactMap(\.lapDuration).min()))
                LabeledContent("平均圈速", value: AnalysisMath.duration(timedLaps.isEmpty ? nil : timedLaps.compactMap(\.lapDuration).reduce(0, +) / Double(timedLaps.count)))
                LabeledContent("理论最佳圈", value: AnalysisMath.duration(theoreticalBest))
                LabeledContent("有效计时", value: "\(timedLaps.count) / \(laps.count) 圈")
                Text("统计排除出站圈；安全车、雨况等慢圈保留。热力表按各赛段自身范围着色，紫色为该赛段最佳。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            AnalysisCard(title: "逐圈走势 · 秒") {
                if timedLaps.isEmpty { missing("圈速") } else {
                    Chart(Array(timedLaps.enumerated()), id: \.offset) { _, lap in
                        if let number = lap.lapNumber, let duration = lap.lapDuration {
                            LineMark(x: .value("圈", number), y: .value("秒", duration))
                            PointMark(x: .value("圈", number), y: .value("秒", duration))
                        }
                    }.frame(height: 170).chartYScale(domain: .automatic(includesZero: false))
                        .accessibilityLabel("车手逐圈圈速，数值在下方赛段表")
                }
            }
            AnalysisCard(title: "圈速与 S1 / S2 / S3 热力表") {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow { Text("圈"); Text("圈速"); Text("S1"); Text("S2"); Text("S3") }.font(.caption.bold())
                    ForEach(Array(laps.enumerated()), id: \.offset) { _, lap in
                        GridRow {
                            Text(lap.lapNumber.map(String.init) ?? "—")
                            Text(AnalysisMath.duration(lap.lapDuration))
                            ForEach(0..<3) { sector in
                                Text(lap.sectors[sector].map { String(format: "%.3f", $0) } ?? "—")
                                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                                    .background(sectorColor(lap.sectors[sector], sector: sector), in: RoundedRectangle(cornerRadius: 4))
                                    .accessibilityLabel("第 \(lap.lapNumber ?? 0) 圈 S\(sector + 1)，\(lap.sectors[sector].map { String(format: "%.3f 秒", $0) } ?? "未提供")")
                            }
                        }
                    }
                }.font(.caption2.monospacedDigit())
                LabeledContent("最高测速点", value: laps.compactMap(\.stSpeed).max().map { "\($0.formatted()) km/h" } ?? "—")
                Text("出站圈与缺失赛段保留原值，不补零。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    var theoreticalBest: Double? {
        let best = (0..<3).compactMap { sector in timedLaps.compactMap { $0.sectors[sector] }.filter { $0 > 0 }.min() }
        return best.count == 3 ? best.reduce(0, +) : nil
    }

    func sectorColor(_ value: Double?, sector: Int) -> Color {
        guard let value else { return .clear }
        let values = laps.compactMap { $0.sectors[sector] }.filter { $0 > 0 }
        guard let min = values.min(), let max = values.max() else { return .clear }
        if value == min { return .purple.opacity(0.4) }
        let fraction = (value - min) / Swift.max(max - min, 0.001)
        return fraction < 0.4 ? .green.opacity(0.2) : fraction < 0.7 ? .yellow.opacity(0.22) : .orange.opacity(0.3)
    }
}
