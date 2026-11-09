import SwiftUI
import PitPulseData
import PitPulseShared

struct PreferencesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: PreferencesSection? = .connection
    @State private var serverDraft = ""
    @State private var tokenDraft = ""

    private var selectedSection: PreferencesSection { selection ?? .connection }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(PreferencesSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                        .accessibilityIdentifier("preferences.section.\(section.rawValue)")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 235)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedSection.title)
                            .font(.title2.weight(.semibold))
                        Text(selectedSection.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    sectionContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
                .frame(maxWidth: 700, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .containerBackground(.windowBackground, for: .window)
        .background { SettingsWindowProbe() }
        .onAppear {
            serverDraft = model.serverAddress
            Task { await model.refreshTokenStatus() }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .connection: connectionSettings
        case .reminders: reminderSettings
        case .liveIsland: liveIslandSettings
        case .favoriteDriver: favoriteDriverSettings
        }
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("服务器地址").font(.headline)
                TextField("https://your-server.example", text: $serverDraft)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("服务器地址")
                    .accessibilityIdentifier("preferences.serverAddress")

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Text(model.serverURL?.absoluteString ?? "未配置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        Button("保存并连接") {
                            if model.updateServerAddress(serverDraft) {
                                serverDraft = model.serverAddress
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .fixedSize()
                    }
                }
                Text("HTTP 仅允许 localhost / loopback；其他服务器必须使用 HTTPS。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Token").font(.headline)
                    Spacer()
                    Text(model.isTokenStored ? "已存入 Keychain" : "未保存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: Capsule())
                }
                SecureField(
                    model.isTokenStored ? "输入新 Token 以替换现有值" : "输入 Token",
                    text: $tokenDraft
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Token")

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Button("保存 Token") {
                            model.saveToken(tokenDraft)
                            tokenDraft = ""
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("删除 Token", role: .destructive) {
                            model.deleteToken()
                        }
                        .buttonStyle(.glass)
                        .disabled(!model.isTokenStored)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("连接与缓存").font(.headline)
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Button("测试连接") {
                            Task { await model.testConnection() }
                        }
                        .buttonStyle(.glass)
                        Button("清除当前服务器缓存") {
                            model.clearCurrentCache()
                        }
                        .buttonStyle(.glass)
                    }
                }
                if let message = model.settingsMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var reminderSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("开启 Session 提醒", isOn: Binding(
                get: { model.remindersEnabled },
                set: { enabled in Task { await model.setRemindersEnabled(enabled) } }
            ))
            .toggleStyle(.switch)
            .accessibilityIdentifier("preferences.reminders")

            Text("PitPulse 会在每个 Session 开始前提醒你。开启时 macOS 会请求通知权限；默认提前 15 分钟。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider()
            Picker("提前时间", selection: Binding(
                get: { model.reminderMinutes },
                set: { minutes in Task { await model.setReminderMinutes(minutes) } }
            )) {
                ForEach(SessionReminderPlanner.allowedMinutes, id: \.self) { minutes in
                    Text("\(minutes) 分钟").tag(minutes)
                }
            }
            .disabled(!model.remindersEnabled)
            if let message = model.reminderMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            if model.reminderPermissionDenied {
                Button("打开通知系统设置") { model.openNotificationSettings() }
                    .buttonStyle(.glass)
            }
        }
    }

    private var liveIslandSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("实时数据源", selection: Binding(
                get: { model.liveSeries },
                set: { model.setLiveSeries($0) }
            )) {
                ForEach(LiveSeries.allCases) { series in
                    Text(series.title).tag(series)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("preferences.liveSeries")
            Text("WEC 使用 FIA WEC 官方 Live Timing 的公开数据，目前为 PoC；赛历、成绩与积分仍为 F1。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Session 期间自动显示 Notch", isOn: Binding(
                get: { model.notchAutoShowEnabled },
                set: { model.setNotchAutoShowEnabled($0) }
            ))
            .toggleStyle(.switch)
            .accessibilityIdentifier("preferences.notchAutoShow")
            Text("收到 Session 实时开始状态后显示；关闭后仍可从菜单栏手动打开。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("展开后收起方式", selection: Binding(
                get: { model.notchCollapseOnMouseExit },
                set: { model.setNotchCollapseOnMouseExit($0) }
            )) {
                Text("点击 Nook 外部收起").tag(false)
                Text("鼠标移出 Nook 自动收起").tag(true)
            }
            .accessibilityIdentifier("preferences.notchCollapseBehavior")
            Text("收起后保留车手、地图视角和消息选项；菜单及天气详情打开时保持展开。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var favoriteDriverSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("车手", selection: Binding(
                get: { model.favoriteDriverId ?? "" },
                set: { model.setFavoriteDriver($0.isEmpty ? nil : $0) }
            )) {
                Text("不关注").tag("")
                ForEach(LiveIslandLogic.favorites(for: .f1, in: model.favoriteDrivers)) { driver in
                    Text(driver.name).tag(driver.id)
                }
            }
            Text("按稳定车手 ID 保存；车队变更不会改变关注对象。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private enum PreferencesSection: String, CaseIterable, Identifiable {
    case connection, reminders, liveIsland, favoriteDriver

    var id: Self { self }

    var title: String {
        switch self {
        case .connection: "连接"
        case .reminders: "本地提醒"
        case .liveIsland: "Live Island"
        case .favoriteDriver: "关注车手"
        }
    }

    var subtitle: String {
        switch self {
        case .connection: "服务器、Token 与本地缓存"
        case .reminders: "Session 开始前通知"
        case .liveIsland: "Notch 状态面板"
        case .favoriteDriver: "Live Island 优先车手"
        }
    }

    var symbol: String {
        switch self {
        case .connection: "network"
        case .reminders: "bell.badge"
        case .liveIsland: "macwindow"
        case .favoriteDriver: "person.crop.circle"
        }
    }
}
