import AppKit
import Charts
import SwiftUI
import SharedData

struct SeasonAnalysisView: View {
    @ObservedObject var model: AppModel
    let kind: String
    let id: String
    let season: Int
    let officialPoints: Double
    @State var response: APIEnvelope<SeasonAnalysis>?
    @State var error: String?
    @State var loading = true
    @State var reload = 0
    var rounds: [AnalysisRound] { response?.data.rounds ?? [] }
    var cumulative: [(index: Int, points: Double)] {
        var sum = 0.0
        return rounds.enumerated().compactMap { index, round in
            guard let points = round.points else { return nil }
            sum += points
            return (index, sum)
        }
    }
    var contributions: [(name: String, points: Double)] {
        var sums: [String: Double] = [:]
        for entry in rounds.flatMap(\.entries) {
            if let name = entry.driverName, let points = entry.points { sums[name, default: 0] += points }
        }
        return sums.map { ($0.key, $0.value) }.sorted { $0.points > $1.points }
    }
    func rankColor(_ rank: Int?) -> Color {
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
