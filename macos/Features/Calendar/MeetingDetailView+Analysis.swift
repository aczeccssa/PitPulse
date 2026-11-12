import AppKit
import SwiftUI
import SharedData

extension MeetingDetailView {
    var analysis: some View {
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

    var nextSessionForecastHour: PitPulseForecastHour? {
        guard let forecast,
              let next = CalendarLogic.nextSession(in: [meeting], now: Date()) else { return nil }
        return hour(for: next.session, in: forecast)
    }

    func hour(for session: Session, in forecast: PitPulseForecast) -> PitPulseForecastHour? {
        guard let hour = forecast.hours.min(by: {
            abs($0.time - session.startTime.timeIntervalSince1970) < abs($1.time - session.startTime.timeIntervalSince1970)
        }) else { return nil }
        return abs(hour.time - session.startTime.timeIntervalSince1970) <= 3_600 ? hour : nil
    }

    enum SessionState {
        case finished, running, upcoming, cancelled
    }

    func sessionState(_ session: Session) -> SessionState {
        if session.status == .cancelled || session.status == .postponed { return .cancelled }
        let end = session.endTime ?? session.startTime.addingTimeInterval(7_200)
        if session.status == .live || (Date() >= session.startTime && Date() < end) { return .running }
        if session.status == .finished || Date() >= end { return .finished }
        return .upcoming
    }

    func sessionStateLabel(_ state: SessionState) -> String {
        switch state {
        case .finished: "已结束"
        case .running: "进行中"
        case .upcoming: "未开始"
        case .cancelled: "取消"
        }
    }
}
