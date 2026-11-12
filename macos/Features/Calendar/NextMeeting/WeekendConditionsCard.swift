import AppKit
import SwiftUI
import SharedData

struct WeekendConditionsCard: View {
    @EnvironmentObject var model: AppModel
    let meeting: Meeting
    let now: Date

    @State var forecast: PitPulseForecast?
    @State var statusText = "正在读取预报…"
    @State var showingMap = false

    var targetHour: PitPulseForecastHour? {
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

struct ConditionTile: View {
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
