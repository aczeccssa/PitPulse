import AppKit
import SwiftUI
import SharedData

struct MapView: NSViewRepresentable {
    @ObservedObject var store: MapStore
    var meeting: Meeting? = nil
    var meetings: [Meeting] = []
    var snapshot: LiveSnapshot? = nil
    var selected: String? = nil
    var radar = false
    var active = true
    var now = Date()
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ container: NSView, context: Context) {
        guard active else { store.pause(); return }
        let web = store.view()
        if web.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            web.frame = container.bounds
            web.autoresizingMask = [.width, .height]
            container.addSubview(web)
        }
        store.update(meeting: meeting, meetings: meetings, snapshot: snapshot, selected: selected, radar: radar, active: active, now: now)
    }
}

struct MeetingMapView: View {
    @EnvironmentObject var model: AppModel
    let meeting: Meeting
    @State private var mapExpanded = false
    @State private var forecast: [ForecastHour] = []
    @State private var weatherStatus = "正在读取预报…"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if meeting.circuit != nil {
                if mapExpanded {
                    MapView(store: model.mapStore, meeting: meeting).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 10))
                    Button("收起地图") { mapExpanded = false; model.mapStore.pause() }.font(.caption)
                    if let error = model.mapStore.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                } else {
                    Button {
                        mapExpanded = true
                        Task { await model.mapStore.load(model: model, meeting: meeting) }
                    } label: {
                        Label("打开赛道地图 · \(meeting.circuit?.name ?? meeting.location)", systemImage: "map")
                            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            } else { Text("暂无赛道地点坐标").font(.caption).foregroundStyle(.secondary) }
            Text(weatherStatus).font(.caption).foregroundStyle(.secondary)
            ForEach(meeting.sessions) { session in
                if let hour = forecast.min(by: { abs($0.time - session.startTime.timeIntervalSince1970) < abs($1.time - session.startTime.timeIntervalSince1970) }), abs(hour.time-session.startTime.timeIntervalSince1970) <= 3600, (session.endTime ?? session.startTime.addingTimeInterval(7200)) >= Date() {
                    HStack { Text(session.sessionType.displayName); Spacer(); Text("\(hour.temperature.map { String(format: "%.0f°C", $0) } ?? "—") · 降雨 \(hour.probability.map { String(format: "%.0f%%", $0) } ?? "—")") }.font(.caption)
                } else {
                    HStack { Text(session.sessionType.displayName); Spacer(); Text((session.endTime ?? session.startTime.addingTimeInterval(7200)) < Date() ? "已结束 · 无历史天气" : "尚无预报") }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: "\(meeting.id)-\(model.serverAddress)") {
            forecast = []
            do {
                let data = try await model.mapData(path: "/api/v1/meetings/\(meeting.id)/weather")
                let envelope = try JSONDecoder().decode(ForecastEnvelope.self, from: data)
                try Task.checkCancellation()
                forecast = envelope.data.hours
                weatherStatus = envelope.data.status == "available" ? "Open-Meteo 预报\(envelope.meta.stale ? " · 已过期" : "")" : envelope.data.status == "past_event" ? "已结束赛事不提供当前天气预报" : "尚无比赛日期预报"
            } catch { if !Task.isCancelled { weatherStatus = "天气暂不可用：\(error.localizedDescription)" } }
        }
        .onDisappear { model.mapStore.pause() }
    }
}
