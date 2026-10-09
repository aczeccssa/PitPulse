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
