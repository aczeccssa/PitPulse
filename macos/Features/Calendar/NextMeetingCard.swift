import AppKit
import SwiftUI
import PitPulseData
import PitPulseShared

// MARK: - Race weekend dashboard

struct NextMeetingCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let meeting = CalendarLogic.featuredMeeting(in: model.meetings, now: context.date) {
                    VStack(alignment: .leading, spacing: PitPulseTheme.cardSpacing) {
                        RaceHeroCard(
                            meeting: meeting,
                            nextSession: CalendarLogic.nextSession(in: [meeting], now: context.date),
                            now: context.date
                        )
                        WeekendTimelineCard(meeting: meeting, now: context.date)
                        WeekendConditionsCard(meeting: meeting, now: context.date)
                        SeasonLeaderCard()
                    }
                    .padding(.horizontal, PitPulseTheme.pagePadding)
                    .padding(.vertical, 14)
                    .background(CalendarScrollAppearance())
                } else if model.isRefreshing {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在读取赛历…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    EmptyStateCard(
                        symbol: AppSymbol.calendar.resolvedSystemName(),
                        title: "暂无比赛",
                        message: "该赛季还没有可用的赛程。切换年份或刷新后重试。"
                    )
                    .padding(PitPulseTheme.pagePadding)
                    .padding(.top, 24)
                }
            }
        }
    }
}

// MARK: - Hero

private struct RaceHeroCard: View {
    let meeting: Meeting
    let nextSession: NextSession?
    let now: Date

    var body: some View {
        GlassCard(padding: 13) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text(CountryFlag.emoji(for: meeting.countryCode) ?? "🌐")
                        .font(.system(size: 22))
                        .accessibilityLabel("举办国 \(meeting.country)")

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text("R\(meeting.round.map(String.init) ?? "—")")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(PitPulseTheme.accent)
                            Text(meeting.name)
                                .font(.system(size: 15.5, weight: .semibold))
                                .tracking(-0.1)
                                .lineLimit(1)
                        }
                        Text("\(meeting.circuit?.name ?? meeting.location) · \(meeting.startDate.formatted(.dateTime.month().day())) – \(meeting.endDate.formatted(.dateTime.month().day()))")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    if let nextSession {
                        CountdownRow(next: nextSession, now: now)
                    }
                }

                if let nextSession {
                    HStack(spacing: 5) {
                        Circle().fill(PitPulseTheme.accent).frame(width: 4, height: 4)
                        Text("下一节 \(nextSession.session.sessionType.displayName)")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(nextSession.session.startTime.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if meeting.status != .scheduled {
                            Text(meeting.status.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal").font(.system(size: 11))
                        Text("本周末赛程已结束")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }
}

private struct CountdownRow: View {
    let next: NextSession
    let now: Date

    private var remaining: TimeInterval {
        max(0, next.session.startTime.timeIntervalSince(now))
    }

    private var days: Int { Int(remaining) / 86_400 }
    private var hours: Int { (Int(remaining) % 86_400) / 3_600 }
    private var minutes: Int { (Int(remaining) % 3_600) / 60 }
    private var seconds: Int { Int(remaining) % 60 }

    var body: some View {
        HStack(spacing: 5) {
            CountdownUnit(value: days, unit: "天")
            CountdownUnit(value: hours, unit: "时")
            CountdownUnit(value: minutes, unit: "分")
            CountdownUnit(value: seconds, unit: "秒")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("距下一节 \(days) 天 \(hours) 小时 \(minutes) 分")
    }
}

private struct CountdownUnit: View {
    let value: Int
    let unit: String

    var body: some View {
        HStack(spacing: 1) {
            Text(String(format: "%02d", value))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 26)
    }
}

// MARK: - Weekend timeline

private struct WeekendTimelineCard: View {
    let meeting: Meeting
    let now: Date

    private var sessions: [Session] {
        meeting.sessions.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "比赛周末")
                if sessions.isEmpty {
                    Text("暂无 Session 数据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            SessionTimelineRow(
                                session: session,
                                state: state(for: session),
                                isLast: index == sessions.count - 1
                            )
                        }
                    }
                }
            }
        }
    }

    private func state(for session: Session) -> SessionTimelineRow.State {
        if session.status == .cancelled { return .cancelled }
        if session.status == .postponed { return .postponed }
        let end = session.endTime ?? session.startTime.addingTimeInterval(7_200)
        if now >= end || session.status == .finished { return .finished }
        if now >= session.startTime { return .running }
        return .upcoming
    }
}

private struct SessionTimelineRow: View {
    enum State {
        case finished, running, upcoming, cancelled, postponed
    }

    let session: Session
    let state: State
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(dotFill)
                    .frame(width: 8, height: 8)
                    .overlay {
                        if case .running = state {
                            Circle().strokeBorder(PitPulseTheme.accent.opacity(0.35), lineWidth: 4)
                        }
                    }
                    .padding(.top, 5)
                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 10)

            HStack(alignment: .center, spacing: 8) {
                Text(session.sessionType.displayName)
                    .font(.system(size: 13, weight: state.isUpcoming ? .semibold : .medium))
                    .foregroundStyle(state.isUpcoming ? Color.primary : Color.secondary)
                Spacer(minLength: 6)
                Text(session.startTime.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(state.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(state.tint)
                    .frame(width: 46, alignment: .trailing)
            }
            .padding(.bottom, isLast ? 2 : 9)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.sessionType.displayName)，\(session.startTime.formatted(date: .abbreviated, time: .shortened))，\(state.label)")
    }

    private var dotFill: Color {
        switch state {
        case .finished: PitPulseTheme.accent
        case .running: PitPulseTheme.accent
        case .upcoming: Color.secondary.opacity(0.45)
        case .cancelled, .postponed: Color.orange
        }
    }
}

private extension SessionTimelineRow.State {
    var isUpcoming: Bool {
        if case .upcoming = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .finished: "已结束"
        case .running: "进行中"
        case .upcoming: "未开始"
        case .cancelled: "已取消"
        case .postponed: "延期"
        }
    }

    var tint: Color {
        switch self {
        case .finished: .secondary
        case .running: PitPulseTheme.accent
        case .upcoming: .secondary
        case .cancelled, .postponed: .orange
        }
    }
}

// MARK: - Conditions + circuit

private struct WeekendConditionsCard: View {
    @EnvironmentObject private var model: AppModel
    let meeting: Meeting
    let now: Date

    @State private var forecast: PitPulseForecast?
    @State private var statusText = "正在读取预报…"
    @State private var showingMap = false

    private var targetHour: PitPulseForecastHour? {
        guard let forecast else { return nil }
        let anchor = CalendarLogic.nextSession(in: [meeting], now: now)?.session.startTime ?? meeting.startDate
        return forecast.hours.min {
            abs($0.time - anchor.timeIntervalSince1970) < abs($1.time - anchor.timeIntervalSince1970)
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "比赛条件", actionTitle: meeting.circuit == nil ? nil : (showingMap ? "收起地图" : "赛道地图"), actionSymbol: "map") {
                    showingMap.toggle()
                    if showingMap {
                        Task { await model.mapStore.load(model: model, meeting: meeting) }
                    } else {
                        model.mapStore.pause()
                    }
                }

                if let hour = targetHour {
                    HStack(spacing: 8) {
                        ConditionTile(
                            symbol: "thermometer.medium",
                            label: "气温",
                            value: hour.airTemp.map { String(format: "%.0f°", $0) } ?? "—",
                            detail: hour.conditionText
                        )
                        ConditionTile(
                            symbol: "drop.fill",
                            label: "降雨",
                            value: hour.precipitationProbability.map { String(format: "%.0f%%", $0) } ?? "—",
                            detail: hour.precipitation.map { String(format: "%.1f mm", $0) } ?? "概率",
                            tint: .blue
                        )
                        ConditionTile(
                            symbol: "wind",
                            label: "风速",
                            value: hour.windSpeed.map { String(format: "%.1f", $0) } ?? "—",
                            detail: "m/s",
                            tint: .teal
                        )
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "cloud.sun")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        Text(statusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                if showingMap {
                    if meeting.circuit == nil {
                        Text("暂无赛道地点坐标")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        MapView(store: model.mapStore, meeting: meeting)
                            .frame(height: 170)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        if let error = model.mapStore.error {
                            Text(error).font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 9))
                    Text(meeting.circuit?.name ?? "赛道信息未提供")
                    Spacer()
                    if let circuit = meeting.circuit {
                        Text(String(format: "%.4f, %.4f", circuit.latitude, circuit.longitude))
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
        }
        .task(id: "\(meeting.id)-\(model.serverAddress)") {
            forecast = nil
            statusText = "正在读取预报…"
            do {
                let result = try await MeetingForecast.load(meetingID: meeting.id, model: model)
                try Task.checkCancellation()
                forecast = result.forecast
                statusText = result.stale ? "\(result.forecast.statusText) · 已过期" : result.forecast.statusText
            } catch is CancellationError {
                return
            } catch {
                statusText = "天气暂不可用：\(error.localizedDescription)"
            }
        }
        .onDisappear { model.mapStore.pause() }
    }
}

private struct ConditionTile: View {
    let symbol: String
    let label: String
    let value: String
    let detail: String
    var tint: Color = .orange

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 2) {
                    Text(value)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value) \(detail)")
    }
}

// MARK: - Season leader

private struct SeasonLeaderCard: View {
    @EnvironmentObject private var model: AppModel

    private var leaders: [DriverStanding] {
        Array(model.driverStandings.sorted { $0.position < $1.position }.prefix(3))
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "\(String(model.selectedSeason)) 车手积分")
                if leaders.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("积分榜载入后显示领跑者")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(leaders.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 8) {
                                Text(String(row.position))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(index == 0 ? PitPulseTheme.accent : .secondary)
                                    .frame(width: 18, alignment: .trailing)
                                DriverHelmetAvatar(
                                    driverID: row.driverId,
                                    name: row.driverName,
                                    season: model.selectedSeason,
                                    size: 26
                                )
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.driverName)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .lineLimit(1)
                                    Text(row.constructor)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                Text("\(row.points.formatted()) 分")
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                Text("\(row.wins) 胜")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                            .padding(.vertical, 8)
                            if index != leaders.count - 1 {
                                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
        .task(id: "\(model.selectedSeason)-\(model.serverAddress)") {
            model.ensureDriverStandingsLoaded()
        }
    }
}

// MARK: - Forecast payload

struct PitPulseForecastEnvelope: Decodable {
    let data: PitPulseForecast
    let meta: PitPulseForecastMeta
}

struct PitPulseForecastMeta: Decodable {
    let stale: Bool
}

struct PitPulseForecast: Decodable {
    let status: String
    let hours: [PitPulseForecastHour]

    var statusText: String {
        switch status {
        case "available": "比赛日预报"
        case "past_event": "已结束赛事不提供天气预报"
        default: "尚无比赛日期预报"
        }
    }
}

struct PitPulseForecastHour: Decodable {
    let utc: String
    var time: Double { RFC3339.parse(utc)?.timeIntervalSince1970 ?? .greatestFiniteMagnitude }
    let airTemp: Double?
    let precipitationProbability: Double?
    let precipitation: Double?
    let windSpeed: Double?
    let weatherCode: Int?

    var conditionText: String {
        guard let weatherCode else { return "预报" }
        switch weatherCode {
        case 0: return "晴"
        case 1...3: return "多云"
        case 45, 48: return "雾"
        case 51...57: return "毛毛雨"
        case 61...67: return "降雨"
        case 71...77: return "降雪"
        case 80...82: return "阵雨"
        case 85, 86: return "阵雪"
        case 95...99: return "雷暴"
        default: return "预报"
        }
    }
}

enum MeetingForecast {
    static func load(meetingID: String, model: AppModel) async throws -> (forecast: PitPulseForecast, stale: Bool) {
        let data = try await model.mapData(path: "/api/v1/meetings/\(meetingID)/weather")
        let envelope = try JSONDecoder().decode(PitPulseForecastEnvelope.self, from: data)
        return (envelope.data, envelope.meta.stale)
    }
}
