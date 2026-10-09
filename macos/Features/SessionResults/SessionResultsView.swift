import AppKit
import SwiftUI

struct SessionResultsView: View {
    @ObservedObject var model: AppModel

    private var selectedSession: NextSession? {
        model.availableResultSessions.first { $0.session.id == model.selectedResultSessionID }
    }

    var body: some View {
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
                .labelsHidden()
                .accessibilityLabel("选择赛事与 Session")
            }

            if let error = model.resultError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("成绩刷新失败：\(error)")
            }

            if model.sessionResults.isEmpty {
                ContentUnavailableView(
                    model.resultError == nil ? "暂无成绩" : "无法读取成绩",
                    systemImage: "list.number",
                    description: Text(model.availableResultSessions.isEmpty
                        ? "比赛结束后显示实际成绩。"
                        : "保留缓存；上游数据可用后自动更新。")
                )
            } else if let session = selectedSession?.session {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.sessionResults.sorted {
                            ($0.position ?? Int.max, $0.driverId) < ($1.position ?? Int.max, $1.driverId)
                        }) { result in
                            SessionResultRow(result: result, sessionType: session.sessionType, season: model.selectedSeason)
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .accessibilityLabel("\(session.sessionType.displayName) 成绩")
            }

            if let meta = model.resultMeta { DataProvenance(meta: meta) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task(id: model.selectedResultSessionID) { await model.refreshResults() }
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
                    Text(result.classification == "classified" ? result.team : "\(result.team) · \(result.classification)")
                    if let image = MotorsportAsset.image(kind: .teamLogo, id: result.constructorId, season: season) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 24, height: 14).accessibilityHidden(true)
                    }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            metric
                .font(.caption.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
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
                Text(result.raceTime ?? result.time ?? result.gap ?? "—")
                Text("\(result.laps.map(String.init) ?? "—") 圈 · \(result.points.map { String(format: "%g 分", $0) } ?? "—")")
            }
        }
    }
}


struct DataProvenance: View {
    let meta: ResponseMeta

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(meta.source ?? "未知来源") · \(meta.quality.displayName) · revision \(meta.revision)\(meta.stale ? " · 已过期" : "")")
            Text("源更新：\(meta.sourceUpdatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—") · 抓取：\(meta.fetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")")
        }
        .font(.caption2).foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
