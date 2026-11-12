import AppKit
import SwiftUI
import PitPulseData

// MARK: - Results

struct SessionResultsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedResult: SessionResult?

    private var selectedSession: NextSession? {
        model.availableResultSessions.first { $0.session.id == model.selectedResultSessionID }
    }

    private var sortedResults: [SessionResult] {
        model.sessionResults.sorted {
            ($0.position ?? Int.max, $0.driverId) < ($1.position ?? Int.max, $1.driverId)
        }
    }

    var body: some View {
        Group {
            if let selectedResult {
                SessionResultDetailView(
                    model: model,
                    result: selectedResult,
                    meeting: selectedSession?.meeting,
                    session: selectedSession?.session
                ) {
                    self.selectedResult = nil
                }
            } else {
                resultsPage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.selectedResultSessionID) { _, _ in
            selectedResult = nil
        }
        .onChange(of: model.serverAddress) { _, _ in
            selectedResult = nil
        }
        .task(id: model.selectedResultSessionID) { await model.refreshResults() }
    }

    private var resultsPage: some View {
        VStack(spacing: 0) {
            sessionToolbar
            ScrollView {
                VStack(alignment: .leading, spacing: PitPulseTheme.cardSpacing) {
                    if let error = model.resultError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 2)
                    }

                    if model.sessionResults.isEmpty {
                        emptyResults
                    } else {
                        podium
                        classificationTable
                    }
                }
                .padding(.horizontal, PitPulseTheme.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .background(CalendarScrollAppearance())
            }
        }
    }

    private var sessionToolbar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(model.availableResultSessions, id: \.session.id) { item in
                    Button {
                        model.selectResultSession(item.session.id)
                    } label: {
                        Text("\(item.meeting.name) · \(item.session.sessionType.displayName)")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(sessionMenuTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("选择赛事与 Session")

            if let selectedSession {
                Text(selectedSession.session.startTime.formatted(.dateTime.month().day().weekday(.abbreviated)))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

            if model.liveStore.snapshot.sessionId == model.selectedResultSessionID {
                StatusPill(text: "LIVE", tint: PitPulseTheme.accent)
            }

            if model.isRefreshing {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var sessionMenuTitle: String {
        guard let selectedSession else {
            return model.availableResultSessions.isEmpty ? "暂无已结束 Session" : "选择 Session"
        }
        return "\(selectedSession.meeting.name) · \(selectedSession.session.sessionType.displayName)"
    }

    private var emptyResults: some View {
        EmptyStateCard(
            symbol: "list.number",
            title: model.resultError == nil ? "等待赛后成绩" : "无法读取成绩",
            message: model.availableResultSessions.isEmpty
                ? "比赛结束后显示实际成绩。"
                : "成绩来源暂未提供结果，可用后自动更新。"
        )
    }

    // MARK: Podium — pyramid: P1 on top, P2 / P3 below

    private var podium: some View {
        GlassCard(padding: 12) {
            VStack(spacing: 8) {
                CardHeader(title: "领奖台")
                VStack(spacing: -26) {
                    if let leader = sortedResults.first {
                        leaderCard(leader)
                            .zIndex(1)
                    }
                    if sortedResults.count > 1 {
                        HStack(spacing: -14) {
                            ForEach(Array(sortedResults.dropFirst().prefix(2).enumerated()), id: \.element.id) { index, result in
                                runnerCard(result, rank: index + 2)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                }
            }
        }
    }

    private func leaderCard(_ result: SessionResult) -> some View {
        Button { selectedResult = result } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("P\(result.position ?? 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(podiumTime(result))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .foregroundStyle(PitPulseTheme.accent)

                helmetImage(result, size: 52)

                Text(result.driverName)
                    .font(.system(size: 16.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("\(result.points.map { String(format: "%g", $0) } ?? "—") 分")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PitPulseTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("冠军 \(result.driverName)，\(result.team)，\(podiumTime(result))")
        .accessibilityHint("查看完整比赛数据")
    }

    private func runnerCard(_ result: SessionResult, rank: Int) -> some View {
        Button { selectedResult = result } label: {
            VStack(spacing: 4) {
                helmetImage(result, size: 44)

                Text(result.driverName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 4) {
                    Text("\(result.points.map { String(format: "%g", $0) } ?? "—") 分")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("·")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("P\(result.position ?? rank)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PitPulseTheme.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(result.position ?? rank) 名 \(result.driverName)，\(podiumTime(result))")
        .accessibilityHint("查看完整比赛数据")
    }

    private func helmetImage(_ result: SessionResult, size: CGFloat) -> some View {
        DriverHelmetAvatar(
            driverID: result.driverId,
            name: result.driverName,
            season: model.selectedSeason,
            size: size
        )
    }

    private func podiumTime(_ result: SessionResult) -> String {
        if let raceTime = result.raceTime ?? result.time { return raceTime }
        if let gap = result.gap, !gap.isEmpty { return gap }
        return result.bestLap ?? "—"
    }

    // MARK: Classification

    private var classificationTable: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("分类").font(.system(size: 12.5, weight: .semibold)).tracking(0.6)
                    Spacer()
                    Text("用时 / 差距").font(.system(size: 10.5, weight: .medium))
                    Text("积分").font(.system(size: 10.5, weight: .medium)).frame(width: 30, alignment: .trailing)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 11)
                .padding(.bottom, 7)

                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

                ForEach(Array(sortedResults.enumerated()), id: \.element.id) { index, result in
                    VStack(spacing: 0) {
                        Button {
                            selectedResult = result
                        } label: {
                            resultRow(result)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("查看完整比赛数据")
                        .accessibilityIdentifier("results.row.\(result.driverId)")

                        if index != sortedResults.count - 1 {
                            Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1)
                                .padding(.leading, 46)
                        }
                    }
                }
            }
        }
    }

    private func resultRow(_ result: SessionResult) -> some View {
        HStack(spacing: 8) {
            Text(result.position.map(String.init) ?? "—")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
                .foregroundStyle(result.position == 1 ? PitPulseTheme.accent : .secondary)

            helmetImage(result, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.driverName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(result.team)
                    if result.classification != "classified" {
                        Text("· \(result.classificationLabel)")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(resultTime(result))
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 92, alignment: .trailing)

            Text(result.points.map { String(format: "%g", $0) } ?? "—")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func resultTime(_ result: SessionResult) -> String {
        switch selectedSession?.session.sessionType {
        case .qualifying, .sprintQualifying:
            return result.q3 ?? result.q2 ?? result.q1 ?? "—"
        case .fp1, .fp2, .fp3:
            return result.bestLap ?? "—"
        default:
            if let raceTime = result.raceTime ?? result.time, !raceTime.isEmpty { return raceTime }
            return result.gap ?? result.bestLap ?? "—"
        }
    }
}

// MARK: - Expanded row

private struct DriverRaceFactsCard: View {
    @ObservedObject var model: AppModel
    let result: SessionResult
    let season: Int

    @State private var response: APIEnvelope<SessionAnalysis>?
    @State private var error: String?
    @State private var loading = true

    private var data: SessionAnalysis? { response?.data }
    private var fastestLap: AnalysisLap? {
        data?.laps
            .filter { ($0.lapDuration ?? 0) > 0 && $0.isPitOutLap != true }
            .min { ($0.lapDuration ?? .infinity) < ($1.lapDuration ?? .infinity) }
    }
    private var lastStint: AnalysisStint? {
        data?.stints.max { ($0.stintNumber ?? 0) < ($1.stintNumber ?? 0) }
    }
    private var pitCount: Int { data?.pit.count ?? 0 }
    private var fastestStop: Double? {
        data?.pit.compactMap { $0.stopDuration ?? $0.pitDuration }.min()
    }
    private var topSpeed: Double? {
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

    private func sectorChip(_ label: String, _ value: Double?) -> some View {
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

    private func inlineFact(title: String, value: String, tint: Color) -> some View {
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

    private func compoundText(_ compound: String?) -> String {
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

    private func compoundTint(_ compound: String?) -> Color {
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

struct SessionResultDetailView: View {
    @ObservedObject var model: AppModel
    let result: SessionResult
    let meeting: Meeting?
    let session: Session?
    let onBack: () -> Void

    private var season: Int { meeting?.season ?? model.selectedSeason }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    resultSummary
                    DriverRaceFactsCard(model: model, result: result, season: season)
                    SessionAnalysisView(model: model, result: result, season: season)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PitPulseTheme.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(CalendarScrollAppearance())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .textSelection(.enabled)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12.5, weight: .bold))
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("返回成绩")
            .accessibilityLabel("返回成绩")
            .accessibilityIdentifier("results.back")
            .keyboardShortcut(.cancelAction)

            DriverHelmetAvatar(
                driverID: result.driverId,
                name: result.driverName,
                season: season,
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(result.driverName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text("\(result.team) · \(meeting?.name ?? "比赛成绩") · \(session?.sessionType.displayName ?? "Session")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            favoriteButton

            VStack(alignment: .trailing, spacing: 1) {
                Text(result.position.map { "P\($0)" } ?? "—")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(result.points.map { String(format: "%g 分", $0) } ?? "—")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.vertical, 10)
    }

    private var favoriteButton: some View {
        let isFavorite = model.favoriteDriverId(for: .f1) == result.driverId
        return Button {
            model.setFavoriteDriver(isFavorite ? nil : result.driverId, name: result.driverName)
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.05), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isFavorite ? "取消关注 \(result.driverName)" : "关注 \(result.driverName)")
        .accessibilityLabel(isFavorite ? "取消关注" : "关注车手")
    }

    private var resultSummary: some View {
        GlassCard(padding: 10) {
            VStack(alignment: .leading, spacing: 11) {
                CardHeader(title: "最终成绩")
                HStack(spacing: 8) {
                    summaryMetric("名次", result.position.map(String.init) ?? "—", tint: PitPulseTheme.accent)
                    summaryMetric("积分", result.points.map { String(format: "%g", $0) } ?? "—")
                    summaryMetric("完成圈数", result.laps.map(String.init) ?? "—")
                    summaryMetric("状态", result.classificationLabel)
                }
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ResultFact(title: "比赛用时", value: (result.raceTime ?? result.time).flatMap(Double.init).map { AnalysisMath.duration($0) } ?? result.raceTime ?? result.time ?? "—")
                    ResultFact(title: "差距", value: result.gap ?? "—")
                    ResultFact(title: "最佳圈", value: result.bestLap ?? "—")
                    if session?.sessionType == .qualifying || session?.sessionType == .sprintQualifying {
                        ResultFact(title: "Q1", value: result.q1 ?? "—")
                        ResultFact(title: "Q2", value: result.q2 ?? "—")
                        ResultFact(title: "Q3", value: result.q3 ?? "—")
                    }
                }
            }
        }
    }

    private func summaryMetric(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ResultFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium)).monospacedDigit().lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
