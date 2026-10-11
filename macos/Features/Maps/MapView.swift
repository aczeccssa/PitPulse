import AppKit
import SwiftUI
@preconcurrency import WebKit

@MainActor
final class MapStore: ObservableObject {
    @Published var error: String?
    @Published var publicToken: String?
    private(set) var webView: WKWebView?
    private var handler: MapHandler?
    private var serverAddress: String?
    private var geometry: [String: Any]?
    private var geometryID: String?
    private var layoutVerified = false
    private var payloadJSON: String?
    private var radarFrame: Int?
    fileprivate var camera: [String: Any]?
    private var generation = 0
    weak var model: AppModel?
    var onDriver: ((String) -> Void)?
    var onMeeting: ((String) -> Void)?

    func load(model: AppModel, meeting: Meeting?) async {
        let changedServer = serverAddress != model.serverAddress
        if changedServer { release(); serverAddress = model.serverAddress }
        self.model = model
        let requestGeneration = generation
        if changedServer || publicToken == nil {
            do {
                let data = try await model.mapData(path: "/api/v1/maps/config")
                guard !Task.isCancelled, requestGeneration == generation else { return }
                let config = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                publicToken = (config?["data"] as? [String: Any])?["publicToken"] as? String
                error = publicToken == nil ? "未配置 Mapbox 公开 token" : nil
            } catch { if !Task.isCancelled && requestGeneration == generation { self.error = error.localizedDescription } }
        }
        if let meeting, geometryID != meeting.id {
            geometryID = meeting.id
            geometry = nil
            layoutVerified = false
            do {
                let raw = try await model.mapData(path: "/api/v1/meetings/\(meeting.id)/geometry")
                guard !Task.isCancelled, requestGeneration == generation, geometryID == meeting.id else { return }
                let root = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
                geometry = ((root?["data"] as? [String: Any])?["geometry"] as? [String: Any])
                layoutVerified = (root?["data"] as? [String: Any])?["layoutVerified"] as? Bool == true
            } catch { if !Task.isCancelled && requestGeneration == generation && geometryID == meeting.id { self.error = error.localizedDescription } }
        }
    }

    func view() -> WKWebView {
        if let webView { return webView }
        let handler = MapHandler(owner: self)
        self.handler = handler
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(handler, forURLScheme: "pitpulse-radar")
        config.userContentController.add(handler, name: "map")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = handler
        web.setValue(false, forKey: "drawsBackground")
        self.webView = web
        if let url = Bundle.main.url(forResource: "map", withExtension: "html") {
            do {
                // WebKit file-origin workers cannot decode Mapbox terrain/model image blobs.
                web.loadHTMLString(try String(contentsOf: url, encoding: .utf8), baseURL: nil)
            } catch { self.error = "地图资源读取失败" }
        } else { error = "地图资源缺失" }
        return web
    }

    func update(meeting: Meeting?, meetings: [Meeting], snapshot: LiveSnapshot?, selected: String?, radar: Bool, active: Bool) {
        guard let webView else { return }
        guard active else { webView.isHidden = true; webView.evaluateJavaScript("window.pauseMap && window.pauseMap()"); return }
        webView.isHidden = false
        let point = meeting?.circuit
        let markers: [[String: Any]] = meetings.compactMap { meeting in
            guard let c = meeting.circuit else { return nil }
            return ["id": meeting.id, "name": meeting.name, "round": meeting.round.map(String.init) ?? "•", "longitude": c.longitude, "latitude": c.latitude]
        }
        let locations: [[String: Any]] = (snapshot?.drivers ?? []).compactMap { driver in
            guard snapshot?.sourceStatus == .connected, let p = driver.location,
                  snapshot?.sourceMode == .replay || LiveFreshness.isFresh(p.utc), let lon = p.longitude, let lat = p.latitude else { return nil }
            return ["number": driver.number, "label": MotorsportAsset.abbreviation(driver.name ?? driver.number), "color": driver.teamColorHex, "utc": p.utc, "longitude": lon, "latitude": lat]
        }
        let status = radar ? "历史降雨雷达 · 黑色区域无覆盖" : snapshot == nil ? geometry != nil && !layoutVerified ? "赛道轮廓当前年份尚待核验" : "" : snapshot?.sourceStatus != .connected ? "\(snapshot?.statusLabel ?? "已断开") · 位置未更新" : locations.isEmpty ? "车辆定位未校准或暂无新位置" : ""
        let payload: [String: Any] = ["publicToken": publicToken ?? "", "center": [point?.longitude ?? markers.first?["longitude"] as? Double ?? 0, point?.latitude ?? markers.first?["latitude"] as? Double ?? 20], "zoom": radar ? 8 : meetings.isEmpty ? 15.5 : 1.5, "pitch": meetings.isEmpty && !radar ? 55 : 0, "cameraKey": "\(meeting?.id ?? "season")-\(radar)", "camera": camera as Any? ?? NSNull(), "geometry": geometry as Any? ?? NSNull(), "drivers": locations, "selected": selected ?? "", "meetings": markers, "status": status, "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion]
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        payloadJSON = json
        applyPayload()
    }

    func applyPayload() {
        guard let payloadJSON else { return }
        webView?.evaluateJavaScript("window.updateMap && window.updateMap(\(payloadJSON))")
        webView?.evaluateJavaScript("window.setRadar && window.setRadar(\(radarFrame.map(String.init) ?? "null"))")
    }

    func radar(frame: Int?) {
        radarFrame = frame
        webView?.evaluateJavaScript("window.setRadar && window.setRadar(\(frame.map(String.init) ?? "null"))")
    }

    func pause() {
        handler?.cancel()
        webView?.isHidden = true
        webView?.evaluateJavaScript("window.pauseMap && window.pauseMap()")
    }

    func release(preserveCamera: Bool = false) {
        generation += 1
        model = nil
        handler?.cancel()
        webView?.evaluateJavaScript("window.disposeMap && window.disposeMap()")
        webView?.removeFromSuperview()
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "map")
        webView = nil
        handler = nil
        publicToken = nil
        geometry = nil
        layoutVerified = false
        geometryID = nil
        payloadJSON = nil
        radarFrame = nil
        if !preserveCamera { camera = nil; serverAddress = nil }
        onDriver = nil
        onMeeting = nil
    }
}

@MainActor
private final class MapHandler: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKURLSchemeHandler {
    weak var owner: MapStore?
    var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    init(owner: MapStore) { self.owner = owner }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === owner?.webView,
              let body = message.body as? [String: Any] else { return }
        if body["type"] as? String == "camera", let camera = body["value"] as? [String: Any],
           let center = camera["center"] as? [Double], center.count == 2,
           (-180...180).contains(center[0]), (-90...90).contains(center[1]),
           let zoom = camera["zoom"] as? Double, (0...22).contains(zoom),
           let pitch = camera["pitch"] as? Double, (0...85).contains(pitch),
           let bearing = camera["bearing"] as? Double, bearing.isFinite {
            owner?.camera = camera
            return
        }
        guard let value = body["value"] as? String else { return }
        if body["type"] as? String == "error" { owner?.error = value }
        if body["type"] as? String == "driver" { owner?.onDriver?(value) }
        if body["type"] as? String == "meeting" { owner?.onMeeting?(value) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { owner?.applyPayload() }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" && action.navigationType == .other { decisionHandler(.allow) } else {
            decisionHandler(.cancel)
            if url.scheme == "https", ["www.mapbox.com", "www.openstreetmap.org", "apps.mapbox.com", "www.rainviewer.com"].contains(url.host ?? ""), action.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
        }
    }
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        guard let url = urlSchemeTask.request.url, ["radar", "coverage"].contains(url.host ?? ""),
              url.pathComponents.count == 5, url.pathComponents.dropFirst().allSatisfy({ Int($0) != nil }), let model = owner?.model else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        let path = "/api/v1/weather/tiles/\(url.host!)\(url.path)"
        tasks[id] = Task { [weak self] in
            do {
                let data = try await model.mapData(path: path)
                try Task.checkCancellation()
                urlSchemeTask.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png", "Access-Control-Allow-Origin": "*"])!)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                if !Task.isCancelled { urlSchemeTask.didFailWithError(error); self?.owner?.error = "雷达图层不可用，可稍后重试" }
            }
            self?.tasks.removeValue(forKey: id)
        }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) { tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel() }
    func cancel() { tasks.values.forEach { $0.cancel() }; tasks.removeAll() }
}

struct MapView: NSViewRepresentable {
    @ObservedObject var store: MapStore
    var meeting: Meeting? = nil
    var meetings: [Meeting] = []
    var snapshot: LiveSnapshot? = nil
    var selected: String? = nil
    var radar = false
    var active = true
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
        store.update(meeting: meeting, meetings: meetings, snapshot: snapshot, selected: selected, radar: radar, active: active)
    }
}

struct MeetingMapView: View {
    @EnvironmentObject var model: AppModel
    let meeting: Meeting
    @StateObject private var map = MapStore()
    @State private var forecast: [ForecastHour] = []
    @State private var weatherStatus = "正在读取预报…"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if meeting.circuit != nil {
                MapView(store: map, meeting: meeting).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 10))
                if let error = map.error { Text(error).font(.caption).foregroundStyle(.secondary) }
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
            await map.load(model: model, meeting: meeting)
            forecast = []
            do {
                let data = try await model.mapData(path: "/api/v1/meetings/\(meeting.id)/weather")
                let envelope = try JSONDecoder().decode(ForecastEnvelope.self, from: data)
                try Task.checkCancellation()
                forecast = envelope.data.hours
                weatherStatus = envelope.data.status == "available" ? "Open-Meteo 预报\(envelope.meta.stale ? " · 已过期" : "")" : envelope.data.status == "past_event" ? "已结束赛事不提供当前天气预报" : "尚无比赛日期预报"
            } catch { if !Task.isCancelled { weatherStatus = "天气暂不可用：\(error.localizedDescription)" } }
        }
        .onDisappear { map.release() }
    }
}
private struct ForecastEnvelope: Decodable { let data: ForecastData; let meta: ForecastMeta }
private struct ForecastMeta: Decodable { let stale: Bool }
private struct ForecastData: Decodable { let status: String; let hours: [ForecastHour] }
private struct ForecastHour: Decodable {
    let utc: String
    var time: Double { RFC3339.parse(utc)?.timeIntervalSince1970 ?? .greatestFiniteMagnitude }
    let temperature: Double?
    let probability: Double?
    enum CodingKeys: String, CodingKey { case utc, temperature = "airTemp", probability = "precipitationProbability" }
}
