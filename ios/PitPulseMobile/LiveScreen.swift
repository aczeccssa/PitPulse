import SwiftUI
import Charts
import SharedData

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
                    HStack { AssetImage(name: "logo-foreground.png").frame(width: 44, height: 44); PulseHeading(eyebrow: "Real-time · \(model.series.title)", title: "Live") }
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

private struct LiveComparisonChart: View {
    let drivers: [LiveDriver]
    let mode: Int
    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(mode == 0 ? "距离领跑车手" : "前八位圈速对比").font(.headline)
                Chart(Array(drivers.prefix(8)), id: \.number) { driver in
                    let name = MotorsportAssetName.abbreviation(driver.name ?? driver.number)
                    if mode == 0 {
                        if let gap = gapSeconds(driver.gap) {
                            BarMark(x: .value("差距 秒", gap), y: .value("车手", name)).foregroundStyle(PulseStyle.red).cornerRadius(3)
                                .annotation(position: .trailing) { Text(gap == 0 ? "LEADER" : String(format: "+%.3f", gap)).font(.system(size: 9).monospacedDigit()) }
                        }
                    } else {
                        if let best = driver.bestLap.flatMap(LiveIslandLogic.sectorSeconds), best.isFinite {
                            BarMark(x: .value("秒", best), y: .value("车手", name)).foregroundStyle(by: .value("圈速", "最快圈")).position(by: .value("圈速", "最快圈"))
                        }
                        if let last = driver.lastLap.flatMap(LiveIslandLogic.sectorSeconds), last.isFinite {
                            BarMark(x: .value("秒", last), y: .value("车手", name)).foregroundStyle(by: .value("圈速", "上一圈")).position(by: .value("圈速", "上一圈"))
                        }
                    }
                }.chartForegroundStyleScale(["最快圈": PulseStyle.red, "上一圈": Color.gray])
                    .frame(height: mode == 0 ? 185 : 220)
                Text(mode == 0 ? "仅对可换算为秒的差距绘图；被套圈不换算成虚构秒数。" : "最快圈与上一圈并排比较，原始圈速见下方计时表。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func gapSeconds(_ value: String?) -> Double? {
        guard let value else { return nil }
        if value.uppercased() == "LEADER" { return 0 }
        guard let number = Double(value.replacingOccurrences(of: "+", with: "")), number.isFinite, number >= 0 else { return nil }
        return number
    }
}

private struct LiveDriverDetail: View {
    @EnvironmentObject private var model: MobileModel
    let number: String
    private var driver: LiveDriver? { model.liveSnapshot.drivers.first { $0.number == number } }
    var body: some View {
        NavigationStack {
            ScrollView {
                if let driver {
                    VStack(alignment: .leading, spacing: 20) {
                        PulseHeading(eyebrow: "\(model.liveSnapshot.statusLabel) · #\(number)", title: driver.name ?? "Car \(number)")
                        HStack { Text(driver.team ?? "—"); Spacer(); Text(driver.position.map { "P\($0)" } ?? "—").bold(); Text(driver.gap ?? "—").monospacedDigit() }.font(.caption).foregroundStyle(.secondary)
                        TelemetryChartPanel(samples: model.liveHistory[number] ?? [], driver: driver)
                        PulseCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text("本圈分段").font(.headline); Spacer(); Text("秒").font(.caption2).foregroundStyle(.secondary) }
                                Chart(Array((driver.sectors ?? []).enumerated()), id: \.offset) { index, sector in
                                    if let value = sector.value.flatMap(LiveIslandLogic.sectorSeconds), value.isFinite, value >= 0 {
                                        BarMark(x: .value("分段", "S\(index + 1)"), y: .value("秒", value))
                                            .foregroundStyle(sector.overallFastest == true ? Color.purple : sector.personalFastest == true ? .green : PulseStyle.red)
                                            .cornerRadius(5)
                                            .annotation(position: .top) { Text(value.formatted(.number.precision(.fractionLength(3)))).font(.system(size: 10).monospacedDigit()) }
                                    }
                                }.frame(height: 150)
                                HStack { Label(driver.bestLap ?? "—", systemImage: "stopwatch"); Spacer(); Text("上一圈 \(driver.lastLap ?? "—")") }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        PulseCard {
                            HStack(spacing: 16) {
                                Text(driver.tireShortLabel ?? "?").font(.title.bold()).foregroundStyle(.red).frame(width: 46, height: 46).overlay(Circle().stroke(.red, lineWidth: 2))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(driver.tireCompound ?? "轮胎未知").font(.headline)
                                    Text(driver.tireAgeLaps.map { "已使用 \($0) 圈" } ?? "胎龄未知").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(driver.retired == true ? "退赛" : driver.inPit == true ? "进站" : driver.inPit == false ? "赛道中" : "状态未知").font(.caption)
                            }
                        }
                    }.padding(20)
                } else { ContentUnavailableView("暂无此车手数据", systemImage: "person.crop.circle.badge.questionmark") }
            }.background(PulseStyle.background).navigationTitle("车手图表").navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct TelemetryChartPanel: View {
    let samples: [LiveTelemetry]
    let driver: LiveDriver
    private struct Point: Identifiable {
        let id: String
        let date: Date
        let speed: Double?
        let throttle: Double?
        let brake: Double?
    }
    private var points: [Point] {
        samples.compactMap { sample in
            guard let date = RFC3339.parse(sample.utc) else { return nil }
            return Point(id: sample.utc, date: date, speed: sample.speed, throttle: sample.throttle, brake: sample.brake)
        }
    }
    var body: some View {
        VStack(spacing: 20) {
            PulseCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(driver.telemetry?.speed.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—").font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                        Text("km/h").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(driver.telemetry?.gear.map { "GEAR \($0.formatted(.number.precision(.fractionLength(0))))" } ?? "GEAR —").font(.caption.bold())
                            Text(driver.telemetry?.rpm.map { "\($0.formatted(.number.precision(.fractionLength(0)))) RPM" } ?? "RPM —").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if points.count > 1 {
                        Chart(points) { point in
                            if let speed = point.speed { LineMark(x: .value("时间", point.date), y: .value("速度 km/h", speed)).foregroundStyle(PulseStyle.red).lineStyle(StrokeStyle(lineWidth: 2.5)) }
                        }.frame(height: 160).chartYScale(domain: 0...max(350, points.compactMap(\.speed).max() ?? 350))
                    } else { Text("等待速度样本，收到后自动绘图。").font(.caption).foregroundStyle(.secondary).frame(height: 90) }
                    Text("最近 \(points.count) 个真实遥测样本 · 随数据流更新").font(.caption2).foregroundStyle(.secondary)
                }
            }
            PulseCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("油门 / 刹车").font(.headline)
                    if points.count > 1 {
                        Chart(points) { point in
                            if let throttle = point.throttle { LineMark(x: .value("时间", point.date), y: .value("踏板 %", throttle)).foregroundStyle(by: .value("踏板", "油门")) }
                            if let brake = point.brake { LineMark(x: .value("时间", point.date), y: .value("踏板 %", brake)).foregroundStyle(by: .value("踏板", "刹车")) }
                        }.chartForegroundStyleScale(["油门": Color.green, "刹车": Color.red]).chartYScale(domain: 0...100).frame(height: 140)
                    } else { Text("当前数据源尚未提供足够的踏板样本。").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

struct ResultsScreen: View {
    @EnvironmentObject private var model: MobileModel
    let session: Session
    let meeting: Meeting
    @State private var results: [SessionResult] = []
    @State private var error: String?
    @State private var loading = false
    @State private var quality: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PulseHeading(eyebrow: "Weekend Results", title: session.sessionType.displayName)
                Text("\(meeting.name) · R\(meeting.round ?? 0)").font(.subheadline).foregroundStyle(.secondary)
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let quality { Text(quality).font(.caption2).foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.orange) }
                PulseCard {
                    VStack(spacing: 0) {
                        HStack { Text("#   车手"); Spacer(); Text("成绩 / 最快圈") }.font(.caption2).foregroundStyle(.secondary).padding(.bottom, 12)
                        ForEach(results) { row in
                            NavigationLink { DriverAnalysisScreen(sessionID: session.id, driverID: row.driverId, name: row.driverName) } label: {
                                HStack(spacing: 12) {
                                    Text(row.position.map(String.init) ?? "—").frame(width: 22).monospacedDigit()
                                    AssetImage(name: MotorsportAssetName.helmetName(driverID: row.driverId, name: row.driverName, season: meeting.season)).frame(width: 34, height: 30)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(MotorsportAssetName.abbreviation(row.driverName)).font(.subheadline.bold())
                                        HStack(spacing: 4) { AssetImage(name: MotorsportAssetName.name(kind: .teamLogo, id: row.constructorId, season: meeting.season)).frame(width: 15, height: 12); Text(row.team).font(.system(size: 9)).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(row.position == nil ? row.classificationLabel : (row.time ?? row.bestLap ?? row.gap ?? row.classificationLabel)).font(.caption.monospacedDigit())
                                        Text(row.points.map { "\($0.formatted()) PTS" } ?? "—").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary)
                                }.padding(.vertical, 12)
                            }.buttonStyle(.plain)
                            Divider()
                        }
                        if results.isEmpty && !loading { Text("暂无成绩，场次结束并同步后可查看。").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 24) }
                    }
                }
                Text("点击车手查看圈速、分段和遥测。缺失数据保留为空。").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.background(PulseStyle.background).navigationTitle("场次成绩").navigationBarTitleDisplayMode(.inline)
            .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        guard let url = model.serverURL else { error = "请检查服务器地址"; return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let response = try await APIClient(baseURL: url).sessionResults(sessionId: session.id, token: model.currentToken)
            results = response.data
            quality = (response.meta.stale ? "缓存过期 · " : "") + response.meta.quality.displayName
        }
        catch { self.error = MobileModel.message(for: error) }
    }
}

struct DriverAnalysisScreen: View {
    @EnvironmentObject private var model: MobileModel
    let sessionID: String
    let driverID: String
    let name: String
    @State private var analysis: SessionAnalysis?
    @State private var error: String?
    @State private var mode = 0
    @State private var selectedLap: Int?
    @State private var focusedLap: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PulseHeading(eyebrow: "Driver Analytics", title: name)
                Picker("分析图表", selection: $mode) {
                    Text("圈速").tag(0); Text("分段").tag(1); Text("遥测").tag(2); Text("轮胎").tag(3)
                }.pickerStyle(.segmented)
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                if let analysis {
                    switch mode {
                    case 0: lapChart(analysis)
                    case 1: sectorChart(analysis)
                    case 2: telemetryCharts(analysis)
                    default: stintChart(analysis)
                    }
                    ForEach(analysis.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                } else if error == nil { ProgressView("加载车手数据…") }
            }.padding(20)
        }.background(PulseStyle.background).navigationTitle("车手图表").navigationBarTitleDisplayMode(.inline)
            .refreshable { await load() }
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: mode)
            .task(id: "\(model.dataContext):\(selectedLap.map(String.init) ?? "best")") { await load() }
    }
    private func lapChart(_ analysis: SessionAnalysis) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("每圈节奏").font(.headline)
                Chart(Array(analysis.laps.enumerated()), id: \.offset) { _, lap in
                    if let number = lap.lapNumber, let duration = lap.lapDuration {
                        LineMark(x: .value("圈", number), y: .value("圈速 秒", duration)).foregroundStyle(PulseStyle.red)
                        PointMark(x: .value("圈", number), y: .value("圈速 秒", duration)).foregroundStyle(PulseStyle.red).symbolSize(14)
                    }
                    if let focusedLap { RuleMark(x: .value("选中圈", focusedLap)).foregroundStyle(.secondary.opacity(0.5)) }
                }.frame(height: 240).chartXSelection(value: $focusedLap).chartYScale(domain: .automatic(includesZero: false))
                if let focusedLap, let row = analysis.laps.first(where: { $0.lapNumber == focusedLap }) {
                    Text("L\(focusedLap) · \(row.lapDuration.map { String(format: "%.3f s", $0) } ?? "—")").font(.caption.monospacedDigit()).foregroundStyle(.red)
                } else { Text("按住图表查看单圈值；进站慢圈保留真实耗时。").font(.caption2).foregroundStyle(.secondary) }
                if analysis.laps.isEmpty { Text("暂无逐圈数据").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private func sectorChart(_ analysis: SessionAnalysis) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("分段耗时构成").font(.headline)
                Chart(Array(analysis.laps.enumerated()), id: \.offset) { _, lap in
                    if let number = lap.lapNumber {
                        ForEach(0..<3, id: \.self) { index in
                            if let value = lap.sectors[index] { BarMark(x: .value("圈", number), y: .value("秒", value)).foregroundStyle(by: .value("分段", "S\(index + 1)")) }
                        }
                    }
                }.chartForegroundStyleScale(["S1": PulseStyle.red, "S2": Color.orange, "S3": Color.purple]).frame(height: 260)
                Text("每个柱形对应一圈，颜色表示三个分段；缺失分段不补零。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func telemetryCharts(_ analysis: SessionAnalysis) -> some View {
        VStack(spacing: 20) {
            Picker("遥测圈", selection: $selectedLap) {
                Text("最快圈").tag(Int?.none)
                ForEach(analysis.laps.compactMap(\.lapNumber), id: \.self) { lap in Text("L\(lap)").tag(Int?.some(lap)) }
            }.pickerStyle(.menu)
            PulseCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("速度 · L\(analysis.selectedLap ?? selectedLap ?? 0)").font(.headline)
                    Chart(Array(analysis.carData.enumerated()), id: \.offset) { _, point in
                        if let date = point.date, let speed = point.speed { LineMark(x: .value("时间", date), y: .value("km/h", speed)).foregroundStyle(PulseStyle.red) }
                    }.frame(height: 190)
                    if analysis.carData.isEmpty { Text("此圈暂无速度遥测").font(.caption).foregroundStyle(.secondary) }
                }
            }
            PulseCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("油门与刹车").font(.headline)
                    Chart(Array(analysis.carData.enumerated()), id: \.offset) { _, point in
                        if let date = point.date {
                            if let throttle = point.throttle { LineMark(x: .value("时间", date), y: .value("%", throttle)).foregroundStyle(by: .value("踏板", "油门")) }
                            if let brake = point.brake { LineMark(x: .value("时间", date), y: .value("%", brake)).foregroundStyle(by: .value("踏板", "刹车")) }
                        }
                    }.chartForegroundStyleScale(["油门": Color.green, "刹车": Color.red]).chartYScale(domain: 0...100).frame(height: 160)
                }
            }
        }
    }
    private func stintChart(_ analysis: SessionAnalysis) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("轮胎使用区间").font(.headline)
                Chart(Array(analysis.stints.enumerated()), id: \.offset) { index, stint in
                    if let start = stint.lapStart, let end = stint.lapEnd ?? analysis.laps.compactMap(\.lapNumber).max() {
                        BarMark(xStart: .value("起始圈", start), xEnd: .value("结束圈", end), y: .value("Stint", "Stint \(stint.stintNumber ?? index + 1)"))
                            .foregroundStyle(by: .value("轮胎", stint.compound ?? "未知"))
                            .annotation(position: .overlay) { Text("\(stint.compound ?? "?") · L\(start)–\(end)").font(.system(size: 10, weight: .bold)).foregroundStyle(["MEDIUM", "HARD"].contains(stint.compound ?? "") ? Color.black : Color.white) }
                    }
                }.chartForegroundStyleScale(["SOFT": Color.red, "MEDIUM": Color.yellow, "HARD": Color.gray, "INTERMEDIATE": Color.green, "WET": Color.blue, "未知": Color.secondary]).frame(height: max(150, CGFloat(analysis.stints.count) * 42))
                if analysis.stints.isEmpty { Text("暂无轮胎使用记录").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private func load() async {
        guard let url = model.serverURL else { error = "服务器地址无效"; return }
        error = nil
        do {
            for attempt in 0..<10 {
                let response = try await APIClient(baseURL: url).sessionAnalysis(sessionId: sessionID, driverId: driverID, lap: selectedLap, token: model.currentToken)
                try Task.checkCancellation()
                let pending = response.meta.analysisStatus == "loading" || response.meta.analysisStatus == "refreshing"
                if pending {
                    if attempt == 9 { error = "历史数据仍在后台同步，请下拉刷新。"; return }
                    try await Task.sleep(for: .seconds(2))
                    continue
                }
                analysis = response.data
                if response.meta.analysisStatus == "failed" { error = response.meta.analysisError ?? "当前场次的数据源暂不可用，请下拉重试。" }
                return
            }
        } catch { if !Task.isCancelled { self.error = MobileModel.message(for: error) } }
    }
}

struct ChampionshipScreen: View {
    @EnvironmentObject private var model: MobileModel
    @State private var drivers: [DriverStanding] = []
    @State private var teams: [ConstructorStanding] = []
    let mode: Int
    @State private var selectedID: String?
    @State private var analysis: SeasonAnalysis?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PulseHeading(eyebrow: "Formula 1 · \(model.season)", title: mode == 0 ? "车手积分" : "车队积分")
                    if let id = selectedID {
                        PulseCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 16) {
                                    AssetImage(name: MotorsportAssetName.name(kind: mode == 0 ? .helmet : .teamLogo, id: id, season: model.season)).frame(width: 94, height: 100)
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(selectedName).font(.title3.bold())
                                            if mode == 0 {
                                                Button { model.favoriteDriverID = model.favoriteDriverID == selectedID ? nil : selectedID } label: {
                                                    Image(systemName: model.favoriteDriverID == selectedID ? "star.fill" : "star")
                                                }.buttonStyle(.plain).foregroundStyle(PulseStyle.red).accessibilityLabel("收藏 \(selectedName)")
                                            }
                                        }
                                        if mode == 0, let row = drivers.first(where: { $0.id == selectedID }) {
                                            HStack(spacing: 5) {
                                                AssetImage(name: MotorsportAssetName.name(kind: .teamLogo, id: row.constructorIds.first ?? "", season: model.season)).frame(width: 22, height: 16)
                                                Text(row.constructor).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Text("\(selectedPoints.formatted()) PTS").font(.headline.monospacedDigit()).foregroundStyle(PulseStyle.red)
                                    }
                                }
                                Text("赛季积分趋势").font(.caption).foregroundStyle(.secondary)
                                if let analysis, analysis.hasData {
                                    Chart(trend, id: \.round) { item in
                                        AreaMark(x: .value("站", item.round), y: .value("积分", item.points)).foregroundStyle(PulseStyle.red.opacity(0.12))
                                        LineMark(x: .value("站", item.round), y: .value("积分", item.points)).foregroundStyle(PulseStyle.red).symbol(.circle)
                                    }.frame(height: 150)
                                } else { Text(loading ? "加载趋势…" : "暂无趋势数据").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                    PulseCard {
                        VStack(spacing: 0) {
                            if mode == 0 {
                                ForEach(drivers) { row in
                                    Button { selectedID = row.id } label: {
                                        standingRow(position: row.position, name: row.driverName, points: row.points, asset: MotorsportAssetName.helmetName(driverID: row.id, name: row.driverName, season: model.season), teamAsset: MotorsportAssetName.name(kind: .teamLogo, id: row.constructorIds.first ?? "", season: model.season), teamName: row.constructor, favorite: model.favoriteDriverID == row.id)
                                    }.buttonStyle(.plain)
                                }
                            } else {
                                ForEach(teams) { row in
                                    Button { selectedID = row.id } label: {
                                        standingRow(position: row.position, name: row.constructorName, points: row.points, asset: MotorsportAssetName.name(kind: .teamLogo, id: row.id, season: model.season))
                                    }.buttonStyle(.plain)
                                }
                            }
                            if drivers.isEmpty && teams.isEmpty { ContentUnavailableView("暂无积分", systemImage: "chart.bar", description: Text("当前服务器未返回 F1 积分。请在设置中检查 F1 数据，确认已连接有数据的服务器。")) }
                        }
                    }
                }.padding(20)
            }.background(PulseStyle.background)
                .toolbar { ToolbarItem(placement: .topBarLeading) { PulseSettingsButton() } }
                .task(id: model.dataContext) { await load() }
                .refreshable { await load() }
                .task(id: "\(mode):\(selectedID ?? ""):\(model.dataContext)") { await loadTrend() }
        }
    }
    private var selectedName: String { mode == 0 ? drivers.first { $0.id == selectedID }?.driverName ?? "—" : teams.first { $0.id == selectedID }?.constructorName ?? "—" }
    private var selectedPoints: Double { mode == 0 ? drivers.first { $0.id == selectedID }?.points ?? 0 : teams.first { $0.id == selectedID }?.points ?? 0 }
    private var trend: [(round: Int, points: Double)] {
        analysis?.cumulativePointsByRound ?? []
    }

    private func standingRow(position: Int, name: String, points: Double, asset: String, teamAsset: String? = nil, teamName: String? = nil, favorite: Bool = false) -> some View {
        HStack(spacing: 14) {
            Text("\(position)").font(.subheadline.bold().monospacedDigit()).frame(width: 22)
            AssetImage(name: asset).frame(width: 40, height: 36)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(name).font(.subheadline.weight(.medium)).lineLimit(1)
                    if favorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(PulseStyle.red) }
                }
                if let teamAsset, let teamName {
                    HStack(spacing: 5) {
                        AssetImage(name: teamAsset).frame(width: 18, height: 13)
                        Text(teamName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(); Text(points.formatted()).font(.subheadline.bold().monospacedDigit())
        }.padding(.vertical, 14).contentShape(Rectangle())
            .background(selectedName == name ? PulseStyle.red.opacity(0.1) : .clear)
    }
    private func load() async {
        guard let url = model.serverURL else { error = "服务器地址无效"; return }
        let context = model.dataContext
        drivers = []; teams = []; selectedID = nil; analysis = nil
        error = nil
        let client = APIClient(baseURL: url)
        do {
            let response = try await client.driverStandings(season: model.season, token: model.currentToken)
            guard model.dataContext == context, !Task.isCancelled else { return }; drivers = response.data
        }
        catch { self.error = MobileModel.message(for: error) }
        do {
            let response = try await client.constructorStandings(season: model.season, token: model.currentToken)
            guard model.dataContext == context, !Task.isCancelled else { return }; teams = response.data
        }
        catch { self.error = MobileModel.message(for: error) }
        selectedID = mode == 0 ? drivers.first?.id : teams.first?.id
    }
    private func loadTrend() async {
        analysis = nil
        guard let id = selectedID, let url = model.serverURL else { return }
        loading = true; defer { loading = false }
        do {
            let response = try await APIClient(baseURL: url).seasonAnalysis(kind: mode == 0 ? "drivers" : "constructors", id: id, season: model.season, token: model.currentToken)
            try Task.checkCancellation(); analysis = response.data; error = nil
        } catch is CancellationError { } catch { if !Task.isCancelled { self.error = MobileModel.message(for: error) } }
    }
}
