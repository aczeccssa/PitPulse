import AppKit
import SwiftUI
import SharedData

// MARK: - Results

struct SessionResultsView: View {
    @ObservedObject var model: AppModel
    var context: NextSession? = nil
    @State var localResults: [SessionResult] = []
    @State var localError: String?
    @State var selectedResult: SessionResult?

    var displayedResults: [SessionResult] { context == nil ? model.sessionResults : localResults }
    var displayedError: String? { context == nil ? model.resultError : localError }

    var selectedSession: NextSession? {
        context ?? model.availableResultSessions.first { $0.session.id == model.selectedResultSessionID }
    }

    var sortedResults: [SessionResult] {
        displayedResults.sorted {
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
        .task(id: "\(context?.session.id ?? model.selectedResultSessionID ?? "")-\(model.serverAddress)") {
            if let context {
                do {
                    let response = try await model.meetingSessionResults(sessionID: context.session.id, season: context.meeting.season)
                    try Task.checkCancellation()
                    localResults = response.data
                    localError = nil
                } catch is CancellationError { return }
                catch { localError = error.localizedDescription }
            } else { await model.refreshResults() }
        }
    }

    var resultsPage: some View {
        VStack(spacing: 0) {
            if context == nil { sessionToolbar }
            ScrollView {
                VStack(alignment: .leading, spacing: PitPulseTheme.cardSpacing) {
                    if let error = displayedError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 2)
                    }

                    if displayedResults.isEmpty {
                        emptyResults
                    } else {
                        if selectedSession?.session.sessionType == .race || selectedSession?.session.sessionType == .sprint { podium }
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

    var sessionToolbar: some View {
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

    var sessionMenuTitle: String {
        guard let selectedSession else {
            return model.availableResultSessions.isEmpty ? "暂无已结束 Session" : "选择 Session"
        }
        return "\(selectedSession.meeting.name) · \(selectedSession.session.sessionType.displayName)"
    }

    var emptyResults: some View {
        let pending = context == nil && model.seasonHasNotStarted && displayedError == nil
        return EmptyStateCard(
            symbol: "list.number",
            title: pending ? "赛季尚未开始" : displayedError == nil ? "等待赛后成绩" : "无法读取成绩",
            message: model.availableResultSessions.isEmpty
                ? "比赛结束后显示实际成绩。"
                : "成绩来源暂未提供结果，可用后自动更新。"
        )
    }

    // MARK: Podium — pyramid: P1 on top, P2 / P3 below

    var podium: some View {
        ResultsPodium(results: sortedResults, season: selectedSession?.meeting.season ?? model.selectedSeason) {
            selectedResult = $0
        }
    }
}
