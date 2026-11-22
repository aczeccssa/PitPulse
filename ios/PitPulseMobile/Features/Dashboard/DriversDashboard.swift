import SharedComponents
import SharedData
import SwiftUI

struct DriversDashboard: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var showsStandings: Bool
    var showsSectionPicker = true
    @State private var selectedStanding: StandingEntry?
    @State private var wideStandings = false
    @State private var compactStanding = false
    @State private var query = ""
    @State private var rosterLoading = true
    @State private var constructors: [ConstructorStanding] = []
    @FocusState private var searchFocused: Bool
    @Namespace private var transition

    init(showsStandings: Binding<Bool>, showsSectionPicker: Bool = true, initialStanding: StandingEntry? = nil) {
        _showsStandings = showsStandings
        self.showsSectionPicker = showsSectionPicker
        _selectedStanding = State(initialValue: initialStanding)
    }

    private var roster: [DriverStanding] {
        model.driverRoster.sorted { $0.position < $1.position }
    }

    private var archive: APIEnvelope<[SeasonResultWeekend]>? { model.seasonArchive }

    private var displayedStanding: StandingEntry? {
        guard !showsSectionPicker else { return selectedStanding }
        let id = selectedStanding?.id
        return (roster.first { $0.id == id } ?? roster.first).map(StandingEntry.init(driver:))
    }

    var body: some View {
        StandingColumns(wide: $wideStandings, selected: displayedStanding, driversDesign: true,
                        tabletDriverProfile: !showsSectionPicker) {
            driverList
        }
        .onChange(of: wideStandings) { _, wide in
            compactStanding = !wide && selectedStanding != nil
        }
        .navigationDestination(isPresented: $compactStanding) {
            if let selectedStanding { StandingProfile(entry: selectedStanding, driversDesign: true) }
        }
    }

    private var driverList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if showsSectionPicker {
                    PulseSectionPicker(sections: [(true, "Standings"), (false, "Directory")], selection: $showsStandings)
                }
                Group {
                    if roster.isEmpty {
                        rosterStatus
                    } else if showsStandings {
                        standings
                    } else {
                        directory
                    }
                }
                .transition(.opacity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(WebDashboardStyle.homeText)
        .background(WebDashboardStyle.homeBackground)
        .pulseSwap(showsStandings)
        .pulseSwap(roster.isEmpty)
        .onChange(of: showsStandings) { _, _ in searchFocused = false }
        .task(id: model.dataContext) { await load() }
        .refreshable { await load(force: true) }
    }

    private func load(force: Bool = false) async {
        let context = model.dataContext
        let season = model.season
        rosterLoading = true
        async let history: Void = model.loadSeasonArchive(force: force)
        async let teams = model.serverURL.map { APIClient(baseURL: $0) }?
            .constructorStandings(season: season, token: model.currentToken)
        await model.loadF1Roster(force: force)
        if !Task.isCancelled { rosterLoading = false }
        if let response = try? await teams, model.dataContext == context, !Task.isCancelled {
            constructors = response.data
        }
        await history
    }

    @ViewBuilder private var rosterStatus: some View {
        if rosterLoading {
            PulseSkeleton(rows: 5, label: "Loading drivers…")
        } else {
            ContentUnavailableView {
                Label("Drivers Unavailable", systemImage: "person.2")
            } description: {
                Text(model.rosterLoadError?.pulseEnglishError ?? "No driver standings are available for this season.")
            } actions: {
                Button("Retry") { Task { await load(force: true) } }.buttonStyle(.glass)
            }
        }
    }

    @ViewBuilder private var directory: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search drivers or teams", text: $query)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("drivers.search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 48)
        .dashboardPanel(WebDashboardStyle.homePanel)

        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = roster.filter { driver in
            let number = driver.driverNumber ?? ""
            return search.isEmpty || [driver.driverName, driver.seasonTeamName, number, "#\(number)"]
                .filter { !$0.isEmpty && $0 != "#" }.contains { $0.localizedStandardContains(search) }
        }
        if matching.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            let teams = Dictionary(grouping: matching, by: driverTeamID)
            let allTeams = Dictionary(grouping: roster, by: driverTeamID)
            let positions = Dictionary(constructors.filter { $0.season == model.season }.map { (MobileModel.normalizedConstructorID($0.id), $0.position) },
                                       uniquingKeysWith: min)
            ForEach(teams.keys.sorted { left, right in
                (positions[left] ?? .max, allTeams[left]?.first?.position ?? .max, left)
                    < (positions[right] ?? .max, allTeams[right]?.first?.position ?? .max, right)
            }, id: \.self) { team in
                if let members = teams[team], let first = members.first {
                    teamPanel(title: constructors.first { $0.season == model.season && MobileModel.normalizedConstructorID($0.id) == team }?.constructorName
                              ?? first.seasonTeamName, representative: first, members: members)
                }
            }
        }
    }

    private func teamPanel(title: String, representative: DriverStanding?, members: [DriverStanding]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let representative { DriversTeamLogo(driver: representative) }
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            }
            .padding(.bottom, 8)
            ForEach(members) { driver in
                Divider()
                driverLink(driver, source: "directory") {
                    HStack(spacing: 10) {
                        driverIdentity(driver, subtitle: representative == nil ? driver.constructor : nil)
                        if let number = driver.driverNumber, !number.isEmpty {
                            PulseNumber("#\(number)").font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .dashboardPanel(WebDashboardStyle.homePanel)
    }

    @ViewBuilder private var standings: some View {
        if let leader = roster.first {
            standingsLeader(leader)
            if !showsSectionPicker { standingsTable(leader: leader) }

            NavigationLink {
                DriversSeasonCharts(entries: roster.map(StandingEntry.init(driver:)))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line").foregroundStyle(PulseStyle.red)
                    Text("Season Charts").font(.headline)
                    Spacer()
                    chevron
                }
                .padding(14)
                .frame(minHeight: 48)
                .dashboardPanel(WebDashboardStyle.homePanel)
            }
            .buttonStyle(PulsePressStyle())
            .accessibilityIdentifier("drivers.seasonCharts")
            if showsSectionPicker { standingsTable(leader: leader) }
        }
    }

    private func standingsLeader(_ leader: DriverStanding) -> some View {
        driverLink(leader, source: "leader") {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(model.season.formatted(.number.grouping(.never))) Championship Leader")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    driverIdentity(leader, subtitle: leader.seasonTeamName, helmetSize: 54)
                    VStack(alignment: .trailing, spacing: 1) {
                        PulseNumber(leader.points.formatted()).font(.title2.bold().monospacedDigit())
                        Text("Points").font(.caption).foregroundStyle(.secondary)
                    }
                    chevron
                }
            }
            .padding(14)
            .dashboardPanel(WebDashboardStyle.homePanel)
        }
    }

    private func standingsTable(leader: DriverStanding) -> some View {
        let movement = archive.flatMap { $0.meta.stale ? nil : RoundMovement(entries: roster.map(StandingEntry.init(driver:)), weekends: $0.data, teams: false) }
        return VStack(alignment: .leading, spacing: 0) {
            if !showsSectionPicker {
                let title = "\(String(model.season)) F1 Driver Standings"
                Text(title).font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 10)
            }

            HStack(spacing: 8) {
                Text("Driver").frame(maxWidth: .infinity, alignment: .leading)
                Text("Points / Gap").multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, wideStandings ? 8 : 0)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.vertical, 10)
            ForEach(roster) { driver in
                Divider()
                driverLink(driver, source: "standing") {
                    HStack(spacing: 9) {
                        VStack(spacing: 2) {
                            PulseNumber("\(driver.position)").font(.subheadline.weight(.semibold))
                                .accessibilityLabel("Position \(driver.position)")
                            if let previous = movement?.previousRanks[driver.id], previous != driver.position {
                                let places = previous - driver.position
                                Image(systemName: places > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(places > 0 ? Color.green : PulseStyle.red)
                                    .accessibilityLabel(places > 0 ? "Moved up \(places)" : "Moved down \(-places)")
                            }
                        }.frame(minWidth: 23)
                        driverIdentity(driver, subtitle: driver.seasonTeamName)
                        VStack(alignment: .trailing, spacing: 2) {
                            PulseNumber(driver.points.formatted()).font(.subheadline.weight(.semibold))
                            if driver.id != leader.id {
                                PulseNumber((driver.points - leader.points).formatted(.number.sign(strategy: .always())))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .dashboardPanel(WebDashboardStyle.homePanel)
    }

    private func driverLink<Label: View>(_ driver: DriverStanding, source: String, @ViewBuilder label: () -> Label) -> some View {
        let id = "\(source).\(driver.id)"
        let entry = StandingEntry(driver: driver)
        return Group {
            if wideStandings {
                let selected = displayedStanding?.id == entry.id
                Button { selectedStanding = entry } label: {
                    label().padding(.horizontal, source == "leader" ? 0 : 8)
                        .frame(minHeight: 54).contentShape(.rect)
                        .background(selected && source != "leader" ? PulseStyle.red.opacity(0.10) : .clear, in: .rect(cornerRadius: 6))
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            } else {
                NavigationLink {
                    StandingProfile(entry: entry, driversDesign: true)
                        .pulseNavigationZoom(id, in: transition)
                } label: {
                    label().frame(minHeight: 54).contentShape(.rect)
                        .matchedTransitionSource(id: id, in: transition)
                }
                .navigationLinkIndicatorVisibility(.hidden)
            }
        }
        .buttonStyle(PulsePressStyle())
        .accessibilityIdentifier("drivers.\(id)")
    }

    private func driverIdentity(_ driver: DriverStanding, subtitle: String?, helmetSize: CGFloat = 37) -> some View {
        HStack(spacing: 9) {
            if !typeSize.isAccessibilitySize {
                AssetImage(name: StandingEntry(driver: driver).asset).frame(width: helmetSize, height: helmetSize)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(driver.driverName).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            if model.favoriteDriverID == driver.id {
                Image(systemName: "heart.fill").font(.caption2).foregroundStyle(PulseStyle.red)
                    .accessibilityLabel("Favorite driver")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.tertiary).accessibilityHidden(true)
    }
}

private func driverTeamID(_ driver: DriverStanding) -> String {
    driver.seasonTeamID
}

extension DriverStanding {
    var seasonTeamID: String {
        if season == 2026, id == "lawson" { return "rb" }
        return constructorIds.first.map(MobileModel.normalizedConstructorID) ?? constructor
    }

    var seasonTeamName: String {
        if season == 2026, id == "lawson" { return "Racing Bulls" }
        return constructor
    }
}

private struct DriversTeamLogo: View {
    let driver: DriverStanding

    var body: some View {
        Group {
            if let logo = DashboardArt.image(.teamLogo, id: driverTeamID(driver), season: driver.season) {
                Image(uiImage: logo).resizable().scaledToFit()
            } else {
                Image(systemName: "flag.checkered").foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 22)
        .accessibilityHidden(true)
    }
}

private struct DriversSeasonCharts: View {
    @EnvironmentObject private var model: MobileModel
    let entries: [StandingEntry]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let archive = model.seasonArchive, !archive.data.isEmpty {
                    ChampionshipSeasonCharts(entries: entries, weekends: archive.data, usingTeams: false, driversDesign: true)
                } else if let error = model.seasonArchiveError {
                    ContentUnavailableView {
                        Label("Season Charts Unavailable", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text(error.pulseEnglishError)
                    } actions: {
                        Button("Retry") { Task { await model.loadSeasonArchive(force: true) } }.buttonStyle(.glass)
                    }
                } else if model.seasonArchive != nil {
                    ContentUnavailableView("No Season Results Yet", systemImage: "flag.checkered")
                } else {
                    PulseSkeleton(label: "Loading season charts…", chart: true)
                }
            }
            .padding(16)
        }
        .background(WebDashboardStyle.homeBackground)
        .navigationTitle("Season Charts")
        .navigationBarTitleDisplayMode(.inline)
        .dashboardDetail()
        .task(id: model.dataContext) { await model.loadSeasonArchive() }
        .refreshable { await model.loadSeasonArchive(force: true) }
    }
}

struct SeasonChartFilter: View {
    let entries: [StandingEntry]
    @Binding var selected: Set<String>?
    let title: String
    let dismiss: () -> Void

    static let icon = "line.3.horizontal.decrease"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Select All") { selected = nil }.disabled(selected == nil || selected?.count == entries.count)
                    Spacer()
                    Button("Clear") { selected = [] }.disabled(selected?.isEmpty == true)
                }
                .buttonStyle(.glass)

                VStack(spacing: 0) {
                    ForEach(entries, id: \.id) { entry in
                        if entry.id != entries.first?.id { Divider() }
                        let checked = selected?.contains(entry.id) ?? true
                        Button {
                            var ids = selected ?? Set(entries.map(\.id))
                            if checked { ids.remove(entry.id) } else { ids.insert(entry.id) }
                            selected = ids
                        } label: {
                            HStack(spacing: 10) {
                                AssetImage(name: entry.asset).frame(width: 34, height: 33)
                                Text(entry.name).font(.subheadline.weight(.semibold))
                                Spacer(minLength: 4)
                                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checked ? PulseStyle.red : Color.secondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: 48)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(checked ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 14)
                .dashboardPanel(WebDashboardStyle.homePanel)
            }
            .padding(16)
        }
        .background(WebDashboardStyle.homeBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark", action: dismiss).labelStyle(.iconOnly)
            }
        }
    }
}
