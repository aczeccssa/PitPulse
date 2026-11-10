import SwiftUI
import PitPulseData
import PitPulseShared

struct SettingsScreen: View {
    @EnvironmentObject private var model: MobileModel
    @State private var serverConfigurationPresented = false
    @State private var serverReachable: Bool?
    @State private var widgetPreviewPresented = false
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
                    HStack(spacing: 8) {
                        if let url = model.serverURL {
                            Link(model.serverText, destination: url).lineLimit(1).truncationMode(.middle)
                        } else {
                            Text("未配置服务器").foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                        Image(systemName: serverReachable == true ? "checkmark.circle.fill" : serverReachable == false ? "xmark.circle.fill" : "circle.dotted")
                            .font(.title2)
                            .foregroundStyle(serverReachable == true ? Color.green : serverReachable == false ? Color.red : Color.secondary)
                            .accessibilityLabel(serverReachable == true ? "服务器可用" : serverReachable == false ? "服务器不可用" : "正在检查服务器")

                        Button { serverConfigurationPresented = true } label: {
                            Image(systemName: "square.and.pencil").font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("配置服务器")
                    }
                    .listRowSeparator(.hidden)
                }

                Section("偏好设置") {
                    Picker("赛季", selection: $model.season) {
                        ForEach(2023...2027, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }

                    Picker("主题", selection: $appearance) {
                        Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
                    }.pickerStyle(.menu)

                    Picker("收藏车手", selection: $model.favoriteDriverID) {
                        Text("未选择").tag(String?.none)
                        ForEach(model.driverRoster) { driver in
Text(driver.driverName).tag(String?.some(driver.id))
                        }
                    }
                    if model.driverRoster.isEmpty {
                        Text(model.rosterLoadError ?? "正在加载车手…").font(.caption).foregroundStyle(.secondary)
                        Button("重新加载车手") { Task { await model.loadF1Roster(force: true) } }
                    }
                }
                Section("组件") {
                    Picker("灵动岛显示", selection: $model.islandMode) {
                        ForEach(IslandContentMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    #if DEBUG
                    Button { widgetPreviewPresented = true } label: {
                        HStack {
                            Image(systemName: "rectangle.grid.2x2")
                            Text("桌面组件预览")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                    #endif
                }

                Section("关于") {
                    LabeledContent("版本", value: "0.1.0")
                    LabeledContent("数据层", value: model.hasToken ? "PitPulseData · Token 已保存" : "PitPulseData")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .formStyle(.grouped)
            .tint(PulseStyle.red)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("关闭设置")
                }
            }
            .task(id: model.dataContext) {
                let context = model.dataContext
                serverReachable = nil
                if let url = model.serverURL {
                    do {
                        let health = try await APIClient(baseURL: url).health(token: model.currentToken)
                        guard !Task.isCancelled, context == model.dataContext else { return }
                        serverReachable = health.database && health.status == "ok"
                    } catch {
                        guard !Task.isCancelled, context == model.dataContext else { return }
                        serverReachable = false
                    }
                } else { serverReachable = false }
                await model.loadF1Roster()
            }
        }
        // Present from the stable settings root, not a lazily rebuilt Form section.
        .sheet(isPresented: $serverConfigurationPresented) {
            ServerConfigurationSheet().environmentObject(model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #if DEBUG
        .sheet(isPresented: $widgetPreviewPresented) {
            NavigationStack { WidgetPreviewGallery() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #endif
    }

 }

private struct ServerConfigurationSheet: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var token = ""
    @State private var result: String?
    @State private var testRequest: UUID?
    @State private var isTesting = false
    @FocusState private var focusedField: Field?
    private enum Field { case address, token }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 18) {
                    Text("服务器设置")
                        .font(.title)
                        .foregroundStyle(.primary)

                    Text("连接到你的私人服务器")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                VStack(spacing: 14) {
                    TextField("服务器地址", text: $address)
                        .keyboardType(.URL).textContentType(.URL)
                        .focused($focusedField, equals: .address)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .token }
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    SecureField(model.hasToken ? "Token（留空保留已有令牌）" : "Token（可选）", text: $token)
                        .focused($focusedField, equals: .token)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Spacer()

                VStack(spacing: 14) {
                    Button {
                        focusedField = nil
                        isTesting = true
                        result = nil
                        testRequest = UUID()
                    } label: {
                        Group {
                            if isTesting { ProgressView().frame(maxWidth: .infinity) }
                            else { Text("测试").frame(maxWidth: .infinity) }
                        }.padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTesting || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("测试当前填写的服务器")
                    .buttonBorderShape(.capsule)

                    Button {
                        if let error = model.saveConnection(address: address, token: token) {
                            result = error
                        } else {
                            token = ""
                            dismiss()
                            Task { await model.loadCalendar(force: true) }
                        }
                    } label: {
                        Text("保存").frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonBorderShape(.capsule)

                    if let result {
                        Text(result).font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 480).frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .tint(PulseStyle.red)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("关闭服务器配置")
                }
            }
            .onAppear { address = model.serverText }
            .onChange(of: address) { _, _ in invalidateTest() }
            .onChange(of: token) { _, _ in invalidateTest() }
            .task(id: testRequest) {
                guard testRequest != nil else { return }
                do {
                    let server = try ServerAddress(rawValue: address)
                    let typedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    let credential = typedToken.isEmpty ? (server.url == model.serverURL ? model.currentToken : nil) : typedToken
                    let health = try await APIClient(baseURL: server.url).health(token: credential)
                    guard !Task.isCancelled else { return }
                    result = health.database && health.status == "ok" ? "连接成功" : "服务已响应，数据库暂不可用"
                } catch {
                    guard !Task.isCancelled else { return }
                    result = MobileModel.message(for: error)
                }
                isTesting = false
            }
        }
    }

    private func invalidateTest() {
        testRequest = nil
        isTesting = false
        result = nil
    }
}
