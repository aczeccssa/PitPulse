import SharedComponents
import SwiftUI
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
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    settingsPanel("Server") {
                        Button { serverConfigurationPresented = true } label: {
                            settingsRow("Server Connection", symbol: "server.rack") {
                                HStack(spacing: 8) {
                                    Text(connectionStatus)
                                        .foregroundStyle(serverReachable == true ? Color.green : .secondary)
                                    PulseChevron()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Configure server")
                        .accessibilityValue(connectionStatus)

                        if let url = model.serverURL {
                            Divider()
                            Link(destination: url) {
                                HStack {
                                    Text(model.serverText)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.up.right")
                                        .accessibilityHidden(true)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minHeight: 44)
                            }
                            .tint(.secondary)
                        }
                    }

                    settingsPanel("Preferences") {
                        Menu {
                            Picker("Season", selection: $model.season) {
                                ForEach(2023...max(2027, model.season), id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                        } label: {
                            settingsRow("Season", symbol: "calendar") { menuValue(String(model.season)) }
                        }
                        .tint(.primary)
                        .accessibilityLabel("Season")
                        .accessibilityValue(String(model.season))

                        Divider()

                        Menu {
                            Picker("Appearance", selection: $appearance) {
                                Text("System").tag("system")
                                Text("Light").tag("light")
                                Text("Dark").tag("dark")
                            }
                        } label: {
                            settingsRow("Appearance", symbol: "circle.lefthalf.filled") { menuValue(appearanceTitle) }
                        }
                        .tint(.primary)
                        .accessibilityLabel("Appearance")
                        .accessibilityValue(appearanceTitle)

                        Divider()

                        VStack(alignment: .leading, spacing: 0) {
                            settingsRow("Preferred Live Series", symbol: "antenna.radiowaves.left.and.right") {
                                LiveSeriesPicker(series: LiveSeries.allCases, selected: model.preferredLiveSeries) {
                                    model.preferredLiveSeries = $0
                                }
                            }
                        }

                        Divider()

                        NavigationLink {
                            FavoriteDriverScreen()
                        } label: {
                            settingsRow("Favorite Driver", symbol: "heart") {
                                Text(model.favoriteStanding?.driverName ?? "None")
                                    .lineLimit(1)
                                PulseChevron()
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.favorite")
                    }

                    settingsPanel("Widgets") {
                        Button { islandPreviewPresented = true } label: {
                            settingsRow("Dynamic Island Mode", symbol: "capsule.portrait") {
                                Text(model.islandMode.englishTitle)
                                PulseChevron()
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dynamic Island mode: \(model.islandMode.englishTitle)")
                        #if DEBUG
                        Divider()
                        Button { widgetPreviewPresented = true } label: {
                            settingsRow("Widget Previews", symbol: "rectangle.3.group") { PulseChevron() }
                        }
                        .buttonStyle(.plain)
                        #endif
                    }

                    settingsPanel("About") {
                        settingsRow("Version", symbol: "info.circle") {
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                                .monospacedDigit()
                        }
                    }
                }
                .padding(16)
            }
            .background(PulseStyle.background)
            .tint(PulseStyle.red)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close settings")
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
        // Keep sheet presentation on the settings root.
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
            NavigationStack { WidgetPreviewGallery().background(PulseStyle.background) }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #endif
    }


    private var connectionStatus: String {
        guard model.serverURL != nil else { return "Not configured" }
        switch serverReachable {
        case true?: return "Available"
        case false?: return "Unavailable"
        case nil: return "Checking"
        }
    }

    private var appearanceTitle: String {
        switch appearance {
        case "light": "Light"
        case "dark": "Dark"
        default: "System"
        }
    }

    private func settingsPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0, content: content)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .dashboardPanel(WebDashboardStyle.homePanel)
        }
    }

    private func settingsRow<Value: View>(_ title: String, symbol: String,
                                          @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PulseStyle.red)
                .frame(width: 32, height: 32)
                .background(PulseStyle.red.opacity(0.10), in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
            value().font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(minHeight: 50)
        .contentShape(.rect)
    }

    private func menuValue(_ title: String) -> some View {
        HStack(spacing: 7) {
            Text(title)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)
        }
    }
}

struct FavoriteDriverScreen: View {
    @EnvironmentObject private var model: MobileModel

    var body: some View {
        DriverChoiceScreen(title: "Favorite Driver", selected: model.favoriteDriverID,
                           clear: { model.favoriteDriverID = nil }) { driver in
            model.favoriteDriverID = driver.id
        }
    }
}

struct DriverChoiceScreen: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    let title: String
    let selected: String?
    var excluding: String? = nil
    var clear: (() -> Void)? = nil
    let choose: (DriverStanding) -> Void

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let drivers = model.driverRoster.filter { driver in
            driver.id != excluding && (query.isEmpty || [driver.driverName, driver.constructor, driver.driverNumber ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { ($0.constructor, $0.driverName) < ($1.constructor, $1.driverName) }
        let teams = Dictionary(grouping: drivers, by: \.constructor)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if query.isEmpty, let clear, selected != nil {
                    Button(role: .destructive) {
                        clear()
                        dismiss()
                    } label: {
                        Label("Remove favorite", systemImage: "heart.slash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PulseStyle.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 48)
                            .dashboardPanel(WebDashboardStyle.homePanel)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(teams.keys.sorted(), id: \.self) { team in
                    if let roster = teams[team] {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(team)
                                .font(.headline)
                                .padding(.leading, 4)
                                .accessibilityAddTraits(.isHeader)
                            VStack(spacing: 0) {
                                ForEach(roster) { driver in
                                    if driver.id != roster.first?.id { Divider() }
                                    driverRow(driver)
                                }
                            }
                            .padding(.horizontal, 14)
                            .dashboardPanel(WebDashboardStyle.homePanel)
                        }
                    }
                }
                if model.driverRoster.isEmpty {
                    if let error = model.rosterLoadError {
                        ContentUnavailableView {
                            Label("Couldn't Load Drivers", systemImage: "person.crop.circle")
                        } description: {
                            Text(error.pulseEnglishError)
                        } actions: {
                            Button("Retry") { Task { await model.loadF1Roster(force: true) } }
                        }
                    } else {
                        PulseSkeleton(label: "Loading drivers…").padding(24)
                            .frame(maxWidth: .infinity)
                    }
                } else if drivers.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .padding(16)
        }
        .background(PulseStyle.background)
        .pulseSwap(model.driverRoster.isEmpty)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Driver or team")
        .task(id: model.dataContext) { await model.loadF1Roster() }
        .refreshable { await model.loadF1Roster(force: true) }
    }

    private func driverRow(_ driver: DriverStanding) -> some View {
        Button {
            choose(driver)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                AssetImage(name: StandingEntry(driver: driver).asset)
                    .frame(width: 38, height: 34)
                Text(driver.driverName).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if let number = driver.driverNumber {
                    Text("#\(number)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if selected == driver.id {
                    Image(systemName: "heart.fill").foregroundStyle(PulseStyle.red)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == driver.id ? .isSelected : [])
        .accessibilityIdentifier("driver.choice.\(driver.id)")
    }
}
