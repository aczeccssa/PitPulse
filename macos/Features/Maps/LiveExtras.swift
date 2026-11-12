import AVFoundation
import Combine
import SwiftUI
import SharedData

@MainActor
final class RadioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingID: String?
    @Published private(set) var loadingID: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var error: String?
    private var player: AVAudioPlayer?
    private var file: URL?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var timer: AnyCancellable?
    func toggle(_ radio: LiveRadio, sessionID: String, model: AppModel) {
        if playingID == radio.id, let player {
            if player.isPlaying { player.pause() } else { player.play() }
            objectWillChange.send()
            return
        }
        stop()
        error = nil
        loadingID = radio.id
        let current = generation
        task = Task { [weak self] in
            do {
                let data = try await model.mapData(path: "/api/v1/live/radio/\(sessionID)/\(radio.id)")
                try Task.checkCancellation()
                guard let self, current == self.generation else { return }
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("pitpulse-radio-\(UUID().uuidString).mp3")
                self.file = file
                try data.write(to: file, options: .atomic)
                let player = try AVAudioPlayer(contentsOf: file)
                player.delegate = self
                self.player = player
                guard player.play() else { throw URLError(.cannotDecodeContentData) }
                self.playingID = radio.id
                self.loadingID = nil
                self.timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                    guard let self, let player = self.player else { return }
                    self.progress = player.duration > 0 ? player.currentTime / player.duration : 0
                }
            } catch {
                guard let self, current == self.generation, !Task.isCancelled else { return }
                self.stop()
                self.error = "音频播放失败，可点击重试：\(error.localizedDescription)"
            }
        }
    }
    var isPlaying: Bool { player?.isPlaying == true }
    func stop() {
        generation += 1
        task?.cancel(); task = nil
        timer?.cancel(); timer = nil
        player?.delegate = nil; player?.stop(); player = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil; playingID = nil; loadingID = nil; progress = 0
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.player.map(ObjectIdentifier.init) == identity else { return }
            self.stop()
        }
    }
}

struct LiveTelemetryView: View {
    let driver: LiveDriver?
    let snapshot: LiveSnapshot
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let driver, let data = driver.telemetry,
               snapshot.sourceStatus == .connected,
               snapshot.sourceMode == .replay || LiveFreshness.isFresh(data.receivedAt ?? data.utc, now: context.date) {
                HStack(spacing: 16) {
                    metric("速度", data.speed, "km/h")
                    metric("RPM", data.rpm, "")
                    metric("挡位", data.gear, "")
                    metric("油门", data.throttle, "%")
                    metric("刹车", data.brake, "")
                    metric("DRS", data.drs, "")
                    Spacer(minLength: 0)
                }
                .padding(8).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            } else { Text(driver == nil ? "No selected" : "车辆遥测未提供或已过期").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func metric(_ label: String, _ value: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(label).foregroundStyle(.secondary); Text(value.map { String(format: "%.0f", $0) + unit } ?? "—").monospacedDigit() }.font(.caption2)
    }
}

struct LiveWeatherView: View {
    let snapshot: LiveSnapshot
    @State private var details = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let w = snapshot.weather, snapshot.sourceStatus == .connected,
               snapshot.sourceMode == .replay || LiveFreshness.isFresh(w.utc, now: context.date, maximumAge: 120) {
                Button { details.toggle() } label: {
                    HStack(spacing: 8) {
                        Label(format(w.airTemp, "°"), systemImage: "thermometer.medium")
                        Label(format(w.trackTemp, "°"), systemImage: "road.lanes")
                        Image(systemName: w.rainfall == true ? "cloud.rain.fill" : "cloud.sun")
                    }.font(.caption2).foregroundStyle(.secondary).fixedSize()
                }.buttonStyle(.plain).help("赛道天气详情")
                    .accessibilityLabel("气温 \(format(w.airTemp, "°C"))，赛道 \(format(w.trackTemp, "°C"))，点击查看天气详情")
                    .popover(isPresented: $details) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(snapshot.sourceMode == .replay ? "模拟赛道天气" : "赛道天气").font(.headline)
                            Text("气温 \(format(w.airTemp, "°C")) · 赛道 \(format(w.trackTemp, "°C"))")
                            Text("湿度 \(format(w.humidity, "%")) · 气压 \(format(w.pressure, "hPa"))")
                            Text("风速 \(format(w.windSpeed, "m/s")) · 风向 \(format(w.windDirection, "°"))")
                            Text(w.rainfall.map { $0 ? "有降雨" : "未检测降雨" } ?? "降雨未知")
                        }.font(.caption).padding(16)
                    }
            } else {
                Image(systemName: "cloud.slash").foregroundStyle(.secondary)
                    .help("赛道天气未提供或已过期").accessibilityLabel("赛道天气未提供或已过期")
            }
        }
    }
    private func format(_ value: Double?, _ unit: String) -> String { value.map { String(format: "%.1f", $0) + unit } ?? "—" }
}

struct LiveMessagesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: RadioPlayer
    let snapshot: LiveSnapshot
    let selected: String?
    @Binding var page: String
    @Binding var filter: String
    @Binding var expanded: Bool
    private var driverLabel: String {
        guard let selected else { return "车手" }
        let name = snapshot.drivers.first { $0.number == selected }?.name.map(MotorsportAsset.abbreviation) ?? ""
        return "#\(selected) \(name)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                messageTab("Race Control", label: "赛会消息", count: snapshot.raceControl?.count ?? 0)
                messageTab("Team Radio", label: "车队语音", count: snapshot.teamRadio?.count ?? 0)
                Spacer()
                Button { expanded.toggle() } label: {
                    Label(expanded ? "收起详情" : "展开详情", systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }.buttonStyle(.borderless)
                    .accessibilityIdentifier("liveIsland.messages.toggle")
                    .accessibilityValue(expanded ? "展开" : "收起")
                if expanded { Menu {
                    Button("全部消息") { filter = "all" }
                    Button("仅 \(driverLabel)") { filter = "driver" }.disabled(selected == nil)
                } label: {
                    Label(filter == "driver" ? "仅 \(driverLabel)" : "全部消息", systemImage: "line.3.horizontal.decrease")
                        .font(.caption2)
                }.menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("消息筛选：\(filter == "driver" ? driverLabel : "全部消息")")
                }
            }
            if expanded { ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if page == "Race Control" {
                        let messages = (snapshot.raceControl ?? []).filter { filter != "driver" || $0.concernsDriver(selected) }
                            .sorted { ($0.utc ?? "") > ($1.utc ?? "") }
                        if messages.isEmpty { emptyMessage("暂无赛会消息") }
                        let rows = Array(messages.enumerated()).map { (id: $0.element.id ?? "legacy-\($0.offset)", item: $0.element) }
                        ForEach(rows, id: \.id) { row in
                            let item = row.item
                            HStack(alignment: .top, spacing: 8) {
                                Text(time(item.utc)).monospacedDigit().foregroundStyle(.secondary).frame(width: 60)
                                if let lap = item.lap { Text("L\(lap)").foregroundStyle(.secondary) }
                                if let number = item.driverNumber { Text("#\(number)").foregroundStyle(.secondary) }
                                Text(item.message ?? [item.flag, item.category].compactMap { $0 }.joined(separator: " · "))
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }.font(.caption2)
                        }
                    } else {
                        let radios = (snapshot.teamRadio ?? []).filter { filter != "driver" || $0.driverNumber == selected }.sorted { $0.utc > $1.utc }
                        if radios.isEmpty {
                            emptyMessage(snapshot.sourceMode == .replay ? "此 Mock 未提供车队语音；真实场次收到音频后可手动播放" : "尚未收到车队语音")
                        }
                        ForEach(radios) { radio in
                            HStack {
                                Text(time(radio.utc)).monospacedDigit().foregroundStyle(.secondary)
                                Text("#\(radio.driverNumber) \(snapshot.drivers.first { $0.number == radio.driverNumber }?.name ?? "")")
                                Spacer()
                                if player.loadingID == radio.id { ProgressView().controlSize(.small) }
                                Button {
                                    guard let sessionID = snapshot.sessionId else { return }
                                    player.toggle(radio, sessionID: sessionID, model: model)
                                } label: { Image(systemName: player.playingID == radio.id && player.isPlaying ? "pause.fill" : "play.fill") }
                                    .buttonStyle(.borderless).disabled(snapshot.sessionId == nil)
                                    .accessibilityLabel("\(player.playingID == radio.id && player.isPlaying ? "暂停" : "播放")车手 \(radio.driverNumber) 的 Team Radio")
                                if player.playingID == radio.id { ProgressView(value: player.progress).frame(width: 90) }
                            }.font(.caption)
                        }
                        if let error = player.error { Text(error).font(.caption2).foregroundStyle(.orange) }
                    }
                }
            }.frame(height: 60) }
        }
        .onChange(of: page) { _, _ in player.stop() }
        .onChange(of: expanded) { _, open in if !open { player.stop() } }
        .onDisappear { player.stop() }
        .onChange(of: snapshot.sessionId) { _, _ in player.stop() }
        .onChange(of: model.serverAddress) { _, _ in player.stop() }
    }
    private func messageTab(_ value: String, label: String, count: Int) -> some View {
        Button { page = value } label: {
            Text("\(label) \(count)").font(.caption.weight(page == value ? .semibold : .regular))
                .foregroundStyle(page == value ? Color.white : Color.secondary)
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) { if page == value { Capsule().fill(.white.opacity(0.8)).frame(height: 2) } }
        }.buttonStyle(.plain).accessibilityLabel("\(label)，\(count)条")
            .accessibilityAddTraits(page == value ? .isSelected : [])
    }
    private func emptyMessage(_ text: String) -> some View {
        HStack {
            Text(filter == "driver" ? "没有与 \(driverLabel) 相关的消息" : text).font(.caption2).foregroundStyle(.secondary)
            if filter == "driver" { Button("显示全部") { filter = "all" }.font(.caption2).buttonStyle(.borderless) }
        }
    }
    private func time(_ utc: String?) -> String { utc.flatMap(RFC3339.parse).map { $0.formatted(.dateTime.hour().minute().second()) } ?? "—" }
}

struct RadarControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var map: MapStore
    @State private var frames: [Int] = []
    @State private var selected = 0.0
    @State private var playing = false
    @State private var status = "正在读取降雨雷达…"
    var body: some View {
        HStack {
            Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }.buttonStyle(.borderless).disabled(frames.isEmpty).accessibilityLabel("播放或暂停历史降雨雷达")
            if frames.count > 1 { Slider(value: $selected, in: 0...Double(frames.count-1), step: 1).accessibilityLabel("选择雷达时间") }
            Text(status + " · " + (frames.indices.contains(Int(selected)) ? Date(timeIntervalSince1970: Double(frames[Int(selected)])).formatted(.dateTime.hour().minute()) : "—")).font(.caption2)
            Link("RainViewer", destination: URL(string: "https://www.rainviewer.com/")!).font(.caption2)
        }
        .task(id: model.serverAddress) {
            frames = []; selected = 0; playing = false
            map.radar(frame: nil)
            while !Task.isCancelled {
                do {
                    let data = try await model.mapData(path: "/api/v1/weather/radar")
                    let result = try JSONDecoder().decode(RadarEnvelope.self, from: data)
                    try Task.checkCancellation()
                    frames = result.data.frames.map(\.id).sorted()
                    selected = Double(max(0, frames.count-1))
                    status = frames.isEmpty ? "暂无雷达帧" : result.meta.stale ? "雷达缓存已过期" : "历史降雨雷达"
                    map.radar(frame: frames.last)
                } catch {
                    guard !Task.isCancelled else { return }
                    frames = []; selected = 0; playing = false
                    status = "雷达暂不可用"; map.radar(frame: nil)
                }
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
            }
        }
        .onChange(of: selected) { _, new in if frames.indices.contains(Int(new)) { map.radar(frame: frames[Int(new)]) } }
        .onReceive(Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()) { _ in if playing && !frames.isEmpty { selected = Double((Int(selected)+1) % frames.count) } }
        .onDisappear { playing = false; map.radar(frame: nil) }
    }
}
private struct RadarEnvelope: Decodable { let data: RadarData; let meta: RadarMeta }
private struct RadarMeta: Decodable { let stale: Bool }
private struct RadarData: Decodable { let frames: [RadarFrame] }
private struct RadarFrame: Decodable { let id: Int; let utc: String }
