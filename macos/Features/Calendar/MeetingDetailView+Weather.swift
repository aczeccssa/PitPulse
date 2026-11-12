import AppKit
import SwiftUI
import SharedData

extension MeetingDetailView {
    var weather: some View {
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

    func weatherMetric(symbol: String, text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(minWidth: 26, alignment: .trailing)
        }
    }

    // MARK: Analysis
}
