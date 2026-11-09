import SwiftUI
import PitPulseData
import PitPulseShared

struct SettingsScreen: View {
    @EnvironmentObject private var model: MobileModel
    @State private var tokenDraft = ""
    @State private var tokenMessage: String?
    @State private var revealToken = false

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    TextField("http://localhost:38701", text: $model.serverText)
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
                            Image(systemName: revealToken ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    Button("保存连接设置") { save() }
                    Button("测试连接") { Task { await model.testConnection() } }

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

                Section("Live") {
                    Picker("系列", selection: $model.series) {
                        ForEach(LiveSeries.allCases) { series in
                            Text(series.title).tag(series)
                        }
                    }
                    Button("结束灵动岛活动") { model.endLiveActivity() }
                    Text("iOS 26+ 灵动岛通过 Live Activity 展示实时比赛状态。App 在前台或刚退到后台时更新，无需服务端推送。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("关于") {
                    LabeledContent("版本", value: "0.1.0")
                    LabeledContent("数据层", value: model.hasToken ? "PitPulseData · Token 已保存" : "PitPulseData")
                }
            }
            .navigationTitle("设置")
        }
    }

    private func save() {
        if let failure = model.saveToken(tokenDraft) {
            tokenMessage = failure
        } else {
            tokenMessage = "已保存"
            tokenDraft = ""
        }
    }
}
