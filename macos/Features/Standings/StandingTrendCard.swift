import AppKit
import Charts
import SwiftUI
import SharedData

struct StandingTrendCard: View {
    @ObservedObject var model: AppModel
    let kind: String
    let id: String
    let season: Int
    let officialPoints: Double
    let title: String
    let openDetail: () -> Void

    @State var response: APIEnvelope<SeasonAnalysis>?
    @State var loading = true
    @State var error: String?

    var rounds: [AnalysisRound] { response?.data.rounds ?? [] }

    var cumulative: [(index: Int, points: Double)] {
        var sum = 0.0
        return rounds.enumerated().compactMap { index, round in
            guard let points = round.points else { return nil }
            sum += points
            return (index, sum)
        }
    }

    var recent: [AnalysisRound] { Array(rounds.suffix(5)) }

    var body: some View {
        GlassCard(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                CardHeader(title: "\(title) · 赛季走势", actionTitle: "完整分析", actionSymbol: "arrow.up.right", action: openDetail)

                if loading, response == nil {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text("读取赛季明细…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else if let error, cumulative.isEmpty {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if cumulative.isEmpty {
                    Text("逐站积分明细未提供。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(cumulative.last?.points.formatted() ?? "—")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("明细累计")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("积分榜 \(officialPoints.formatted())")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Chart(cumulative, id: \.index) { row in
                        AreaMark(
                            x: .value("场次", row.index + 1),
                            y: .value("累计积分", row.points)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [PitPulseTheme.accent.opacity(0.28), PitPulseTheme.accent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("场次", row.index + 1),
                            y: .value("累计积分", row.points)
                        )
                        .foregroundStyle(PitPulseTheme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                            AxisValueLabel().font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(height: 104)
                    .accessibilityLabel("\(title) 赛季累计积分折线，\(cumulative.count) 场")

                    if !recent.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(Array(recent.enumerated()), id: \.offset) { _, round in
                                VStack(spacing: 2) {
                                    Text("R\(round.round.map(String.init) ?? "—")")
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                    Text(round.points.map { String(format: "%g", $0) } ?? "—")
                                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }

                    Text("Sprint 与正赛分别统计；累计仅包含后端已提供的场次，可能低于积分榜总分。")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: "\(kind)-\(id)-\(season)") {
            loading = true
            error = nil
            do {
                let value = try await model.seasonAnalysis(kind: kind, id: id, season: season)
                try Task.checkCancellation()
                response = value
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}
