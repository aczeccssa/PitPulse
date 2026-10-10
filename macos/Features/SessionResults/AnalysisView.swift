import SwiftUI
import Charts

struct AnalysisCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SessionAnalysisView: View {
    @ObservedObject var model: AppModel
    let result: SessionResult
    let season: Int
    @State private var response: APIEnvelope<SessionAnalysis>?
    @State private var error: String?
    @State private var loading = true
    @State private var selectedLap = 0
    @State private var reload = 0
    @State private var tab = 0
    @State private var metric = "速度"
    private var data: SessionAnalysis? { response?.data }
    private var laps: [AnalysisLap] { (data?.laps ?? []).sorted { ($0.lapNumber ?? 0) < ($1.lapNumber ?? 0) } }
    private var timedLaps: [AnalysisLap] { laps.filter { ($0.lapDuration ?? 0) > 0 && $0.isPitOutLap != true } }

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
                Picker("分析内容", selection: $tab) {
                    Text("圈速").tag(0); Text("赛道").tag(1); Text("策略").tag(2); Text("赛事").tag(3)
                }.pickerStyle(.segmented)
                switch tab {
                case 0: timing
                case 1: track(data)
                case 2: strategy(data)
                default: events(data)
                }
                if let meta = response?.meta { DataProvenance(meta: meta) }
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

    private var timing: some View {
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

    private var theoreticalBest: Double? {
        let best = (0..<3).compactMap { sector in timedLaps.compactMap { $0.sectors[sector] }.filter { $0 > 0 }.min() }
        return best.count == 3 ? best.reduce(0, +) : nil
    }

    private func sectorColor(_ value: Double?, sector: Int) -> Color {
        guard let value else { return .clear }
        let values = laps.compactMap { $0.sectors[sector] }.filter { $0 > 0 }
        guard let min = values.min(), let max = values.max() else { return .clear }
        if value == min { return .purple.opacity(0.4) }
        let fraction = (value - min) / Swift.max(max - min, 0.001)
        return fraction < 0.4 ? .green.opacity(0.2) : fraction < 0.7 ? .yellow.opacity(0.22) : .orange.opacity(0.3)
    }

    private func track(_ data: SessionAnalysis) -> some View {
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
                Picker("赛道颜色", selection: $metric) {
                    Text("速度").tag("速度"); Text("油门").tag("油门"); Text("刹车").tag("刹车")
                }.pickerStyle(.segmented)
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
    private func gearRange(_ data: SessionAnalysis) -> String {
        let values = data.carData.compactMap(\.nGear)
        guard let low = values.min(), let high = values.max() else { return "—" }
        return "\(low)–\(high)"
    }
    private func telemetryChart(_ data: SessionAnalysis, field: String) -> some View {
        Chart(Array(data.carData.enumerated()), id: \.offset) { _, row in
            if let date = row.date, let value = field == "速度" ? row.speed : field == "油门" ? row.throttle : row.brake {
                LineMark(x: .value("时间", date), y: .value(field, value))
            }
        }.frame(height: 160).accessibilityLabel("该圈\(field)随时间变化")
    }

    private func strategy(_ data: SessionAnalysis) -> some View {
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
    private func events(_ data: SessionAnalysis) -> some View {
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
    private func missing(_ field: String) -> some View { Text("\(field)未提供").font(.caption).foregroundStyle(.secondary) }
    private func seconds(_ value: Double?) -> String { value.map { String(format: "%.3f 秒", $0) } ?? "未提供" }
    private func compoundColor(_ value: String?) -> Color {
        switch value?.uppercased() { case "SOFT": .red; case "MEDIUM": .yellow; case "HARD": .white; case "INTERMEDIATE": .green; case "WET": .blue; default: .gray }
    }
    private func eventColor(_ value: String?) -> Color {
        switch value?.uppercased() { case "RED": .red; case "YELLOW", "DOUBLE YELLOW": .yellow; case "GREEN": .green; case "BLUE": .blue; default: .secondary }
    }
}

private struct TrackHeatmap: View {
    let location: [AnalysisLocation]
    let telemetry: [AnalysisTelemetry]
    let metric: String
    var body: some View {
        let rows = location.filter { $0.x != nil && $0.y != nil }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        let values = rows.map { row -> Double? in
            guard let car = AnalysisMath.telemetry(at: row.date, in: telemetry) else { return nil }
            return metric == "速度" ? car.speed : metric == "油门" ? car.throttle : car.brake
        }
        Canvas { context, size in
            guard let minX = rows.compactMap(\.x).min(), let maxX = rows.compactMap(\.x).max(),
                let minY = rows.compactMap(\.y).min(), let maxY = rows.compactMap(\.y).max(), rows.count > 1 else { return }
            let scale = min((size.width - 24) / max(maxX - minX, 1), (size.height - 24) / max(maxY - minY, 1))
            let left = (size.width - (maxX - minX) * scale) / 2
            let top = (size.height - (maxY - minY) * scale) / 2
            let low = metric == "速度" ? values.compactMap { $0 }.min() ?? 0 : 0
            let high = metric == "速度" ? values.compactMap { $0 }.max() ?? 1 : 100
            for index in 1..<rows.count {
                guard let aDate = rows[index - 1].date, let bDate = rows[index].date,
                    bDate.timeIntervalSince(aDate) <= 2 else { continue }
                let a = CGPoint(x: left + (rows[index - 1].x! - minX) * scale, y: size.height - top - (rows[index - 1].y! - minY) * scale)
                let b = CGPoint(x: left + (rows[index].x! - minX) * scale, y: size.height - top - (rows[index].y! - minY) * scale)
                guard hypot(a.x - b.x, a.y - b.y) < size.width / 3 else { continue }
                var path = Path(); path.move(to: a); path.addLine(to: b)
                let color = values[index].map { Color(hue: 0.66 * (1 - min(max(($0 - low) / max(high - low, 1), 0), 1)), saturation: 0.85, brightness: 0.95) } ?? Color.gray
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
        }
        .accessibilityLabel("真实赛道行车轨迹，\(metric)热力图，\(rows.count)个坐标，\(values.compactMap { $0 }.count)个已对齐采样")
    }
}

struct SeasonAnalysisView: View {
    @ObservedObject var model: AppModel
    let kind: String
    let id: String
    let season: Int
    let officialPoints: Double
    @State private var response: APIEnvelope<SeasonAnalysis>?
    @State private var error: String?
    @State private var loading = true
    @State private var reload = 0
    private var rounds: [AnalysisRound] { response?.data.rounds ?? [] }
    private var cumulative: [(index: Int, points: Double)] {
        var sum = 0.0
        return rounds.enumerated().compactMap { index, round in
            guard let points = round.points else { return nil }
            sum += points
            return (index, sum)
        }
    }
    private var contributions: [(name: String, points: Double)] {
        var sums: [String: Double] = [:]
        for entry in rounds.flatMap(\.entries) {
            if let name = entry.driverName, let points = entry.points { sums[name, default: 0] += points }
        }
        return sums.map { ($0.key, $0.value) }.sorted { $0.points > $1.points }
    }
    private func rankColor(_ rank: Int?) -> Color {
        guard let rank, rank > 0 else { return .gray.opacity(0.15) }
        return Color(hue: 0.34 * (1 - Double(min(rank, 22) - 1) / 21), saturation: 0.7, brightness: 0.85).opacity(0.3)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if loading { ProgressView().controlSize(.small).help("读取积分分析").accessibilityLabel("读取积分分析") }
            if let error {
                HStack { Text(error).font(.caption).foregroundStyle(.orange); Spacer(); Button { reload += 1 } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("重试积分分析") }
            }
            if response != nil && (!loading || !rounds.isEmpty) {
                AnalysisCard(title: "赛季概览") {
                    LabeledContent("已提供场次", value: "\(rounds.count)")
                    LabeledContent("明细积分 / 积分榜", value: "\(cumulative.last?.points.formatted() ?? "—") / \(officialPoints.formatted())")
                    LabeledContent("领奖台记录", value: "\(rounds.flatMap(\.entries).filter { (1...3).contains($0.position ?? 0) }.count)")
                    Text("Sprint 与正赛分别统计；累计仅包含已提供的场次，可能与最新积分榜不同。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if rounds.isEmpty { Text("逐站明细未提供").font(.caption).foregroundStyle(.secondary) }
                else {
                    AnalysisCard(title: "逐站积分") {
                        Chart(Array(rounds.enumerated()), id: \.offset) { index, round in
                            if let points = round.points {
                                BarMark(x: .value("场次", index + 1), y: .value("积分", points))
                                    .foregroundStyle(by: .value("类型", round.sessionType ?? "—"))
                            }
                        }.frame(height: 170).accessibilityLabel("逐站积分，场次对应下方明细")
                    }
                    AnalysisCard(title: "累计积分走势 · 已提供场次") {
                        Chart(cumulative, id: \.index) { row in
                            LineMark(x: .value("场次", row.index + 1), y: .value("累计积分", row.points))
                            PointMark(x: .value("场次", row.index + 1), y: .value("累计积分", row.points))
                        }.frame(height: 170)
                    }
                    AnalysisCard(title: "完赛名次分布") {
                        let positions = Dictionary(grouping: rounds.flatMap(\.entries).compactMap(\.position), by: { $0 })
                        Chart(positions.keys.sorted(), id: \.self) { position in
                            BarMark(x: .value("名次", position), y: .value("次数", positions[position]?.count ?? 0))
                        }.frame(height: 140)
                    }
                    AnalysisCard(title: kind == "constructors" ? "车手积分贡献" : "积分榜对比") {
                        if kind == "constructors" {
                            Chart(contributions, id: \.name) { row in BarMark(x: .value("积分", row.points), y: .value("车手", row.name)) }.frame(height: max(90, Double(contributions.count) * 30))
                            Divider()
                            Text("车队积分榜对比").font(.caption.bold())
                            Chart(model.constructorStandings) { row in
                                BarMark(x: .value("积分", row.points), y: .value("车队", row.constructorName))
                                    .foregroundStyle(row.constructorId == id ? Color.accentColor : Color.gray.opacity(0.5))
                            }.frame(height: max(120, Double(model.constructorStandings.count) * 26))
                        } else {
                            Chart(model.driverStandings) { row in
                                BarMark(x: .value("积分", row.points), y: .value("车手", row.driverName))
                                    .foregroundStyle(row.driverId == id ? Color.accentColor : Color.gray.opacity(0.5))
                            }.frame(height: max(120, Double(model.driverStandings.count) * 24))
                            if let leader = model.driverStandings.min(by: { $0.position < $1.position }) {
                                LabeledContent("距榜首", value: "\(max(0, leader.points - officialPoints).formatted()) 分")
                            }
                        }
                    }
                    AnalysisCard(title: "逐站名次热力图") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 8) {
                            ForEach(Array(rounds.enumerated()), id: \.offset) { _, round in
                                VStack(spacing: 5) {
                                    Text("R\(round.round.map(String.init) ?? "—") · \(round.sessionType == "Sprint" ? "S" : "R")").font(.caption2.bold())
                                    ForEach(Array(round.entries.enumerated()), id: \.offset) { _, entry in
                                        Text(entry.position.map { "P\($0)" } ?? "—")
                                            .font(.caption.monospacedDigit()).frame(maxWidth: .infinity).padding(.vertical, 6)
                                            .background(rankColor(entry.position), in: RoundedRectangle(cornerRadius: 4))
                                            .accessibilityLabel("\(round.raceName ?? "—") \(round.sessionType ?? "—")，\(entry.driverName ?? "—")，名次 \(entry.position.map(String.init) ?? "未提供")")
                                    }
                                }
                            }
                        }
                        Text("绿色靠前、橙红靠后、灰色缺项；S 为 Sprint，R 为正赛。车队按下方明细的车手顺序显示。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    AnalysisCard(title: "逐站成绩与赛道") {
                        ForEach(Array(rounds.enumerated()), id: \.offset) { index, round in
                            VStack(alignment: .leading, spacing: 7) {
                                Text("\(index + 1). \(round.raceName ?? "—") · \(round.sessionType ?? "—")").font(.callout.bold())
                                Text("\(round.date ?? "—") · \(round.circuitName ?? "—") · \(round.country ?? "—")").font(.caption2).foregroundStyle(.secondary)
                                ForEach(Array(round.entries.enumerated()), id: \.offset) { _, entry in
                                    HStack(alignment: .top) {
                                        Text(entry.position.map { "P\($0)" } ?? "—").font(.caption.bold())
                                            .frame(width: 36).padding(.vertical, 6)
                                            .background((entry.position ?? 100) <= 3 ? Color.purple.opacity(0.35) : Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.driverName ?? "—").font(.caption)
                                            Text("发车 \(entry.grid.map(String.init) ?? "—") · \(entry.laps.map(String.init) ?? "—") 圈 · \(entry.status ?? "—")").font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(entry.points.map { "\($0.formatted()) 分" } ?? "—").font(.caption.monospacedDigit())
                                    }
                                }
                            }
                            Divider()
                        }
                    }
                }
                if let meta = response?.meta { DataProvenance(meta: meta) }
                if let warnings = response?.data.warnings, !warnings.isEmpty {
                    DisclosureGroup("部分历史数据未提供") {
                        ForEach(warnings, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                    }.font(.caption)
                }
            }
        }
        .task(id: "\(kind)-\(id)-\(season)-\(reload)") {
            loading = true; error = nil
            if let cached = await model.cachedAnalysis(key: "analysis-\(kind)-\(id)", season: season, as: SeasonAnalysis.self) {
                response = cached
            }
            do {
                for _ in 0..<60 {
                    let value = try await model.seasonAnalysis(kind: kind, id: id, season: season)
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
}
