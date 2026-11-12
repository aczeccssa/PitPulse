import Charts
import SharedData
import SwiftUI

struct LiveScreen: View {
    var onClose: (() -> Void)? = nil
    @EnvironmentObject private var model: MobileModel
    @State private var mode = 0
    @State private var selectedNumber: String?
    @State private var islandPreviewPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { AssetImage(name: MotorsportAssetName.brandLogoName).frame(width: 44, height: 44); PulseHeading(eyebrow: "Real-time · \(model.series.title)", title: "Live") }
                    PulseCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(model.liveSnapshot.meetingName ?? "等待赛事连接").font(.headline)
                                Spacer()
                                Text(model.liveConnecting ? "连接中" : model.liveSnapshot.statusLabel)
                                    .font(.caption2.bold()).padding(6).background(PulseStyle.red.opacity(0.2), in: Capsule())
                            }
                            HStack {
                                Text(model.liveSnapshot.sessionName ?? "—")
                                Text(model.liveSnapshot.lapLabel).monospacedDigit()
                                Spacer()
                                Text(model.liveSnapshot.trackCondition.label)
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Picker("计时视图", selection: $mode) {
                        Text("计时").tag(0); Text("圈速").tag(1); Text("轮胎").tag(2); Text("赛会").tag(3)
                    }.pickerStyle(.segmented)
                    if mode < 2 && !model.sortedDrivers.isEmpty {
                        LiveComparisonChart(drivers: model.sortedDrivers, mode: mode)
                    }
                    if mode == 3 {
                        ForEach(Array((model.liveSnapshot.raceControl ?? []).enumerated()), id: \.offset) { _, message in
                            PulseCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack { Label(message.flag ?? message.category ?? "RACE CONTROL", systemImage: "flag.fill").foregroundStyle(flagColor(message.flag)); Spacer(); if let lap = message.lap { Text("L\(lap)").monospacedDigit() } }.font(.caption2.bold())
                                    Text(message.message ?? "—").font(.subheadline)
                                }
                            }.transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        if model.liveSnapshot.raceControl?.isEmpty != false { Text("暂无赛会消息").foregroundStyle(.secondary) }
                    } else {
                        PulseCard {
                            VStack(spacing: 0) {
                                HStack {
                                    Label("灵动岛对比 · 最多两位", systemImage: "person.2")
                                    Spacer()
                                    if !model.islandBattleNumbers.isEmpty { Button("恢复默认") { model.resetIslandBattle() } }
                                }.font(.caption).padding(.bottom, 12)
                                HStack {
                                    Text("#").frame(width: 24)
                                    Text("车手"); Spacer()
                                    Text(mode == 1 ? "最快圈 / 上圈" : mode == 2 ? "轮胎 / 胎龄" : "差距"); Text("胎").frame(width: 28)
                                }.font(.caption2).foregroundStyle(.secondary).padding(.bottom, 12)
                                ForEach(model.sortedDrivers, id: \.number) { driver in
                                    HStack(spacing: 8) {
                                    Button { model.toggleIslandBattle(driver.number) } label: {
                                        Image(systemName: model.islandBattleNumbers.contains(driver.number) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(model.islandBattleNumbers.contains(driver.number) ? PulseStyle.red : .secondary)
                                            .frame(width: 32, height: 44)
                                    }.buttonStyle(.plain)
                                    .disabled(model.islandBattleNumbers.count == 2 && !model.islandBattleNumbers.contains(driver.number))
                                    .accessibilityLabel("灵动岛对比 \(driver.name ?? driver.number)")
                                    .accessibilityValue(model.islandBattleNumbers.contains(driver.number) ? "已选择" : "未选择")
                                    Button { selectedNumber = driver.number } label: {
                                    HStack(spacing: 10) {
                                        Text(driver.position.map(String.init) ?? "—").frame(width: 24).monospacedDigit()
                                        AssetImage(name: model.helmetAsset(for: driver)).frame(width: 36, height: 32)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(MotorsportAssetName.abbreviation(driver.name ?? driver.number)).fontWeight(.semibold)
                                            HStack(spacing: 4) {
                                                if let teamID = LiveIslandLogic.teamAssetID(for: driver, isWec: model.liveSnapshot.isWec) {
                                                    AssetImage(name: MotorsportAssetName.name(kind: .teamLogo, id: teamID, season: model.season)).frame(width: 15, height: 13)
                                                }
                                                Text(driver.team ?? "#\(driver.number)").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            if model.driverID(for: driver) == model.favoriteDriverID, model.favoriteDriverID != nil { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(PulseStyle.red) }
                                        }
                                        Spacer(minLength: 0)
                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text(value(driver)).font(.caption.monospacedDigit()).contentTransition(.numericText()).animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: value(driver))
                                            if mode == 1 { Text(driver.lastLap ?? "—").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
                                        }
                                        Text(driver.tireShortLabel ?? "—").font(.caption2.bold()).frame(width: 23, height: 23)
                                            .foregroundStyle(tireColor(driver)).overlay(Circle().stroke(tireColor(driver), lineWidth: 1.5))
                                    }.font(.subheadline).padding(.vertical, 11).contentShape(Rectangle())
                                    }.buttonStyle(PulsePressStyle())
                                    }
                                    Divider().overlay(Color.primary.opacity(0.035))
                                }
                                if model.sortedDrivers.isEmpty {
                                    ContentUnavailableView("等待计时数据", systemImage: "antenna.radiowaves.left.and.right", description: Text("连接后显示服务器快照；不会使用虚构实时数据。"))
                                }
                            }
                        }
                    }
                    Text("点击车手查看实时速度、油门、刹车、分段及轮胎。数据由当前快照提供，缺失项显示为未知。").font(.caption2).foregroundStyle(.secondary)
                    Text(model.liveSnapshot.lastUpdatedLabel.map { "更新于 \($0)" } ?? "尚未收到快照")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(20)
            }.background(PulseStyle.background).toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let onClose { Button(action: onClose) { Image(systemName: "chevron.down") }.accessibilityLabel("收起 Live") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.availableLiveSeries.count > 1 {
                        Menu {
                            ForEach(model.availableLiveSeries) { series in Button(series.title) { model.selectLiveSeries(series) } }
                        } label: { Label("切换比赛", systemImage: "arrow.left.arrow.right") }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if let notice = model.liveNotice {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(PulseStyle.red)
                        Text(notice).font(.caption.weight(.medium))
                        Spacer()
                        Button { model.liveNotice = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("关闭新比赛提示")
                    }.padding(14).background(.regularMaterial)
                }
            }
            .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button {
                            islandPreviewPresented = true
                        } label: {
                            HStack(spacing: 6) {
                                Text("灵动岛")
                                Text(model.islandMode.title).foregroundStyle(.secondary)
                                Image(systemName: "chevron.up.chevron.down").font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("灵动岛显示：\(model.islandMode.title)")
                        Spacer()
                        Button(model.isLiveRunning ? "断开" : "连接") { model.toggleLive() }.font(.caption)
                    }.padding(.horizontal, 20).padding(.vertical, 10).background(.regularMaterial)
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: mode)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.sortedDrivers.map(\.number))
            .sheet(isPresented: $islandPreviewPresented) {
                IslandModePreviewSheet()
                    .environmentObject(model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: Binding(get: { selectedNumber != nil }, set: { if !$0 { selectedNumber = nil } })) {
                if let number = selectedNumber { LiveDriverDetail(number: number).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
            }
            .task { model.autoStartLiveOnce() }
        }
    }
    private func value(_ driver: LiveDriver) -> String {
        if mode == 1 { return driver.bestLap ?? "—" }
        if mode == 2 { return driver.tireLabel ?? "未知" }
        return driver.gap ?? driver.interval ?? "—"
    }
    private func flagColor(_ flag: String?) -> Color {
        switch flag?.uppercased() {
        case "BLUE": .blue
        case "YELLOW", "DOUBLE YELLOW": .yellow
        case "GREEN", "CLEAR": .green
        case "RED": .red
        default: .secondary
        }
    }
    private func tireColor(_ driver: LiveDriver) -> Color {
        switch driver.tireShortLabel { case "S": .red; case "M": .orange; case "I": .green; case "W": .blue; default: .primary }
    }
}
