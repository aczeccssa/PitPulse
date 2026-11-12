import AppKit
import SwiftUI
import SharedData

struct LiveIslandExpandedView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var actions: LiveIslandActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var map: MapStore
    @ObservedObject private var radio: RadioPlayer
    init(model: AppModel, actions: LiveIslandActions) {
        self.model = model
        self.actions = actions
        self.map = actions.map
        self.radio = actions.radio
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let logo = MotorsportAsset.seriesLogo(isWec: snapshot.isWec) {
                    Image(nsImage: logo)
                        .resizable().scaledToFit()
                        .frame(height: 15)
                        .accessibilityLabel(snapshot.isWec ? "WEC" : "F1")
                }
                titleMenu
                if snapshot.sourceMode == .replay { Text("回放").font(.caption2).foregroundStyle(.orange) }
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    modeButton("Telemetry", title: "计时", icon: "chart.bar.xaxis")
                    modeButton("Live Map", title: "地图", icon: "map")
                }.padding(2).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                Button { actions.collapse?() } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).help("收起 Live Island").accessibilityLabel("收起 Live Island")
                    .accessibilityIdentifier("liveIsland.collapse").keyboardShortcut(.cancelAction)
                Button { actions.hide?() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("隐藏 Live Island").accessibilityLabel("隐藏 Live Island")
            }
            HStack(spacing: 10) {
                followControls
                LiveWeatherView(snapshot: snapshot)
                if hasTiming {
                    Text([snapshot.lapLabel, snapshot.remainingLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .help(snapshot.remainingLabel.map { "剩余 \($0)" } ?? "已完成圈数")
                    LiveTrackStatusBadge(snapshot: snapshot, compact: true)
                } else { LiveWaitingIndicator(detail: snapshot.statusLabel) }
                if mode == "Live Map" {
                    Button { actions.showRadar.toggle() } label: {
                        Image(systemName: "cloud.rain").foregroundStyle(showRadar ? Color.blue : Color.secondary)
                    }.buttonStyle(.borderless).help("历史降雨雷达")
                        .accessibilityLabel("历史降雨雷达").accessibilityValue(showRadar ? "开启" : "关闭")
                }
                displayMenu
            }
            if mode == "Telemetry" {
                if snapshot.isWec {
                    LiveWecCarView(
                        model: model,
                        driver: selectedDriver,
                        showTire: actions.showTire,
                        showEnergy: actions.showEnergy
                    )
                } else {
                    LiveF1CarView(model: model, driver: selectedDriver, snapshot: snapshot)
                }
            }
            if mode == "Telemetry", snapshot.isWec, hasTiming, !wecClasses.isEmpty {
                classTabs
            }
            ScrollView {

                VStack(alignment: .leading, spacing: 10) {

                    if mode == "Telemetry" {
                        if hasTiming {
                            let sectorBests = wecSectorBests
                            HStack(spacing: 8) {
                                HStack(spacing: 7) {
                                    Image(systemName: "star").frame(width: 17)
                                    Text("位置 / 车手")
                                }.frame(width: 224, alignment: .leading)
                                timingHeader("Gap", width: 58)
                                timingHeader("Interval", width: 58)
                                timingHeader("上一圈", width: 76)
                                timingHeader("最佳圈", width: 76)
                                ForEach(0..<3) { index in timingHeader("S\(index + 1)", width: sectorWidth) }
                                if snapshot.isWec {
                                    Text("轮胎 / 能量").frame(width: wecTelemetryWidth, alignment: .leading)
                                }
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            LazyVStack(spacing: 6) {
                                ForEach(visibleDrivers, id: \.number) { driver in
                                    LiveIslandDriverRow(
                                        model: model,
                                        actions: actions,
                                        driver: driver,
                                        snapshot: snapshot,
                                        favoriteID: favoriteID,
                                        sectorBests: sectorBests,
                                        sectorWidth: sectorWidth,
                                        wecTelemetryWidth: wecTelemetryWidth
                                    )
                                }
                            }

                        } else if model.liveSeries == .wec {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(snapshot.statusReason == "disabled"
                                    ? "WEC Live 未在服务端启用"
                                    : "当前没有正在进行的 WEC 会话")
                                    .font(.subheadline)
                                Text(snapshot.statusReason == "disabled"
                                    ? "在本地 environment.json 中设置 F1_COMPANION_WEC_LIVE_ENABLED=1 后重启服务端。"
                                    : "顶部可随时切回 F1。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        } else {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(model.plannedIslandSessionLabel(for: snapshot, now: context.date))
                                        .font(.subheadline)
                                    if let meeting = CalendarLogic.featuredMeeting(in: model.meetings, now: context.date) {
                                        Text(meeting.name).font(.headline)
                                        Text(meeting.location).font(.caption).foregroundStyle(.secondary)
                                        ForEach(meeting.sessions.sorted { $0.startTime < $1.startTime }) { session in
                                            HStack {
                                                Text(session.sessionType.displayName)
                                                Spacer()
                                                Text(session.startTime.formatted(.dateTime.weekday().hour().minute()))
                                                    .monospacedDigit()
                                            }
                                            .font(.caption)
                                            .padding(.vertical, 3)
                                        }
                                    }
                                }
                            }
                        }

                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        MapView(store: map, meeting: meeting, snapshot: snapshot, selected: selectedDriver?.number, radar: showRadar, active: mode == "Live Map" && actions.presentation == "expanded", now: context.date)
                            .frame(height: mode == "Live Map" ? (showRadar ? 210 : 250) : 0)
                            .opacity(mode == "Live Map" ? 1 : 0)
                            .allowsHitTesting(mode == "Live Map")
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if mode == "Live Map" {
                        if let error = map.error {
                            HStack(spacing: 8) {
                                Label("地图暂时不可用", systemImage: "exclamationmark.triangle").help(error)
                                Button("重试") { Task { map.release(); await map.load(model: model, meeting: meeting); map.onDriver = { actions.selectedNumber = $0 } } }
                                Spacer()
                            }.font(.caption2).foregroundStyle(.secondary)
                        }
                        if showRadar { RadarControls(model: model, map: map) }
                    }


                }
                .background(CalendarScrollAppearance())
            }
            Divider()
            LiveMessagesView(model: model, player: radio, snapshot: snapshot, selected: selectedDriver?.number, page: $actions.messagePage, filter: $actions.messageFilter, expanded: $actions.messagesExpanded)
        }
        .padding(16)
        .frame(width: 860)
        .frame(maxHeight: 490)
        .foregroundStyle(Color.white)
        .accessibilityElement(children: .contain)
        .onAppear(perform: model.ensureDriverStandingsLoaded)
        .task(id: "\(mode)-\(model.serverAddress)-\(meeting?.id ?? "none")-\(actions.presentation)") {
            guard mode == "Live Map", actions.presentation == "expanded" else {
                map.pause()
                return
            }
            await map.load(model: model, meeting: meeting)
            map.onDriver = { actions.selectedNumber = $0 }
        }
        .onChange(of: actions.presentation) { _, value in
            if value != "expanded" { radio.stop(); map.pause() }
            if value == "hidden" { map.pause() }
        }
        .onChange(of: model.serverAddress) { _, _ in radio.stop() }
        .onDisappear { radio.stop(); map.pause() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: hasTiming)
        .environment(\.colorScheme, .dark)
    }
}

