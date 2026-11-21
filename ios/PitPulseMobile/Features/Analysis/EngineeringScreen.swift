import Charts
import SharedData
import SwiftUI

struct EngineeringScreen: View {
    @EnvironmentObject private var model: MobileModel
    @State private var features: SeasonFeatures?
    @State private var error: String?

    var body: some View {
        List {
            ForEach(Topic.allCases.filter { available($0) }) { topic in
                NavigationLink {
                    EngineeringDetail(topic: topic)
                } label: {
                    Label(topic.title, systemImage: topic.symbol)
                }.listRowSeparator(.hidden)
            }
            if let error { Text(error).foregroundStyle(.secondary) }
        }.listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(PulseStyle.background)
            .task(id: model.dataContext) {
                features = nil
                await load()
            }
            .refreshable { await load() }
    }

    private func available(_ topic: Topic) -> Bool {
        switch topic {
        case .upgrades: true
        case .power: features?.powerUnit == true
        case .damage: features?.destructors == true
        }
    }

    private func load() async {
        guard let url = model.serverURL else { error = "Invalid server address"; return }
        let context = model.dataContext
        do {
            let response = try await APIClient(baseURL: url).seasonFeatures(season: model.season, token: model.currentToken)
            guard context == model.dataContext, !Task.isCancelled else { return }
            features = response.data
            error = nil
        } catch {
            guard context == model.dataContext, !Task.isCancelled else { return }
            self.error = MobileModel.message(for: error).pulseEnglishError
        }
    }

    enum Topic: String, CaseIterable, Identifiable {
        case upgrades, power, damage
        var id: Self { self }
        var title: String {
            switch self {
            case .upgrades: "Technical Upgrades"
            case .power: "Power Units"
            case .damage: "Crash Costs"
            }
        }
        var symbol: String {
            switch self {
            case .upgrades: "wrench.and.screwdriver"
            case .power: "engine.combustion"
            case .damage: "exclamationmark.triangle"
            }
        }
    }
}

struct EngineeringDetail: View {
    @Environment(\.openDashboardDriverProfile) private var openDriverProfile
    @EnvironmentObject private var model: MobileModel
    let topic: EngineeringScreen.Topic
    var tabletWorkspace = false
    @State private var updates: [TechnicalUpdate] = []
    @State private var power: PowerUnitReport?
    @State private var damage: DamageReport?
    @State private var metadata: EngineeringMetadata?
    @State private var loaded = false
    @State private var error: String?
    @State private var round: Int?
    @State private var team = ""
    @State private var excludedConstructors: Set<String> = []
    @State private var excludedDrivers: Set<String> = []
    @State private var excludedElements: Set<String> = []
    @State private var excludedUpgradeTypes: Set<String> = []
    @State private var excludedUpgradeReasons: Set<String> = []
    @State private var highlightMajorUpgrades = false

    var body: some View {
        List {
            if let metadata { quality(metadata) }
            if let error {
                Text(error).foregroundStyle(.secondary)
                if tabletWorkspace {
                    Button("Try again") { Task { await load() } }
                }
            }
            if loaded {
                switch topic {
                case .upgrades:
                    if tabletWorkspace { upgradesWorkspace } else { upgrades }
                case .power: powerUnits
                case .damage:
                    if tabletWorkspace { damageWorkspace } else { incidents }
                }
            } else if error == nil {
                PulseSkeleton(label: "Loading \(topic.title)…", chart: true)
            }
        }.listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(PulseStyle.background)
            .pulseSwap(loaded)
            .navigationTitle(topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: model.dataContext) {
                loaded = false
                error = nil
                metadata = nil
                round = nil
                team = ""
                excludedConstructors.removeAll()
                excludedDrivers.removeAll()
                excludedElements.removeAll()
                excludedUpgradeTypes.removeAll()
                excludedUpgradeReasons.removeAll()
                await load()
            }
            .refreshable { await load() }
    }

    private func quality(_ meta: EngineeringMetadata) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text([String(model.season), meta.source, meta.quality?.rawValue.capitalized,
                  meta.stale == true ? "Stale" : nil, meta.unavailable == true ? "No Data Available" : nil]
                .compactMap { $0 }.joined(separator: " · "))
            if let sections = meta.sections {
                ForEach(sections.keys.sorted(), id: \.self) { key in
                    if let section = sections[key] {
                        let labels = [
                            section.source,
                            section.quality?.rawValue.capitalized,
                            section.coverage?.complete == false ? "Partial Coverage" : nil,
                            section.unavailable == true ? "No Data Available" : nil,
                            section.stale == true ? "Stale" : nil
                        ].compactMap { $0 }
                        if !labels.isEmpty {
                            let names = ["usage": "Usage", "elements": "Components", "penalties": "Penalties", "incidents": "Incidents", "corrections": "Revisions"]
                            Text("\(names[key] ?? key) · \(labels.joined(separator: " · "))")
                        }
                    }
                }
            }
        }.font(.footnote).foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder private var upgradesWorkspace: some View {
        HStack {
            reportFilter("Constructors", options: updates.compactMap(\.team), excluded: $excludedConstructors)
            reportFilter("Types", options: updates.compactMap(\.type), excluded: $excludedUpgradeTypes)
            reportFilter("Primary Reasons", options: updates.compactMap(\.reason), excluded: $excludedUpgradeReasons)
        }
        .listRowSeparator(.hidden)
        let rows = updates.filter {
            !excludedConstructors.contains($0.team ?? "")
                && !excludedUpgradeTypes.contains($0.type ?? "")
                && !excludedUpgradeReasons.contains($0.reason ?? "")
        }
        if rows.isEmpty {
            ContentUnavailableView(updates.isEmpty ? "No upgrades recorded" : "No matching upgrades", systemImage: topic.symbol)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    upgradeOverview(rows)
                        .frame(minWidth: 530)
                    upgradeBars("Updated Components", values: rows.compactMap(\.component))
                        .frame(width: 270)
                }
                VStack(alignment: .leading, spacing: 14) {
                    upgradeOverview(rows)
                    upgradeBars("Updated Components", values: rows.compactMap(\.component))
                }
            }
            .listRowSeparator(.hidden)
        }
    }

    private struct UpgradePoint: Identifiable {
        let team: String
        let round: Int
        let count: Int
        let cumulative: Int
        let hasMajor: Bool
        var id: String { "\(team):\(round)" }
    }

    private func upgradeOverview(_ rows: [TechnicalUpdate]) -> some View {
        let rounds = Set(rows.compactMap(\.round)).sorted()
        let teams = Dictionary(grouping: rows.filter { $0.team != nil }, by: { $0.team ?? "" })
        let points = teams.keys.sorted().flatMap { team in
            let grouped = Dictionary(grouping: teams[team, default: []], by: \.round)
            var total = 0
            return rounds.map { round in
                let updates = grouped[round, default: []]
                total += updates.count
                return UpgradePoint(team: team, round: round, count: updates.count, cumulative: total,
                                    hasMajor: updates.contains { $0.major == true })
            }
        }
        let activePoints = points.filter { $0.count > 0 }
        return VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                upgradeBars("Updates per Team", values: rows.compactMap(\.team))
                upgradeDonut("Types of Upgrades", values: rows.compactMap(\.type))
                upgradeDonut("Primary Reasons for Updates", values: rows.compactMap(\.reason))
            }
            upgradeCard("Updates by Team and Grand Prix") {
                Chart(activePoints) { item in
                    BarMark(x: .value("Updates", item.count), y: .value("Round", "R\(item.round)"))
                        .foregroundStyle(WebDashboardStyle.chartTeamColor(item.team))
                }.frame(height: CGFloat(max(rounds.count, 1)) * 22 + 54)
            }
            upgradeCard("Tech Updates Over Time") {
                Toggle("Highlight major updates", isOn: $highlightMajorUpgrades)
                Chart(activePoints) { item in
                    PointMark(x: .value("Round", item.round), y: .value("Team", item.team))
                        .symbolSize(by: .value("Updates", item.count))
                        .foregroundStyle(WebDashboardStyle.chartTeamColor(item.team))
                    if highlightMajorUpgrades && item.hasMajor {
                        PointMark(x: .value("Round", item.round), y: .value("Team", item.team))
                            .symbolSize(by: .value("Updates", item.count))
                            .symbol {
                                Circle().strokeBorder(WebDashboardStyle.chartTeamColor(item.team),
                                                      style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                                    .padding(-3)
                            }
                    }
                }.frame(height: CGFloat(max(teams.count, 1)) * 26 + 54)
            }
            upgradeCard("Cumulative Updates by Team and Grand Prix") {
                Chart(points) { item in
                    LineMark(x: .value("Round", item.round), y: .value("Updates", item.cumulative),
                             series: .value("Team", item.team))
                        .foregroundStyle(WebDashboardStyle.chartTeamColor(item.team))
                }.frame(height: 220)
            }
        }
    }

    private func upgradeCounts(_ values: [String]) -> [(name: String, count: Int)] {
        Dictionary(grouping: values, by: { $0 }).map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    private func upgradeBars(_ title: String, values: [String]) -> some View {
        let counts = upgradeCounts(values)
        let teams = title == "Updates per Team"
        let tint = Color(red: 225 / 255, green: 6 / 255, blue: 0)
        return upgradeCard(title) {
            if counts.isEmpty {
                Text("No data available for this selection.").foregroundStyle(WebDashboardStyle.homeMuted)
            } else {
                Chart(counts, id: \.name) { item in
                    BarMark(x: .value("Updates", item.count), y: .value("Category", item.name))
                        .foregroundStyle(teams ? WebDashboardStyle.chartTeamColor(item.name) : tint)
                        .annotation(position: .trailing) { Text(String(item.count)).font(.caption2) }
                }
                .chartYScale(domain: counts.map(\.name))
                .frame(height: CGFloat(counts.count) * 24 + 30)
            }
        }
    }

    private func upgradeDonut(_ title: String, values: [String]) -> some View {
        let counts = upgradeCounts(values)
        let total = counts.reduce(0) { $0 + $1.count }
        let palette: [UInt32] = [0xe10600, 0xffda4b, 0x1f75ef]
        func color(_ index: Int) -> Color {
            let hex = palette.indices.contains(index) ? palette[index] : 0x64748b
            return WebDashboardStyle.adaptive(dark: hex, light: hex)
        }
        return upgradeCard(title) {
            if counts.isEmpty {
                Text("No data available for this selection.").foregroundStyle(WebDashboardStyle.homeMuted)
            } else {
                Chart(Array(counts.enumerated()), id: \.offset) { index, item in
                    SectorMark(angle: .value("Updates", item.count), innerRadius: .ratio(0.57), angularInset: 1)
                        .foregroundStyle(color(index))
                        .accessibilityLabel(item.name)
                        .accessibilityValue(String(item.count))
                }
                .chartBackground { _ in
                    VStack(spacing: 2) {
                        Text(String(total)).font(.title3.bold())
                        Text("updates").font(.caption2).foregroundStyle(WebDashboardStyle.homeMuted)
                    }
                }
                .frame(minHeight: 150)
                ForEach(Array(counts.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 6) {
                        Circle().fill(color(index)).frame(width: 7, height: 7)
                        Text(item.name)
                        Spacer(minLength: 4)
                        Text(String(item.count)).monospacedDigit()
                    }
                    .font(.caption2)
                }
            }
        }
    }

    private func upgradeCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PulseStyle.surface, in: .rect(cornerRadius: 10))
    }

    private var upgrades: some View {
        Group {
            filters(rounds: updates.compactMap(\.round), teams: updates.compactMap(\.team))
            let rows = updates.filter { (round == nil || round == $0.round) && (team.isEmpty || team == $0.team) }
            if !rows.isEmpty {
                if team.isEmpty { upgradeChart(rows) }
                upgradeTimeline(rows)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, update in
                VStack(alignment: .leading, spacing: 5) {
                    Text(update.component ?? "Upgrades").font(.headline)
                    Text([update.round.map { "R\($0)" }, update.country, update.team, update.type]
                        .compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                    if let reason = update.reason { Text(reason).font(.subheadline) }
                }.padding(.vertical, 5).listRowSeparator(.hidden)
            }
            if rows.isEmpty { ContentUnavailableView("No upgrades recorded", systemImage: topic.symbol) }
        }
    }

    private func upgradeChart(_ rows: [TechnicalUpdate]) -> some View {
        var counts: [String: Int] = [:]
        for team in rows.compactMap(\.team) {
            counts[team, default: 0] += 1
        }
        let teams = counts.keys.sorted {
            let first = counts[$0, default: 0]
            let second = counts[$1, default: 0]
            return first == second ? $0 < $1 : first > second
        }
        return Section("Upgrades by Team") {
            Chart(teams, id: \.self) { team in
                BarMark(x: .value("Count", counts[team, default: 0]), y: .value("Team", team))
                    .foregroundStyle(PulseStyle.red)
            }.pulseChart().frame(height: CGFloat(max(1, teams.count)) * 27 + 26)
        }
    }

    @ViewBuilder private func upgradeTimeline(_ rows: [TechnicalUpdate]) -> some View {
        let counts = Dictionary(grouping: rows.compactMap(\.round), by: { $0 })
            .mapValues(\.count)
        let rounds = counts.keys.sorted()
        if !rounds.isEmpty {
            Section("Upgrades by Round") {
                Chart(rounds, id: \.self) { round in
                    BarMark(x: .value("Round", round), y: .value("Upgrades", counts[round, default: 0]))
                        .foregroundStyle(.teal).cornerRadius(3)
                }.pulseChart().frame(height: 145)
                let groups = Dictionary(grouping: rows.compactMap(\.type), by: { $0 })
                    .mapValues(\.count)
                let categories = groups.keys.sorted()
                if !categories.isEmpty {
                    Chart(categories, id: \.self) { category in
                        SectorMark(angle: .value("Count", groups[category, default: 0]),
                                   innerRadius: .ratio(0.63), angularInset: 2)
                            .foregroundStyle(by: .value("Category", category))
                    }.pulseChart().frame(height: 170)
                }
            }.listRowBackground(PulseStyle.surface)
        }
    }

    @ViewBuilder private var powerUnits: some View {
        if let power {
            if tabletWorkspace {
                HStack {
                    reportFilter("Constructors", options: power.usage.compactMap(\.team), excluded: $excludedConstructors)
                    reportFilter("Drivers", options: power.usage.compactMap(\.driverCode), excluded: $excludedDrivers)
                    reportFilter("Elements", options: power.elements.map(\.code), excluded: $excludedElements)
                }
                .listRowSeparator(.hidden)
                let usage = power.usage.filter {
                    !excludedConstructors.contains($0.team ?? "") && !excludedDrivers.contains($0.driverCode ?? "")
                }
                let elements = power.elements.filter { !excludedElements.contains($0.code) }
                powerOverview(usage: usage, elements: elements)
            } else {
                Section("Component Usage") {
                    ForEach(Array(power.usage.enumerated()), id: \.offset) { _, usage in
                        DisclosureGroup {
                            ForEach(power.elements, id: \.code) { element in
                                let count = usage.count(for: element.code)
                                VStack(alignment: .leading, spacing: 4) {
                                    LabeledContent(element.name, value: [
                                        count.map(String.init) ?? "—", element.quota.map(String.init) ?? "—"
                                    ].joined(separator: " / "))
                                    if let count, let quota = element.quota, quota > 0 {
                                        ProgressView(value: min(Double(count), Double(quota)), total: Double(quota))
                                            .tint(count > quota ? PulseStyle.red : .teal)
                                            .accessibilityLabel(count > quota ? "Over Quota" : "Quota Usage")
                                    }
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(usage.driverName ?? "Unknown driver").font(.headline)
                                Text([usage.team, usage.engineManufacturer].compactMap { $0 }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if power.usage.isEmpty { Text("No usage recorded").foregroundStyle(.secondary) }
                }
            }
            let penalties = power.penalties.filter { item in
                !tabletWorkspace || (
                    !excludedConstructors.contains(item.constructorName ?? "")
                    && !excludedDrivers.contains(item.driverCode ?? "")
                    && (excludedElements.isEmpty || item.elements?.contains {
                        let code = powerElementCode($0)
                        return power.elements.contains { powerElementCode($0.code) == code && !excludedElements.contains($0.code) }
                    } == true)
                )
            }
            if tabletWorkspace {
                powerPenaltyTable(penalties, hasReports: !power.penalties.isEmpty)
                    .listRowSeparator(.hidden)
            } else {
                Section("Penalties") {
                    ForEach(Array(penalties.enumerated()), id: \.offset) { _, item in
                        LabeledContent {
                            Text(item.startsFromPitLane == true ? "Pit lane start" : item.gridPositions.map { "\($0)-place grid penalty" } ?? "—")
                        } label: {
                            Text(item.driverName ?? "Unknown driver")
                            if let event = item.grandPrixName { Text(event).foregroundStyle(.secondary) }
                        }
                    }
                    if penalties.isEmpty { Text("No penalties recorded").foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func powerPenaltyTable(_ penalties: [PowerUnitReport.Penalty], hasReports: Bool) -> some View {
        let events = Dictionary(grouping: penalties) { $0.round ?? -1 }
        let rounds = events.keys.sorted(by: >)
        let groups = events.mapValues { reports in
            Dictionary(grouping: reports) { $0.driverCode ?? $0.driverName ?? "" }.values.sorted {
                let left = $0.compactMap(\.gridPositions).reduce(0, +)
                let right = $1.compactMap(\.gridPositions).reduce(0, +)
                return (left, $0.first?.driverName ?? "", $0.first?.driverCode ?? "")
                    < (right, $1.first?.driverName ?? "", $1.first?.driverCode ?? "")
            }
        }
        return upgradeCard("Power Unit Grid Penalties") {
            if penalties.isEmpty {
                let unavailable = metadata?.sections?["penalties"]?.unavailable == true
                Text(unavailable ? "Penalty reports could not be loaded." : hasReports
                    ? "No penalties match the selected filters." : "No reported power unit grid penalties for this season.")
                    .foregroundStyle(.secondary)
            }
            ForEach(rounds, id: \.self) { round in
                let location = events[round, default: []].compactMap(\.grandPrixName).first
                Text([round >= 0 ? "R\(round)" : nil, location].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.bold())
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 6)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Driver")
                        Text("Components Changed")
                        Text("Penalty")
                        Text("Starting")
                    }.font(.caption.bold()).foregroundStyle(.secondary)
                    Divider()
                    ForEach(Array(groups[round, default: []].enumerated()), id: \.offset) { _, items in
                        if let first = items.first {
                            powerPenaltyRow(items, first: first)
                            Divider()
                        }
                    }
                }
                .font(.subheadline.monospacedDigit())
            }
        }
    }

    private func powerElementCode(_ value: String) -> String {
        switch value.lowercased() {
        case "mguk": "mgu-k"
        case "mguh": "mgu-h"
        default: value.lowercased()
        }
    }

    private func powerPenaltyComponents(_ items: [PowerUnitReport.Penalty]) -> [String] {
        let details = items.flatMap { $0.penaltyItems ?? [] }.compactMap { item -> String? in
            guard let code = item.elementCode else { return nil }
            return [item.elementNumber.map { "#\($0)" }, powerElementCode(code).uppercased(),
                    item.gridPositions.map { "+\($0)" }].compactMap { $0 }.joined(separator: " ")
        }
        if !details.isEmpty { return details }
        return Set(items.flatMap { $0.elements ?? [] }.map { powerElementCode($0).uppercased() }).sorted()
    }

    private func powerPenaltyValues(_ items: [PowerUnitReport.Penalty]) -> (components: String, penalty: String, starting: String) {
        let components = powerPenaltyComponents(items)
        let positions = items.compactMap(\.gridPositions)
        let starting = items.compactMap(\.startingPosition).last
        let pitLane = items.contains { $0.startsFromPitLane == true }
        return (
            components.isEmpty ? "—" : components.joined(separator: ", "),
            positions.isEmpty ? "—" : "\(positions.reduce(0, +)) places",
            pitLane ? "Pit lane" : starting.map { "P\($0)" } ?? "Back of the field"
        )
    }

    private func powerPenaltyRow(_ items: [PowerUnitReport.Penalty], first: PowerUnitReport.Penalty) -> some View {
        let values = powerPenaltyValues(items)
        let components = powerPenaltyComponents(items)
        let reason = items.compactMap(\.pitLaneReason).first { !$0.isEmpty }
        let decision = items.flatMap { $0.sourceDocuments ?? [] }.compactMap { source -> URL? in
            guard let url = source.url.flatMap(URL.init(string:)),
                  url.scheme == "https", url.host == "www.fia.com" else { return nil }
            return url
        }.first
        return GridRow {
            VStack(alignment: .leading, spacing: 3) {
                powerDriverLink(name: first.driverName, code: first.driverCode)
                if let owner = items.compactMap(\.allocationDriverName).first, owner != first.driverName {
                    Text("PU allocation: \(owner)").font(.caption).foregroundStyle(.secondary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(components.enumerated()), id: \.offset) { _, component in
                        Text(component).font(.caption)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(WebDashboardStyle.homeLine, in: .rect(cornerRadius: 4))
                    }
                }
                Text(values.components)
            }
            Text(values.penalty).foregroundStyle(PulseStyle.red)
            HStack(spacing: 6) {
                if let reason {
                    Text(values.starting).help(reason)
                        .accessibilityHint(reason)
                } else {
                    Text(values.starting)
                }
                if let decision {
                    Link(destination: decision) { Image(systemName: "info.circle") }
                        .accessibilityLabel("FIA decision for \(first.driverName ?? "driver")")
                }
            }
        }
    }

    @ViewBuilder
    private func powerDriverLink(name: String?, code: String?) -> some View {
        let label = name ?? "Unknown driver"
        if let driver = powerDriver(name: name, code: code) {
            if tabletWorkspace, let openDriverProfile {
                Button {
                    openDriverProfile(.stats(StandingEntry(driver: driver)))
                } label: {
                    Text(label).foregroundStyle(PulseStyle.red)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    StandingProfile(entry: StandingEntry(driver: driver), driversDesign: true)
                } label: {
                    Text(label).foregroundStyle(PulseStyle.red)
                }
                .buttonStyle(.plain)
            }
        } else {
            Text(label)
        }
    }

    private func powerDriver(name: String?, code: String?) -> DriverStanding? {
        let locale = Locale(identifier: "en_US_POSIX")
        func normalized(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let roster = model.driverRoster.filter { $0.season == model.season }
        if let name, let exact = roster.first(where: { normalized($0.driverName) == normalized(name) }) {
            return exact
        }
        guard let code, !code.isEmpty else { return nil }
        let matches = roster.filter { driver in
            guard let surname = driver.driverName.split(whereSeparator: \.isWhitespace).last else { return false }
            return normalized(String(surname.prefix(3))) == normalized(code)
        }
        return matches.count == 1 ? matches.first : nil
    }

    private func reportFilter(_ title: String, options: [String], excluded: Binding<Set<String>>) -> some View {
        Menu {
            Button("Select All") { excluded.wrappedValue.removeAll() }
            ForEach(Set(options).sorted(), id: \.self) { option in
                Toggle(option, isOn: Binding(
                    get: { !excluded.wrappedValue.contains(option) },
                    set: { selected in
                        if selected { excluded.wrappedValue.remove(option) }
                        else { excluded.wrappedValue.insert(option) }
                    }
                ))
                .menuActionDismissBehavior(.disabled)
            }
        } label: {
            Label(title, systemImage: excluded.wrappedValue.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private func powerOverview(usage: [PowerUnitReport.Usage], elements: [PowerUnitReport.Element]) -> some View {
        let counts: [(code: String, count: Int)] = elements.map { element in
            let count = usage.reduce(0) { total, usage in
                total + (usage.count(for: element.code) ?? 0)
            }
            return (element.code, count)
        }
        let totals = counts.sorted {
            if $0.count == $1.count { return $0.code < $1.code }
            return $0.count > $1.count
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                powerMatrix(usage: usage, elements: elements).frame(minWidth: 530)
                powerTotals(totals).frame(width: 245)
            }
            VStack(alignment: .leading, spacing: 16) {
                powerMatrix(usage: usage, elements: elements)
                powerTotals(totals)
            }
        }
        .listRowSeparator(.hidden)
    }

    private func powerMatrixValue(_ usage: PowerUnitReport.Usage, element: PowerUnitReport.Element) -> String {
        guard let count = usage.count(for: element.code) else { return "—" }
        guard let quota = element.quota, quota > 0 else { return String(count) }
        return "\(count)/\(quota)"
    }

    private func powerMatrix(usage: [PowerUnitReport.Usage], elements: [PowerUnitReport.Element]) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Power Unit Elements Used").font(.headline).accessibilityAddTraits(.isHeader)
            }
            if usage.isEmpty {
                Text("No drivers match the selected filters.").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                        GridRow {
                            Text("Driver")
                            Text("Engine")
                            ForEach(elements, id: \.code) { Text($0.code.uppercased()) }
                            Text("Total")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        Divider()
                        ForEach(Array(usage.enumerated()), id: \.offset) { _, usage in
                            GridRow {
                                powerDriverLink(name: usage.driverName, code: usage.driverCode)
                                Text(usage.engineManufacturer ?? "—").foregroundStyle(.secondary)
                                ForEach(elements, id: \.code) { element in
                                    PowerAllocationCell(
                                        driver: usage.driverName ?? "Unknown driver",
                                        element: element,
                                        count: usage.count(for: element.code),
                                        value: powerMatrixValue(usage, element: element)
                                    )
                                }
                                Text(elements.reduce(0) { $0 + (usage.count(for: $1.code) ?? 0) }, format: .number)
                                    .bold()
                            }
                            Divider()
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .fixedSize(horizontal: true, vertical: false)
                }
                HStack(spacing: 7) {
                    PowerAllocationStatus.within.badge("Within allocation")
                    PowerAllocationStatus.limit.badge("At allocation")
                    PowerAllocationStatus.over.badge("Over allocation")
                }
                .font(.system(size: 10))
            }
        }
        .padding(12)
        .background(PulseStyle.surface, in: .rect(cornerRadius: 10))
    }

    private func powerTotals(_ totals: [(code: String, count: Int)]) -> some View {
        let title = "Elements Used by Component"
        let height = max(150, totals.count * 24 + 8)
        let maximum = max(1, totals.map(\.count).max() ?? 0)
        let red = Color(red: 225 / 255, green: 6 / 255, blue: 0)
        func width(_ count: Int) -> CGFloat { 343 * CGFloat(count) / CGFloat(maximum) }
        return upgradeCard(title) {
            if totals.isEmpty {
                Text("No data available for this selection.").foregroundStyle(WebDashboardStyle.homeMuted)
            } else {
                Canvas { context, size in
                    var context = context
                    context.scaleBy(x: size.width / 360, y: size.height / CGFloat(height))
                    for (index, item) in totals.enumerated() {
                        let y = CGFloat(index * 24 + 4)
                        let rect = CGRect(x: 5, y: y, width: width(item.count), height: 22)
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(red))
                        context.draw(Text(String(item.count)).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(width(item.count) >= 26 ? Color.white : WebDashboardStyle.homeText),
                            at: CGPoint(x: 11, y: y + 11), anchor: .leading)
                        context.draw(Text(item.code.uppercased()).font(.system(size: 12))
                            .foregroundStyle(width(item.count) > 210 ? Color.white : WebDashboardStyle.homeText),
                            at: CGPoint(x: 37, y: y + 11), anchor: .leading)
                    }
                }
                .aspectRatio(360 / CGFloat(height), contentMode: .fit)
                .accessibilityRepresentation {
                    ForEach(totals, id: \.code) { item in
                        Text("\(item.code.uppercased()) · \(item.count)")
                    }
                }
            }
        }
    }

    private struct DamageCost: Identifiable {
        let name: String
        let detail: String
        let total: Double
        var id: String { "\(name)|\(detail)" }
    }

    @ViewBuilder private var damageWorkspace: some View {
        if let damage {
            HStack {
                reportFilter("Drivers", options: damage.rows.compactMap(\.driverName), excluded: $excludedDrivers)
                reportFilter("Constructors", options: damage.rows.compactMap(\.team), excluded: $excludedConstructors)
            }
            .listRowSeparator(.hidden)
            let rows = damage.rows.filter {
                !excludedDrivers.contains($0.driverName ?? "") && !excludedConstructors.contains($0.team ?? "")
            }
            if rows.isEmpty {
                ContentUnavailableView("No matching incidents", systemImage: topic.symbol)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        crashSidebar(rows, corrections: damage.corrections).frame(width: 270)
                        crashSummary(rows).frame(minWidth: 530)
                    }
                    VStack(spacing: 14) {
                        crashSidebar(rows, corrections: damage.corrections)
                        crashSummary(rows)
                    }
                }
                .listRowSeparator(.hidden)
            }
        }
    }

    private func crashSidebar(_ rows: [DamageReport.Incident], corrections: [DamageReport.Correction]?) -> some View {
        VStack(spacing: 14) {
            upgradeCard("Source Corrections") {
                Text("Costs are estimates from the PitPulse archive.")
                    .foregroundStyle(.secondary)
                if metadata?.sections?["corrections"]?.unavailable == true || corrections == nil {
                    Text("Correction history is currently unavailable.")
                        .foregroundStyle(.secondary)
                } else if let corrections {
                    DisclosureGroup {
                        ForEach(Array(corrections.enumerated()), id: \.offset) { _, correction in
                            VStack(alignment: .leading, spacing: 5) {
                                Text([
                                    correction.round.map { $0 == 0 ? "Pre-season" : "R\($0)" },
                                    correction.driverSeason?.driver?.name ?? "Unknown driver",
                                    correction.components?.name ?? "Component"
                                ].compactMap { $0 }.joined(separator: " · ")).bold()
                                Text([
                                    correction.diff.map { $0.capitalized },
                                    correction.quantity.map { "×\($0)" },
                                    correction.note ?? "Source correction"
                                ].compactMap { $0 }.joined(separator: " · "))
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 5)
                        }
                    } label: {
                        Text("Corrections (\(corrections.count))")
                    }
                }
            }
            .font(.subheadline)
            crashStandings(rows)
        }
    }

    private func crashStandings(_ rows: [DamageReport.Incident]) -> some View {
        let rankings = crashCosts(rows, by: \.driverName)
        return upgradeCard("Driver Crash Standings") {
            ForEach(Array(rankings.enumerated()), id: \.element.id) { index, item in
                HStack {
                    Text("\(index + 1)").foregroundStyle(.secondary)
                    Text(item.name)
                    Spacer()
                    Text(item.total, format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .font(.subheadline.monospacedDigit())
                Divider()
            }
        }
    }

    private func crashSummary(_ rows: [DamageReport.Incident]) -> some View {
        let parts = rows.flatMap(\.components).filter { $0.name != nil && $0.price != nil && $0.quantity != nil }
        let components = Dictionary(grouping: parts) { part in
            "\(part.name ?? "")|\(part.price ?? 0)"
        }.map { key, entries in
            let quantity = entries.compactMap(\.quantity).reduce(0, +)
            let price = entries.first?.price ?? 0
            return (id: key, name: entries.first?.name ?? "", quantity: quantity, price: price, total: price * Double(quantity))
        }.sorted { $0.total > $1.total }
        let crashes = Dictionary(grouping: rows) { row in
            DamageCost(name: row.driverName ?? "Unknown driver",
                       detail: [row.round.map { "R\($0)" }, row.country].compactMap { $0 }.joined(separator: " · "),
                       total: 0).id
        }.values.compactMap { group -> DamageCost? in
            guard let first = group.first else { return nil }
            let total = group.compactMap(\.estimate).reduce(0, +)
            guard total > 0 else { return nil }
            return DamageCost(name: first.driverName ?? "Unknown driver",
                              detail: [first.round.map { "R\($0)" }, first.country].compactMap { $0 }.joined(separator: " · "),
                              total: total)
        }.sorted { $0.total > $1.total }
        let componentTotal = components.reduce(0) { $0 + $1.total }
        let mostExpensive = crashes.prefix(30)
        return VStack(spacing: 14) {
            crashBreakdown(rows, byConstructor: true)
            crashEvolution("Cumulative Constructor Crash Costs", rows: rows, by: \.team)
            crashEvolution("Cumulative Driver Crash Costs", rows: rows, by: \.driverName)
            crashBreakdown(rows, byConstructor: false)
            upgradeCard("Crash Costs by Component") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Component")
                        Text("Unit Price")
                        Text("Quantity")
                        Text("Total Cost")
                    }.font(.caption.bold()).foregroundStyle(.secondary)
                    Divider()
                    ForEach(components, id: \.id) { item in
                        GridRow {
                            Text(item.name)
                            Text(item.price, format: .currency(code: "USD").precision(.fractionLength(0)))
                            Text(item.quantity, format: .number)
                            Text(item.total, format: .currency(code: "USD").precision(.fractionLength(0)))
                        }
                    }
                    Divider()
                    GridRow {
                        Text("Total").gridCellColumns(3)
                        Text(componentTotal,
                             format: .currency(code: "USD").precision(.fractionLength(0)))
                    }.bold()
                }.font(.subheadline.monospacedDigit())
            }
            upgradeCard("Most Expensive Crashes") {
                ForEach(mostExpensive) { item in
                    LabeledContent {
                        Text(item.total, format: .currency(code: "USD").precision(.fractionLength(0)))
                    } label: {
                        Text(item.name)
                        Text(item.detail).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func crashMoney(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
    }

    private func crashCosts(_ rows: [DamageReport.Incident],
                            by key: KeyPath<DamageReport.Incident, String?>) -> [DamageCost] {
        let groups = Dictionary(grouping: rows) { $0[keyPath: key] ?? "Unknown" }
        return groups.compactMap { name, incidents -> DamageCost? in
            let estimates = incidents.compactMap(\.estimate)
            guard !estimates.isEmpty else { return nil }
            return DamageCost(name: name, detail: "", total: estimates.reduce(0, +))
        }.sorted { $0.total == $1.total ? $0.name < $1.name : $0.total > $1.total }
    }

    private struct CrashTrend {
        let name: String
        let team: String
        let totals: [Double]
    }

    private func crashEvolution(_ title: String, rows: [DamageReport.Incident],
                                by key: KeyPath<DamageReport.Incident, String?>) -> some View {
        let meetings = model.meetings.filter { $0.season == model.season }
        let countries = Dictionary(meetings.compactMap { meeting in
            meeting.round.map { ($0, meeting.country) }
        }, uniquingKeysWith: { first, _ in first })
        let observedCountries = Dictionary(rows.compactMap { row in
            guard let round = row.round, let country = row.country else { return nil as (Int, String)? }
            return (round, country)
        }, uniquingKeysWith: { first, _ in first })
        let rounds = Set(countries.keys).union(rows.compactMap(\.round)).sorted()
        let labels = rounds.map { round in
            let country = countries[round] ?? observedCountries[round] ?? ""
            return round == 0 ? "Pre-season" : "R\(round) \(country)".trimmingCharacters(in: .whitespaces)
        }
        let groups = Dictionary(grouping: rows) { $0[keyPath: key] ?? "Unknown" }
        let series = groups.keys.sorted().compactMap { name -> CrashTrend? in
            guard let entries = groups[name], !rounds.isEmpty else { return nil }
            let byRound = Dictionary(grouping: entries, by: \.round)
            var cumulative = 0.0
            let totals = rounds.map { round in
                cumulative += byRound[round, default: []].compactMap(\.estimate).reduce(0, +)
                return cumulative
            }
            guard cumulative > 0 else { return nil }
            let team = entries.max { ($0.round ?? -1) < ($1.round ?? -1) }?.team ?? name
            return CrashTrend(name: name, team: team, totals: totals)
        }
        return upgradeCard(title) {
            if series.isEmpty {
                Text("No crash reports match the selected filters.").foregroundStyle(WebDashboardStyle.homeMuted)
            } else {
                Chart {
                    ForEach(series, id: \.name) { trend in
                        ForEach(Array(trend.totals.enumerated()), id: \.offset) { index, total in
                            LineMark(x: .value("Round", index), y: .value("Estimated cost in USD", total),
                                     series: .value("Name", trend.name))
                                .foregroundStyle(WebDashboardStyle.chartTeamColor(trend.team))
                            PointMark(x: .value("Round", index), y: .value("Estimated cost in USD", total))
                                .foregroundStyle(WebDashboardStyle.chartTeamColor(trend.team))
                                .symbolSize(12)
                                .accessibilityLabel("\(trend.name) · \(labels[index])")
                                .accessibilityValue(crashMoney(total))
                        }
                    }
                }
                .chartXScale(domain: 0...max(1, rounds.count - 1))
                .chartXAxis {
                    AxisMarks(values: Array(rounds.indices)) { value in
                        if let index = value.as(Int.self), rounds.indices.contains(index) {
                            AxisValueLabel(rounds[index] == 0 ? "PS" : "R\(rounds[index])")
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(format: FloatingPointFormatStyle<Double>.Currency(code: "USD").notation(.compactName), position: .leading)
                }
                .frame(height: 300)
            }
        }
    }

    private struct CrashSegment {
        let driver: String
        let team: String
        let total: Double
    }

    private struct CrashBar: Identifiable {
        let id: String
        let label: String
        let segments: [CrashSegment]

        var total: Double { segments.reduce(0) { $0 + $1.total } }
    }

    private func crashBreakdown(_ rows: [DamageReport.Incident], byConstructor: Bool) -> some View {
        let title = byConstructor ? "Constructor Crash Costs" : "Crash Costs by Event (by Driver)"
        let groups = Dictionary(grouping: rows) { row in
            byConstructor ? (row.team ?? "Unknown") : (row.round.map(String.init) ?? row.country ?? "Unknown")
        }
        let bars = groups.map { id, incidents in
            let label = byConstructor ? id : (incidents.first?.country ?? id)
            let drivers = Dictionary(grouping: incidents) { $0.driverName ?? "Unknown driver" }
            let segments = drivers.compactMap { driver, entries -> CrashSegment? in
                let total = entries.compactMap(\.estimate).reduce(0, +)
                guard total > 0 else { return nil }
                return CrashSegment(driver: driver, team: entries.first?.team ?? "Unknown", total: total)
            }.sorted { ($0.total, $0.driver) > ($1.total, $1.driver) }
            return CrashBar(id: id, label: label, segments: segments)
        }.filter { !$0.segments.isEmpty }.sorted {
            if byConstructor { return ($0.total, $0.id) > ($1.total, $1.id) }
            return (Int($0.id) ?? .max, $0.id) < (Int($1.id) ?? .max, $1.id)
        }
        let labels = Dictionary(uniqueKeysWithValues: bars.map { ($0.id, $0.label) })
        return upgradeCard(title) {
            if bars.isEmpty {
                Text("No crash reports match the selected filters.").foregroundStyle(WebDashboardStyle.homeMuted)
            } else {
                Chart(bars) { bar in
                    ForEach(Array(bar.segments.enumerated()), id: \.offset) { index, segment in
                        crashSegmentMark(segment, in: bar, index: index, vertical: byConstructor)
                    }
                }
                .chartXAxis {
                    if byConstructor {
                        AxisMarks(values: bars.map(\.id)) { value in
                            if let id = value.as(String.self) { AxisValueLabel(labels[id, default: id]) }
                        }
                    } else {
                        AxisMarks(format: FloatingPointFormatStyle<Double>.Currency(code: "USD").notation(.compactName))
                    }
                }
                .chartYAxis {
                    if byConstructor {
                        AxisMarks(format: FloatingPointFormatStyle<Double>.Currency(code: "USD").notation(.compactName), position: .leading)
                    } else {
                        AxisMarks(position: .leading, values: bars.map(\.id)) { value in
                            if let id = value.as(String.self) { AxisValueLabel(labels[id, default: id]) }
                        }
                    }
                }
                .frame(height: byConstructor ? 320 : CGFloat(bars.count * 22 + 36))
            }
        }
    }

    @ChartContentBuilder
    private func crashSegmentMark(_ segment: CrashSegment, in bar: CrashBar, index: Int, vertical: Bool) -> some ChartContent {
        let start = bar.segments.prefix(index).reduce(0.0) { $0 + $1.total }
        let end = start + segment.total
        let color = WebDashboardStyle.chartTeamColor(segment.team)
        let name = "\(bar.label) · \(segment.driver)"
        let cost = crashMoney(segment.total)
        if vertical {
            BarMark(x: .value("Constructor", bar.id), yStart: .value("Start", start), yEnd: .value("End", end))
                .foregroundStyle(color).accessibilityLabel(name).accessibilityValue(cost)
        } else {
            BarMark(xStart: .value("Start", start), xEnd: .value("End", end), y: .value("Grand Prix", bar.id))
                .foregroundStyle(color).accessibilityLabel(name).accessibilityValue(cost)
        }
    }

    @ViewBuilder private var incidents: some View {
        if let damage {
            filters(rounds: damage.rows.compactMap(\.round), teams: damage.rows.compactMap(\.team))
            let rows = damage.rows.filter { (round == nil || round == $0.round) && (team.isEmpty || team == $0.team) }
            if !rows.isEmpty {
                let estimates = rows.compactMap(\.estimate)
                if !estimates.isEmpty {
                    LabeledContent(estimates.count == rows.count ? "Estimated Total Cost" : "Known Estimated Costs") {
                        Text(estimates.reduce(0, +), format: .currency(code: "USD")).monospacedDigit()
                    }
                }
            }
            damageChart(rows)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                DisclosureGroup {
                    ForEach(Array(row.components.enumerated()), id: \.offset) { _, component in
                        LabeledContent(
                            component.name ?? "Components",
                            value: component.quantity.map { "×\($0)" } ?? "—"
                        )
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.driverName ?? "Unknown driver").font(.headline)
                            Text([row.round.map { "R\($0)" }, row.country, row.team]
                                .compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let estimate = row.estimate { Text(estimate, format: .currency(code: "USD")).monospacedDigit() }
                    }
                }.listRowSeparator(.hidden)
            }
            if rows.isEmpty { ContentUnavailableView("No incidents recorded", systemImage: topic.symbol) }
        }
    }

    @ViewBuilder private func damageChart(_ rows: [DamageReport.Incident]) -> some View {
        let totals = rows.reduce(into: [String: Double]()) { result, row in
            guard let name = team.isEmpty ? row.team : row.driverName, let estimate = row.estimate else { return }
            result[name, default: 0] += estimate
        }
        let leaders = Array(totals.keys.sorted { totals[$0, default: 0] > totals[$1, default: 0] }.prefix(6))
        if !leaders.isEmpty {
            Section(team.isEmpty ? "Estimated Cost by Team" : "Estimated Cost by Driver") {
                Chart(leaders, id: \.self) { name in
                    BarMark(x: .value("Estimated Cost · USD", totals[name, default: 0]), y: .value("Name", name))
                        .foregroundStyle(team.isEmpty ? DashboardArt.teamColor(name) : PulseStyle.red)
                        .cornerRadius(3)
                }.pulseChart().frame(height: CGFloat(leaders.count) * 30 + 30)
            }.listRowBackground(PulseStyle.surface)
        }
    }

    @ViewBuilder private func filters(rounds: [Int], teams: [String]) -> some View {
        Picker("Round", selection: $round) {
            Text("All").tag(Int?.none)
            ForEach(Set(rounds).sorted(), id: \.self) { Text("R\($0)").tag(Int?.some($0)) }
        }
        Picker("Team", selection: $team) {
            Text("All").tag("")
            ForEach(Set(teams).sorted(), id: \.self) { Text($0).tag($0) }
        }
    }

    private func load() async {
        guard let url = model.serverURL else { error = "Invalid server address"; return }
        let context = model.dataContext
        let season = model.season
        let token = model.currentToken
        let client = APIClient(baseURL: url)
        do {
            switch topic {
            case .upgrades:
                let response = try await client.technicalUpdates(season: season, token: token)
                guard context == model.dataContext, !Task.isCancelled else { return }
                updates = response.data
                metadata = response.meta
            case .power:
                let response = try await client.powerUnitReport(season: season, token: token)
                guard context == model.dataContext, !Task.isCancelled else { return }
                power = response.data
                metadata = response.meta
            case .damage:
                let response = try await client.damageReport(season: season, token: token)
                guard context == model.dataContext, !Task.isCancelled else { return }
                damage = response.data
                metadata = response.meta
            }
            loaded = true
            error = nil
        } catch {
            guard context == model.dataContext, !Task.isCancelled else { return }
            self.error = MobileModel.message(for: error).pulseEnglishError
        }
    }
}


private enum PowerAllocationStatus {
    case within, limit, over, neutral

    var background: Color {
        switch self {
        case .within: WebDashboardStyle.adaptive(dark: 0xd97706, light: 0xd97706)
        case .limit: WebDashboardStyle.adaptive(dark: 0xf59e0b, light: 0xf59e0b)
        case .over: WebDashboardStyle.adaptive(dark: 0xe10600, light: 0xe10600)
        case .neutral: WebDashboardStyle.homeLine
        }
    }

    var foreground: Color {
        switch self {
        case .within, .limit: WebDashboardStyle.adaptive(dark: 0x221300, light: 0x221300)
        case .over: .white
        case .neutral: WebDashboardStyle.homeMuted
        }
    }

    func badge(_ label: String) -> some View {
        Text(label)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(background, in: .rect(cornerRadius: 4))
    }
}

private struct PowerAllocationCell: View {
    let driver: String
    let element: PowerUnitReport.Element
    let count: Int?
    let value: String

    @State private var showsDetails = false

    private var status: PowerAllocationStatus {
        guard let count, let quota = element.quota, quota > 0 else { return .neutral }
        if count > quota { return .over }
        return count == quota ? .limit : .within
    }

    var body: some View {
        let reported = count.map(String.init) ?? "not reported"
        let quota = element.quota.flatMap { $0 > 0 ? " / \($0) allowed" : nil } ?? ""
        let note = status == .over ? " · Allocation exceeded. See the official penalty decisions below." : ""
        let details = "\(driver) · \(element.name): \(reported)\(quota)\(note)"
        Button {
            showsDetails.toggle()
        } label: {
            status.badge(value)
                .frame(minWidth: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(details)
        .help(details)
        .popover(isPresented: $showsDetails) {
            Text(details).font(.subheadline).padding(12).frame(idealWidth: 280)
        }
    }
}
