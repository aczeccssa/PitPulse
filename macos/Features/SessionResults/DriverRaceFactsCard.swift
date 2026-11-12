import AppKit
import SwiftUI
import SharedData

struct DriverRaceFactsCard: View {
    @ObservedObject var model: AppModel
    let result: SessionResult
    let season: Int

    @State var response: APIEnvelope<SessionAnalysis>?
    @State var error: String?
    @State var loading = true

    var data: SessionAnalysis? { response?.data }
    var fastestLap: AnalysisLap? {
        data?.laps
            .filter { ($0.lapDuration ?? 0) > 0 && $0.isPitOutLap != true }
            .min { ($0.lapDuration ?? .infinity) < ($1.lapDuration ?? .infinity) }
    }
    var lastStint: AnalysisStint? {
        data?.stints.max { ($0.stintNumber ?? 0) < ($1.stintNumber ?? 0) }
    }
    var pitCount: Int { data?.pit.count ?? 0 }
    var fastestStop: Double? {
        data?.pit.compactMap { $0.stopDuration ?? $0.pitDuration }.min()
    }
    var topSpeed: Double? {
        data?.laps.compactMap(\.stSpeed).max() ?? data?.carData.compactMap(\.speed).max()
    }

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 11) {
                CardHeader(title: "本场关键数据")

                if loading {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text("读取分段与策略…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else if let error {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    if let lap = fastestLap {
                        HStack(spacing: 6) {
                            sectorChip("S1", lap.durationSector1)
                            sectorChip("S2", lap.durationSector2)
                            sectorChip("S3", lap.durationSector3)
                            Text("最快圈 \(AnalysisMath.duration(lap.lapDuration))")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 6) {
                        if let stint = lastStint, let lapStart = stint.lapStart, let lapEnd = stint.lapEnd {
                            inlineFact(
                                title: "末段轮胎",
                                value: "\(compoundText(stint.compound)) · \(lapStart)–\(lapEnd) 圈",
                                tint: compoundTint(stint.compound)
                            )
                        }
                        inlineFact(
                            title: "进站",
                            value: pitCount == 0 ? "未记录" : "\(pitCount) 次 · 最快 \(AnalysisMath.duration(fastestStop))",
                            tint: .secondary
                        )
                        inlineFact(
                            title: "极速",
                            value: topSpeed.map { String(format: "%.0f km/h", $0) } ?? "未提供",
                            tint: .secondary
                        )
                    }

                    if data?.hasData != true {
                        Text("该 Session 暂无分段或策略采样。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: "\(result.sessionId)-\(result.driverId)") {
            loading = true
            error = nil
            if let cached = await model.cachedAnalysis(
                key: "analysis-\(result.sessionId)-\(result.driverId)-0",
                season: season,
                as: SessionAnalysis.self
            ) {
                response = cached
                loading = false
            }
            do {
                let value = try await model.sessionAnalysis(
                    sessionID: result.sessionId,
                    driverID: result.driverId,
                    season: season,
                    lap: nil
                )
                try Task.checkCancellation()
                response = value
                error = value.meta.analysisError
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    func sectorChip(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(AnalysisMath.duration(value))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    func inlineFact(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func compoundText(_ compound: String?) -> String {
        switch compound?.uppercased() {
        case "SOFT": "软胎"
        case "MEDIUM": "中性胎"
        case "HARD": "硬胎"
        case "INTERMEDIATE": "半雨胎"
        case "WET": "雨胎"
        case let other?: other
        case nil: "未提供"
        }
    }

    func compoundTint(_ compound: String?) -> Color {
        switch compound?.uppercased() {
        case "SOFT": .red
        case "MEDIUM": .yellow
        case "HARD": .white
        case "INTERMEDIATE": .green
        case "WET": .blue
        default: .secondary
        }
    }
}

// MARK: - Driver detail
