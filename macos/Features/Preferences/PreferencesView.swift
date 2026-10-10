import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var serverDraft = ""
    @State private var tokenDraft = ""

    var body: some View {
        Form {
            Section("服务器") {
                TextField("服务器地址", text: $serverDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text(model.serverURL?.absoluteString ?? "未配置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("保存并连接") {
                        _ = model.updateServerAddress(serverDraft)
                    }
                }
                Text("HTTP 仅允许 localhost / loopback；其他服务器必须使用 HTTPS。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Token") {
                SecureField(model.isTokenStored ? "输入新 Token 以替换现有值" : "输入 Token", text: $tokenDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("保存 Token") {
                        model.saveToken(tokenDraft)
                        tokenDraft = ""
                    }
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("删除 Token") {
                        model.deleteToken()
                    }
                    .disabled(!model.isTokenStored)
                    Spacer()
                    Text(model.isTokenStored ? "已存入 Keychain" : "未保存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("本地提醒") {
                Toggle("开启 Session 提醒", isOn: Binding(
                    get: { model.remindersEnabled },
                    set: { enabled in Task { await model.setRemindersEnabled(enabled) } }
                ))
                Text("PitPulse 会在每个 Session 开始前提醒你。开启时 macOS 会请求通知权限；默认提前 15 分钟。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                if model.reminderPermissionDenied {
                    Button("打开通知系统设置") { model.openNotificationSettings() }
                }
            }

            Section("Live Island") {
                Toggle("Session 期间自动显示 Notch", isOn: Binding(
                    get: { model.notchAutoShowEnabled },
                    set: { model.setNotchAutoShowEnabled($0) }
                ))
                .accessibilityIdentifier("preferences.notchAutoShow")
                Text("收到 Session 实时开始状态后显示；关闭后仍可从菜单栏手动打开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("关注车手") {
                Picker("车手", selection: Binding(
                    get: { model.favoriteDriverId ?? "" },
                    set: { model.setFavoriteDriver($0.isEmpty ? nil : $0) }
                )) {
                    Text("不关注").tag("")
                    ForEach(model.favoriteDrivers) { driver in
                        Text(driver.name).tag(driver.id)
                    }
                }
                Text("按稳定车手 ID 保存；车队变更不会改变关注对象。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("连接与缓存") {
                HStack {
                    Button("测试连接") {
                        Task { await model.testConnection() }
                    }
                    Button("清除当前服务器缓存") {
                        model.clearCurrentCache()
                    }
                }
                if let message = model.settingsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            serverDraft = model.serverAddress
            Task { await model.refreshTokenStatus() }
        }
    }
}
