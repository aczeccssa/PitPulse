import SwiftUI
import PitPulseData
import PitPulseShared

struct SettingsScreen: View {
    @EnvironmentObject private var model: MobileModel
    @State private var tokenDraft = ""
    @State private var serverDraft = ""
    @State private var tokenMessage: String?
    @State private var revealToken = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mobileAppearance") private var appearance = "system"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        AssetImage(name: "logo-foreground.png").frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 4) { Text("PitPulse").font(.title2.bold()); Text("MOTORSPORT LIVE & DATA").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(.secondary) }
                    }
                }
                Section("服务器") {
                    TextField("http://localhost:38701", text: $serverDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    HStack(spacing: 8) {
                        if revealToken {
                            TextField("Token（可选）", text: $tokenDraft)
                        } else {
                            SecureField("Token（可选）", text: $tokenDraft)
                        }
                        Button {
                            revealToken.toggle()
                        } label: {
                            Image(systemName: revealToken ? "eye.slash" : "eye").accessibilityLabel(revealToken ? "隐藏 Token" : "显示 Token")
                        }
                        .buttonStyle(.borderless)
                    }

                    Button("保存连接设置") { save() }
                    Button("检查 F1 数据") { Task { await model.testConnection() } }
                    Text("检查已保存地址的赛历、车手和车队数据。真机请填写服务器的局域网 IP 或域名，localhost 指当前手机自身。")
                        .font(.caption2).foregroundStyle(.secondary)

                    if let health = model.healthText {
                        Text(health).font(.caption).foregroundStyle(.secondary)
                    }
                    if let tokenMessage {
                        Text(tokenMessage)
                            .font(.caption)
                            .foregroundStyle(tokenMessage == "已保存" ? .green : .red)
                    }
                }

                Section("赛历") {
                    Picker("赛季", selection: $model.season) {
                        ForEach(2023...2027, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    LabeledContent("当前服务器", value: model.serverURL?.absoluteString ?? "无效地址")
                }

                Section("外观") {
                    Picker("主题", selection: $appearance) {
                        Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
                    }.pickerStyle(.segmented)
                }
                Section("喜欢的车手") {
                    Picker("收藏", selection: $model.favoriteDriverID) {
                        Text("未选择").tag(String?.none)
                        ForEach(model.driverRoster) { driver in
Text(driver.driverName).tag(String?.some(driver.id))
                        }
                    }
                    if model.driverRoster.isEmpty {
                        Text(model.rosterLoadError ?? "正在加载车手…").font(.caption).foregroundStyle(.secondary)
                        Button("重新加载车手") { Task { await model.loadF1Roster(force: true) } }
                    }
                    Text("首页会显示你的车手；灵动岛可切换为该车手的排名和差距。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Section("灵动岛") {
                    Picker("显示内容", selection: $model.islandMode) {
                        ForEach(IslandContentMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    Button("结束灵动岛活动") { model.endLiveActivity() }
                    Text("前台按比赛数据更新；后台数据到期后会标记过期。比赛系列根据当前进行的赛事自动发现。")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                #if DEBUG
                Section("组件") { NavigationLink("预览组件尺寸与外观") { WidgetPreviewGallery() } }
                #endif
                Section("关于") {
                    LabeledContent("版本", value: "0.1.0")
                    LabeledContent("数据层", value: model.hasToken ? "PitPulseData · Token 已保存" : "PitPulseData")
                }
            }
            .scrollContentBackground(.hidden)
            .background(PulseStyle.background)
            .navigationTitle("设置")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task(id: model.dataContext) { await model.loadF1Roster() }
            .onAppear { serverDraft = model.serverText }
        }
    }

    private func save() {
        if let failure = model.saveConnection(address: serverDraft, token: tokenDraft) {
            tokenMessage = failure
        } else {
            tokenMessage = "已保存"
            tokenDraft = ""
            Task { await model.loadCalendar(force: true) }
        }
    }
}
