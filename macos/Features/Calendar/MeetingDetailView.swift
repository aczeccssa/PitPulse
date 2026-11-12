import SwiftUI
import SharedData

struct MeetingDetailView: View {
    enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "概览"
        case weekend = "周末"
        case weather = "天气"
        case analysis = "分析"

        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    let meeting: Meeting
    @State private var tab: DetailTab = .overview
    @State private var forecast: PitPulseForecast?
    @State private var forecastStatus = "正在读取预报…"
    @State private var mapExpanded = false

    private var sortedSessions: [Session] {
        meeting.sessions.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            subTabs
            ScrollView {
                Group {
                    switch tab {
                    case .overview: overview
                    case .weekend: weekend
                    case .weather: weather
                    case .analysis: analysis
                    }
                }
                .padding(.horizontal, PitPulseTheme.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(CalendarScrollAppearance())
            }
        }
        .task(id: "\(meeting.id)-\(model.serverAddress)") {
            forecast = nil
            forecastStatus = "正在读取预报…"
            do {
                let result = try await MeetingForecast.load(meetingID: meeting.id, model: model)
                try Task.checkCancellation()
                forecast = result.forecast
                forecastStatus = result.stale ? "\(result.forecast.statusText) · 已过期" : result.forecast.statusText
            } catch is CancellationError {
                return
            } catch {
                forecastStatus = "天气暂不可用：\(error.localizedDescription)"
            }
        }
        .onDisappear { model.mapStore.pause() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            Text(CountryFlag.display(country: meeting.country, code: meeting.countryCode))
                .font(.system(size: 20))
                .accessibilityLabel("举办国 \(meeting.country)")

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.name)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.2)
                    .lineLimit(1)
                Text("\(meeting.circuit?.name ?? meeting.location) · \(meeting.location)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("第 \(meeting.round.map(String.init) ?? "—") 站")
                    Text("·")
                    Text("\(meeting.startDate.formatted(.dateTime.month().day())) – \(meeting.endDate.formatted(.dateTime.month().day()))")
                        .monospacedDigit()
                    Text("·")
                    Text(meeting.status.displayName)
                        .foregroundStyle(meeting.status == .scheduled ? Color.secondary : Color.orange)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(meeting.season))
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text("R\(meeting.round.map(String.init) ?? "—")")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.bottom, 10)
    }

    private var subTabs: some View {
        LiquidSegmented(
            items: DetailTab.allCases.map { .init(value: $0, title: $0.rawValue) },
            selection: $tab
        )
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.bottom, 2)
    }

    // MARK: Overview

    private var overview: some View {
        VStack(spacing: PitPulseTheme.cardSpacing) {
            HStack(alignment: .top, spacing: 10) {
                GlassCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        CardHeader(title: "周末赛程")
                        if sortedSessions.isEmpty {
                            Text("暂无 Session 数据。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(sortedSessions.enumerated()), id: \.element.id) { index, session in
                                    overviewSessionRow(session, isLast: index == sortedSessions.count - 1)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                weatherSummaryCard
                    .frame(width: 204)
            }

            circuitCard

            if mapExpanded, meeting.circuit != nil {
                MapView(store: model.mapStore, meeting: meeting)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func overviewSessionRow(_ session: Session, isLast: Bool) -> some View {
        let state = sessionState(session)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(state == .running ? PitPulseTheme.accent : (state == .finished ? PitPulseTheme.accent.opacity(0.55) : Color.secondary.opacity(0.35)))
                    .frame(width: 6, height: 6)
                Text(session.sessionType.displayName)
                    .font(.system(size: 12.5, weight: state == .upcoming ? .semibold : .medium))
                    .foregroundStyle(state == .finished ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(session.startTime.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(sessionStateLabel(state))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(state == .running ? PitPulseTheme.accent : Color.secondary.opacity(0.75))
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.vertical, 8)
            if !isLast {
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var weatherSummaryCard: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                CardHeader(title: "下一节天气")
                if let hour = nextSessionForecastHour {
                    HStack(spacing: 6) {
                        Image(systemName: "cloud.sun.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.orange)
                        Text(hour.conditionText)
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                    }
                    miniCondition(label: "气温", value: hour.airTemp.map { String(format: "%.0f°C", $0) } ?? "未提供")
                    miniCondition(label: "降雨", value: hour.precipitationProbability.map { String(format: "%.0f%%", $0) } ?? "未提供")
                    miniCondition(label: "风速", value: hour.windSpeed.map { String(format: "%.1f m/s", $0) } ?? "未提供")
                } else {
                    Text(forecastStatus)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text("Open-Meteo · 仅显示端点返回的预报")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func miniCondition(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var circuitCard: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                CardHeader(
                    title: "赛道",
                    actionTitle: meeting.circuit == nil ? nil : (mapExpanded ? "收起地图" : "查看地图"),
                    actionSymbol: "map"
                ) {
                    mapExpanded.toggle()
                    if mapExpanded {
                        Task { await model.mapStore.load(model: model, meeting: meeting) }
                    } else {
                        model.mapStore.pause()
                    }
                }
                HStack(alignment: .top, spacing: 14) {
                    circuitFact(label: "赛道", value: meeting.circuit?.name ?? "未提供")
                    circuitFact(label: "地点", value: meeting.location)
                    circuitFact(label: "国家", value: meeting.country)
                    circuitFact(label: "Session", value: "\(meeting.sessions.count) 节")
                }
                if let circuit = meeting.circuit {
                    Text(String(format: "%.4f, %.4f", circuit.latitude, circuit.longitude))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("后端未提供赛道坐标，因此不显示赛道长度、弯道数与地图轮廓。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                if mapExpanded, let error = model.mapStore.error {
                    Text(error).font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    private func circuitFact(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Weekend

    private var weekend: some View {
        VStack(spacing: PitPulseTheme.cardSpacing) {
            ForEach(sessionDays, id: \.day) { group in
                GlassCard(padding: 13) {
                    VStack(alignment: .leading, spacing: 8) {
                        CardHeader(title: group.day.formatted(.dateTime.weekday(.wide).month().day()))
                        ForEach(Array(group.sessions.enumerated()), id: \.element.id) { index, session in
                            let state = sessionState(session)
                            VStack(spacing: 0) {
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(state == .running ? PitPulseTheme.accent : Color.primary.opacity(0.12))
                                        .frame(width: 3, height: 26)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.sessionType.displayName)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(sessionTimeRange(session))
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 6)
                                    Text(sessionStateLabel(state))
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(state == .running ? PitPulseTheme.accent : Color.secondary)
                                }
                                .padding(.vertical, 7)
                                if index != group.sessions.count - 1 {
                                    Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                                }
                            }
                        }
                    }
                }
            }
            if sortedSessions.isEmpty {
                EmptyStateCard(symbol: "calendar.badge.clock", title: "周末赛程未提供", message: "服务器返回的分站数据中没有 Session。")
            }
        }
    }

    private var sessionDays: [(day: Date, sessions: [Session])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sortedSessions) { calendar.startOfDay(for: $0.startTime) }
        return grouped.keys.sorted().map { ($0, grouped[$0]!.sorted { $0.startTime < $1.startTime }) }
    }

    private func sessionTimeRange(_ session: Session) -> String {
        let start = session.startTime.formatted(.dateTime.hour().minute())
        guard let end = session.endTime else { return start }
        return "\(start) – \(end.formatted(.dateTime.hour().minute()))"
    }

    // MARK: Weather

    private var weather: some View {
        VStack(spacing: PitPulseTheme.cardSpacing) {
            GlassCard(padding: 13) {
                VStack(alignment: .leading, spacing: 8) {
                    CardHeader(title: "逐节预报")
                    HStack {
                        Text(forecastStatus)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("本地时间").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    }
                    if let forecast, forecast.status == "available" {
                        ForEach(Array(sortedSessions.enumerated()), id: \.element.id) { index, session in
                            if let hour = hour(for: session, in: forecast) {
                                VStack(spacing: 0) {
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(session.sessionType.displayName)
                                                .font(.system(size: 12.5, weight: .semibold))
                                            Text(session.startTime.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 6)
                                        weatherMetric(symbol: "thermometer.medium", text: hour.airTemp.map { String(format: "%.0f°", $0) } ?? "—", tint: .orange)
                                        weatherMetric(symbol: "drop.fill", text: hour.precipitationProbability.map { String(format: "%.0f%%", $0) } ?? "—", tint: .blue)
                                        weatherMetric(symbol: "wind", text: hour.windSpeed.map { String(format: "%.0f", $0) } ?? "—", tint: .teal)
                                        Text(hour.conditionText)
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 46, alignment: .trailing)
                                    }
                                    .padding(.vertical, 8)
                                    if index != sortedSessions.count - 1 {
                                        Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                                    }
                                }
                            } else {
                                HStack {
                                    Text(session.sessionType.displayName).font(.system(size: 12.5, weight: .medium))
                                    Spacer()
                                    Text("尚无预报").font(.system(size: 11)).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    } else {
                        Text(forecast == nil ? "正在读取预报…" : "该分站没有可用的比赛日预报。")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                    }
                }
            }
            if let error = model.mapStore.error {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    private func weatherMetric(symbol: String, text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(minWidth: 26, alignment: .trailing)
        }
    }

    // MARK: Analysis

    private var analysis: some View {
        VStack(spacing: PitPulseTheme.cardSpacing) {
            GlassCard(padding: 13) {
                VStack(alignment: .leading, spacing: 8) {
                    CardHeader(title: "Race Control")
                    let messages = Array((model.liveStore.snapshot.raceControl ?? []).suffix(6).reversed())
                    if messages.isEmpty {
                        Text("当前没有实时 Race Control 消息。")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            HStack(alignment: .top, spacing: 8) {
                                Text(message.lap.map { "L\($0)" } ?? "—")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(PitPulseTheme.accent)
                                    .frame(width: 26, alignment: .leading)
                                Text(message.message ?? "（无内容）")
                                    .font(.system(size: 12))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5)
                            if index != messages.count - 1 {
                                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                            }
                        }
                    }
                }
            }
            GlassCard(padding: 13) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(PitPulseTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("赛后分析")
                            .font(.system(size: 13, weight: .semibold))
                        Text("圈速、分段、策略与遥测在「成绩」标签页的 Session 详情中查看。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Helpers

    private var nextSessionForecastHour: PitPulseForecastHour? {
        guard let forecast,
              let next = CalendarLogic.nextSession(in: [meeting], now: Date()) else { return nil }
        return hour(for: next.session, in: forecast)
    }

    private func hour(for session: Session, in forecast: PitPulseForecast) -> PitPulseForecastHour? {
        guard let hour = forecast.hours.min(by: {
            abs($0.time - session.startTime.timeIntervalSince1970) < abs($1.time - session.startTime.timeIntervalSince1970)
        }) else { return nil }
        return abs(hour.time - session.startTime.timeIntervalSince1970) <= 3_600 ? hour : nil
    }

    private enum SessionState {
        case finished, running, upcoming, cancelled
    }

    private func sessionState(_ session: Session) -> SessionState {
        if session.status == .cancelled || session.status == .postponed { return .cancelled }
        let end = session.endTime ?? session.startTime.addingTimeInterval(7_200)
        if session.status == .live || (Date() >= session.startTime && Date() < end) { return .running }
        if session.status == .finished || Date() >= end { return .finished }
        return .upcoming
    }

    private func sessionStateLabel(_ state: SessionState) -> String {
        switch state {
        case .finished: "已结束"
        case .running: "进行中"
        case .upcoming: "未开始"
        case .cancelled: "取消"
        }
    }
}
