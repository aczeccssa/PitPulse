import AppKit
import SwiftUI

struct SessionResultsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedResult: SessionResult?

    private var selectedSession: NextSession? {
        model.availableResultSessions.first { $0.session.id == model.selectedResultSessionID }
    }

    var body: some View {
        Group {
            if let selectedResult {
                SessionResultDetailView(model: model, result: selectedResult, meeting: selectedSession?.meeting, session: selectedSession?.session) {
                    self.selectedResult = nil
                }
            } else {
                resultsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.selectedResultSessionID) { _, _ in selectedResult = nil }
        .onChange(of: model.serverAddress) { _, _ in selectedResult = nil }
        .task(id: model.selectedResultSessionID) { await model.refreshResults() }
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.availableResultSessions.isEmpty {
                Picker("Session", selection: Binding(
                    get: { model.selectedResultSessionID ?? model.availableResultSessions[0].session.id },
                    set: { model.selectResultSession($0) }
                )) {
                    ForEach(model.availableResultSessions, id: \.session.id) { item in
                        Text("\(item.meeting.name) · \(item.session.sessionType.displayName)")
                            .tag(item.session.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("选择赛事与 Session")
                if let selectedSession {
                    Text("\(selectedSession.session.startTime.formatted(.dateTime.month().day().weekday())) · \(selectedSession.meeting.location)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let error = model.resultError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("成绩刷新失败：\(error)")
            }

            ScrollView {
                if model.sessionResults.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "list.number").font(.title2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.resultError == nil ? "等待赛后成绩" : "无法读取成绩")
                                .font(.headline)
                            Text(model.availableResultSessions.isEmpty
                                ? "比赛结束后显示实际成绩。"
                                : "成绩来源暂未提供结果，可用后自动更新。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                } else if let session = selectedSession?.session {
                    LazyVStack(spacing: 0) {
                        ForEach(model.sessionResults.sorted {
                            ($0.position ?? Int.max, $0.driverId) < ($1.position ?? Int.max, $1.driverId)
                        }) { result in
                            Button { selectedResult = result } label: {
                                HStack(spacing: 8) {
                                    SessionResultRow(result: result, sessionType: session.sessionType, season: model.selectedSeason)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("查看车手成绩详情")
                            Divider().padding(.leading, 48)
                        }
                    }
                    .background(CalendarScrollAppearance())
                }
            }
            .accessibilityLabel("\(selectedSession?.session.sessionType.displayName ?? "Session") 成绩")

            if let meta = model.resultMeta { DataProvenance(meta: meta) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SessionResultRow: View {
    let result: SessionResult
    let sessionType: SessionType
    let season: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(result.position.map(String.init) ?? "—")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
                .accessibilityLabel("名次 \(result.position.map(String.init) ?? "未分类")")

            if let image = MotorsportAsset.image(kind: .helmet, id: result.driverId, season: season) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 30, height: 30)
                    .accessibilityHidden(true)
            } else {
                Text(MotorsportAsset.abbreviation(result.driverName))
                    .font(.caption2.weight(.bold))
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: Circle())
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(result.driverName).font(.callout.weight(.medium)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(result.classification == "classified" ? result.team : "\(result.team) · \(result.classificationLabel)")
                    if let image = MotorsportAsset.image(kind: .teamLogo, id: result.constructorId, season: season) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 24, height: 14).accessibilityHidden(true)
                    }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            metric
                .frame(minWidth: 92, alignment: .trailing)
                .font(.caption.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var metric: some View {
        switch sessionType {
        case .fp1, .fp2, .fp3:
            Text(result.bestLap ?? "—")
        case .qualifying, .sprintQualifying:
            VStack(alignment: .trailing, spacing: 1) {
                Text("Q1 \(result.q1 ?? "—")")
                Text("Q2 \(result.q2 ?? "—") · Q3 \(result.q3 ?? "—")")
            }
        case .sprint, .race:
            VStack(alignment: .trailing, spacing: 1) {
                Text((result.raceTime ?? result.time).flatMap(Double.init).map { AnalysisMath.duration($0) } ?? result.raceTime ?? result.time ?? result.gap ?? "—")
                Text("\(result.laps.map(String.init) ?? "—") 圈 · \(result.points.map { String(format: "%g 分", $0) } ?? "—")")
            }
        }
    }
}


struct SessionResultDetailView: View {
    @ObservedObject var model: AppModel
    let result: SessionResult
    let meeting: Meeting?
    let session: Session?
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("返回成绩")
                .accessibilityLabel("返回成绩")
                .accessibilityIdentifier("results.back")
                .keyboardShortcut(.cancelAction)
                if let image = MotorsportAsset.image(kind: .helmet, id: result.driverId, season: meeting?.season ?? model.selectedSeason) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.driverName).font(.headline).lineLimit(1)
                    Text(result.team).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            Text("\(meeting?.name ?? "比赛成绩") · \(session?.sessionType.displayName ?? "Session")")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    resultSummary
                    Divider()
                    SessionAnalysisView(model: model, result: result, season: meeting?.season ?? model.selectedSeason)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CalendarScrollAppearance())
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .textSelection(.enabled)
    }

    private var resultSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最终成绩").font(.headline)
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("名次").font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(result.position.map(String.init) ?? "—")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(result.classificationLabel).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Rectangle().fill(.quaternary).frame(width: 1, height: 42)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("积分").font(.caption).foregroundStyle(.secondary)
                    Text(result.points?.formatted() ?? "—")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }
            }
            Divider()
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
                ResultFact(title: "比赛用时", value: (result.raceTime ?? result.time).flatMap(Double.init).map { AnalysisMath.duration($0) } ?? result.raceTime ?? result.time ?? "—")
                ResultFact(title: "差距", value: result.gap ?? "—")
                ResultFact(title: "最佳圈", value: result.bestLap ?? "—")
                ResultFact(title: "完成圈数", value: result.laps.map(String.init) ?? "—")
                if session?.sessionType == .qualifying || session?.sessionType == .sprintQualifying {
                    ResultFact(title: "Q1", value: result.q1 ?? "—")
                    ResultFact(title: "Q2", value: result.q2 ?? "—")
                    ResultFact(title: "Q3", value: result.q3 ?? "—")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
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

struct DataProvenance: View {
    let meta: ResponseMeta

    var body: some View {
        DisclosureGroup("数据详情") {
          VStack(alignment: .leading, spacing: 4) {
            Text("\(meta.source ?? "未知来源") · \(meta.quality.displayName) · revision \(meta.revision)\(meta.stale ? " · 已过期" : "")")
            Text("源更新：\(meta.sourceUpdatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—") · 抓取：\(meta.fetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")")
        }
          }
        .font(.caption).foregroundStyle(.secondary)
        .accessibilityIdentifier("dataProvenance")
    }
}
