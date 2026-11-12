import SharedComponents
import SwiftUI
import SceneKit
import SharedData

struct SettingsScreen: View {
    @EnvironmentObject private var model: MobileModel
    @State private var serverConfigurationPresented = false
    @State private var serverReachable: Bool?
    @State private var widgetPreviewPresented = false
    @State private var islandPreviewPresented = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mobileAppearance") private var appearance = "system"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image("logo-foreground.png").resizable().scaledToFit().frame(width: 42, height: 42)
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
                    Button {
                        islandPreviewPresented = true
                    } label: {
                        HStack {
                            Text("灵动岛显示")
                            Spacer()
                            Text(model.islandMode.title).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel("灵动岛显示：\(model.islandMode.title)")
                    #if DEBUG
                    Button { widgetPreviewPresented = true } label: {
                        HStack {
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
                    LabeledContent("数据层", value: model.hasToken ? "SharedData · Token 已保存" : "SharedData")
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
        .sheet(isPresented: $islandPreviewPresented) {
            IslandModePreviewSheet()
                .environmentObject(model)
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
