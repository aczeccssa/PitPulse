import AppKit
import SwiftUI
import SharedData

extension MeetingDetailView {
    var overview: some View {
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

    func overviewSessionRow(_ session: Session, isLast: Bool) -> some View {
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

    var weatherSummaryCard: some View {
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

    func miniCondition(label: String, value: String) -> some View {
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

    var circuitCard: some View {
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

    func circuitFact(label: String, value: String) -> some View {
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
}
