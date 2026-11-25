import Charts
import SharedData
import SwiftUI

struct DriverAnalysisScreen: View {
    @EnvironmentObject private var model: MobileModel
    let sessionID: String
    let driver: SessionResult
    let season: Int
    let sessionLabel: String
    var embedded = false
    @State private var analysis: SessionAnalysis?
    @State private var error: String?
    @State private var focusedLap: Int?

    var body: some View {
        if embedded {
            charts
        } else {
            charts
                .navigationTitle("Driver Charts (\(sessionLabel))")
                .dashboardDetail()
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var charts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    AssetImage(
                        name: MotorsportAssetName.driverAvatarName(
                            driverID: driver.driverId, name: driver.driverName, season: season)
                    )
                    .frame(width: 56, height: 50)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(driver.driverName).font(.title3.bold())
                        HStack(spacing: 5) {
                            AssetImage(
                                name: MotorsportAssetName.name(kind: .teamLogo, id: driver.constructorId, season: season)
                            )
                            .frame(width: 18, height: 15)
                            Text([driver.team, driver.resultNumber].compactMap { $0 }.joined(separator: " · "))
                        }
                        .font(.caption).foregroundStyle(WebDashboardStyle.homeMuted)
                    }
                    Spacer(minLength: 4)
                    Text(driver.position.map { "P\($0)" } ?? "—")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(PulseStyle.red)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(14)
                .dashboardPanel(WebDashboardStyle.homePanel)

                if let analysis {
                    lapChart(analysis)
                    sectorChart(analysis)
                    stintChart(analysis)
                }
                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.caption)
                        Button("Retry") { Task { await load() } }
                    }
                } else if analysis == nil {
                    PulseSkeleton(label: "Loading lap pace…", chart: true)
                    PulseSkeleton(label: "Loading sector times…", chart: true)
                    PulseSkeleton(rows: 2, label: "Loading tire stints…")
                }
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }
            .background(WebDashboardStyle.homeBackground)
            .pulseSwap(analysis != nil)
            .refreshable { await load() }
            .task(id: model.dataContext) { await load() }
    }
    private func lapChart(_ analysis: SessionAnalysis) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 16) {
                let timed = analysis.laps.filter { $0.lapNumber != nil && $0.lapDuration != nil }
                let best = timed.min { ($0.lapDuration ?? .infinity) < ($1.lapDuration ?? .infinity) }
                let current = timed.first { focusedLap != nil && $0.lapNumber == focusedLap } ?? best
                HStack {
                    Text("Lap Pace").font(.headline)
                    Spacer()
                    PulseNumber("\(analysis.laps.count) laps").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("analysis.lapCount")
                }
                if let current, let duration = current.lapDuration, let lap = current.lapNumber {
                    HStack(alignment: .firstTextBaseline) {
                        Text(AnalysisMath.duration(duration)).font(.title2.bold().monospacedDigit())
                        Text(current.lapNumber == best?.lapNumber ? "Fastest Lap · L\(lap)" : "L\(lap)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Chart {
                        ForEach(timed, id: \.lapNumber) { lap in
                            if let number = lap.lapNumber, let duration = lap.lapDuration {
                                LineMark(x: .value("Lap", number), y: .value("Seconds", duration)).foregroundStyle(PulseStyle.red)
                            }
                        }
                        RuleMark(x: .value("Lap", lap)).lineStyle(StrokeStyle(dash: [3, 3])).foregroundStyle(.secondary)
                        PointMark(x: .value("Lap", lap), y: .value("Seconds", duration)).foregroundStyle(PulseStyle.red)
                    }.pulseChart().frame(height: 196).chartXSelection(value: $focusedLap)
                        .chartYScale(domain: .automatic(includesZero: false))
                } else {
                    Text("No lap-by-lap data").foregroundStyle(.secondary)
                }
            }
        }
    }
    private func sectorChart(_ analysis: SessionAnalysis) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sector Times").font(.headline)
                if analysis.laps.contains(where: { $0.sectors.contains { $0 != nil } }) {
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Best S\(index + 1)").font(.caption).foregroundStyle(.secondary)
                                Text(
                                    analysis.laps.compactMap { $0.sectors[index] }.min().map { String(format: "%.3f s", $0) }
                                        ?? "—"
                                )
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Chart(Array(analysis.laps.enumerated()), id: \.offset) { _, lap in
                        if let number = lap.lapNumber {
                            ForEach(0..<3, id: \.self) { index in
                                if let value = lap.sectors[index] {
                                    BarMark(x: .value("Lap", number), y: .value("Seconds", value))
                                        .foregroundStyle(by: .value("Sector", "S\(index + 1)"))
                                }
                            }
                        }
                    }.pulseChart().chartForegroundStyleScale(["S1": PulseStyle.red, "S2": Color.orange, "S3": Color.purple]).frame(
                        height: 196)
                } else {
                    Text("No sector times").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stintChart(_ analysis: SessionAnalysis) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tire Stints").font(.headline)
                ForEach(Array(analysis.stints.enumerated()), id: \.offset) { index, stint in
                    let compound = stint.compound?.uppercased() ?? "—"
                    let badge = tireBadgeStyle(for: compound)
                    HStack(spacing: 10) {
                        Text(badge.letter)
                            .font(.caption2.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(badge.color)
                            .frame(width: 24, height: 24)
                            .overlay { Circle().strokeBorder(badge.color, lineWidth: 2) }
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(compound).font(.caption.weight(.medium))
                            Text("Stint \(stint.stintNumber ?? index + 1)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text([stint.lapStart, stint.lapEnd].map { $0.map { "L\($0)" } ?? "—" }.joined(separator: " – "))
                            .font(.subheadline.monospacedDigit())
                    }
                }
                if analysis.stints.isEmpty { Text("No tire stints recorded").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func tireBadgeStyle(for compound: String) -> (letter: String, color: Color) {
        switch compound {
        case "SOFT": ("S", PulseStyle.red)
        case "MEDIUM": ("M", .yellow)
        case "HARD": ("H", .primary)
        case "INTERMEDIATE", "INTER": ("I", .green)
        case "WET": ("W", .blue)
        default: ("—", .secondary)
        }
    }

    private func load() async {
        let dataContext = model.dataContext
        guard let url = model.serverURL else {
            error = "Invalid server address"
            return
        }
        error = nil
        do {
            for attempt in 0..<60 {
                let response = try await APIClient(baseURL: url).sessionAnalysis(
                    sessionId: sessionID, driverId: driver.driverId, lap: nil, token: model.currentToken)
                try Task.checkCancellation()
                guard dataContext == model.dataContext else { return }
                let pending = response.meta.analysisStatus == "loading" || response.meta.analysisStatus == "refreshing"
                if pending {
                    if response.data.hasData {
                        analysis = response.data
                    }
                    if attempt == 59 {
                        error = "Historical data is still syncing. Pull to refresh."
                        return
                    }
                    try await Task.sleep(for: .seconds(2))
                    continue
                }
                analysis = response.data
                if response.meta.analysisStatus == "failed" { error = response.meta.analysisError ?? "Session data is temporarily unavailable. Pull to retry." }
                return
            }
        } catch {
            if !Task.isCancelled, dataContext == model.dataContext { self.error = MobileModel.message(for: error).pulseEnglishError }
        }
    }
}
