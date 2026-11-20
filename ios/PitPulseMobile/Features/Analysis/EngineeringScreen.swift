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
    @EnvironmentObject private var model: MobileModel
    let topic: EngineeringScreen.Topic
    @State private var updates: [TechnicalUpdate] = []
    @State private var power: PowerUnitReport?
    @State private var damage: DamageReport?
    @State private var metadata: EngineeringMetadata?
    @State private var loaded = false
    @State private var error: String?
    @State private var round: Int?
    @State private var team = ""

    var body: some View {
        List {
            if let metadata { quality(metadata) }
            if let error { Text(error).foregroundStyle(.secondary) }
            if loaded {
                switch topic {
                case .upgrades: upgrades
                case .power: powerUnits
                case .damage: incidents
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
                metadata = nil
                round = nil
                team = ""
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
            Section("Penalties") {
                ForEach(Array(power.penalties.enumerated()), id: \.offset) { _, item in
                    LabeledContent {
                        Text(item.startsFromPitLane == true ? "Pit lane start" : item.gridPositions.map { "\($0)-place grid penalty" } ?? "—")
                    } label: {
                        Text(item.driverName ?? "Unknown driver")
                        if let event = item.grandPrixName { Text(event).foregroundStyle(.secondary) }
                    }
                }
                if power.penalties.isEmpty { Text("No penalties recorded").foregroundStyle(.secondary) }
            }
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
