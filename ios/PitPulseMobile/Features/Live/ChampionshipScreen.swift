import Charts
import SharedComponents
import SharedData
import SwiftUI

struct ChampionshipScreen: View {
    @Environment(\.pulseEnglishPresentation) private var english

    private func copy(_ englishText: @autoclosure () -> String, _ original: @autoclosure () -> String) -> String {
        english ? englishText() : original()
    }

    @EnvironmentObject private var model: MobileModel
    @State private var teams: APIEnvelope<[ConstructorStanding]>?
    @State private var teamError: String?
    @State private var showTeams: Bool
    let constructorsOnly: Bool
    let driversOnly: Bool
    @State private var showSeasonCharts = false
    @State private var showConstructorCharts = false
    @State private var selection: Set<String>?
    @State private var showChartFilters = false
    @State private var standingDetail: StandingEntry?
    init(constructorsOnly: Bool = false, showTeams: Bool = false, driversOnly: Bool = false) {
        self.constructorsOnly = constructorsOnly
        self.driversOnly = driversOnly
        _showTeams = State(initialValue: showTeams)
    }

    private var usingTeams: Bool { constructorsOnly || showTeams }

    private var entries: [StandingEntry] {
        (usingTeams ? (teams?.data ?? []).map(StandingEntry.init(team:)) : model.driverRoster.map(StandingEntry.init(driver:)))
            .sorted { $0.position < $1.position }
    }

    private var movement: RoundMovement? {
        guard let archive = model.seasonArchive, !archive.meta.stale else { return nil }
        return RoundMovement(entries: entries, weekends: archive.data, teams: usingTeams)
    }

    private var selectedEntries: [StandingEntry] {
        entries.filter { selection?.contains($0.id) ?? true }
    }

    var body: some View {
        VStack(spacing: 0) {
            championshipContent
        }
        .navigationDestination(item: $standingDetail) { entry in
            StandingProfile(entry: entry)
        }
        .navigationDestination(isPresented: $showConstructorCharts) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    seasonChartsContent
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(PulseStyle.background)
            .navigationTitle(copy("Constructor Season Charts", "车队赛季图表"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showChartFilters = true } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                    .accessibilityLabel(copy("Filter Teams", "筛选车队"))
                    .accessibilityValue(copy("\(selectedEntries.count) of \(entries.count) teams selected", "已选 \(selectedEntries.count) 支，共 \(entries.count) 支"))
                }
            }
            .sheet(isPresented: $showChartFilters) { constructorFilters(isPresented: $showChartFilters) }
        }
        .task(id: model.dataContext) {
            selection = nil
            teams = nil
            teamError = nil
            async let archive: Void = model.loadSeasonArchive()
            await loadTeams()
            await archive
        }
    }

    private func constructorFilters(isPresented: Binding<Bool>) -> some View {
        NavigationStack {
            List {
                Button(copy("Select All", "全选")) { selection = nil }
                Button(copy("Clear", "清空")) { selection = [] }
                ForEach(entries, id: \.id) { entry in
                    let checked = selection?.contains(entry.id) ?? true
                    Button {
                        var ids = selection ?? Set(entries.map(\.id))
                        if checked { ids.remove(entry.id) } else { ids.insert(entry.id) }
                        selection = ids
                    } label: {
                        HStack {
                            AssetImage(name: entry.asset).frame(width: 28, height: 22)
                            Text(entry.name)
                            Spacer()
                            if checked { Image(systemName: "checkmark").foregroundStyle(PulseStyle.red) }
                        }
                    }.buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PulseStyle.background)
            .navigationTitle(copy("Filter Teams", "筛选车队"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy("Done", "完成")) { isPresented.wrappedValue = false }
                }
            }
        }
    }

    private var championshipContent: some View {
        List {
            if !constructorsOnly && !driversOnly {
                PulseSectionPicker(sections: [(false, copy("Driver", "车手")), (true, copy("Team", "车队"))], selection: $showTeams)
                    .listRowSeparator(.hidden)
            }
            if !constructorsOnly {
                PulseSectionPicker(sections: [(true, copy("Season Charts", "赛季图表")), (false, copy("Standings", "积分榜"))], selection: $showSeasonCharts)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            if constructorsOnly, let leader = entries.first {
                constructorLead(leader)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                standingsTable(leader)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                constructorPointsPreview
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }

            if driversOnly && !showSeasonCharts, let leader = entries.first {
                standingsTable(leader)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }

            if !showSeasonCharts && ((!constructorsOnly && !driversOnly) || entries.isEmpty) {
                if !entries.isEmpty {
                    if usingTeams ? teams?.meta.stale == true : model.rosterSavedAt == .distantPast {
                        Text(copy("Standings · Stale Cache", "缓存积分 · 已过期")).foregroundStyle(.secondary)
                    }
                    let latest = movement
                    Section(latest.map { copy("Points · R\($0.round) Changes", "积分 · R\($0.round) 变动") } ?? copy("Standings", "积分榜")) {
                        HStack {
                            Text(usingTeams ? copy("Pos. / Team", "位次 / 车队") : copy("Pos. / Driver", "位次 / 车手"))
                            Spacer()
                            Text(copy("Points / Gap", "积分 / 差距"))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .listRowBackground(PulseStyle.surface).listRowSeparator(.hidden)
                        ForEach(entries, id: \.id) { entry in
                            link(entry, leader: entries.first?.points, latest: latest)
                        }
                    }
                } else if let error = usingTeams ? teamError : model.rosterLoadError {
                    ContentUnavailableView(copy("Couldn't Load Standings", "无法读取积分"), systemImage: "trophy", description: Text(english ? error.pulseEnglishError : error))
                } else if usingTeams && teams != nil {
                    ContentUnavailableView(copy("No Constructor Standings", "暂无车队积分"), systemImage: "trophy")
                } else {
                    Group { if english { PulseSkeleton(label: "Loading standings…") } else { ProgressView("读取积分…") } }
                }
            }

            if !constructorsOnly && showSeasonCharts {
                seasonChartsContent
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PulseStyle.background)
        .refreshable {
            async let roster: Void = model.loadF1Roster(force: true)
            async let archive: Void = model.loadSeasonArchive(force: true)
            await loadTeams()
            _ = await (roster, archive)
        }
    }

    @ViewBuilder private var seasonChartsContent: some View {
        if let archive = model.seasonArchive, !entries.isEmpty, !archive.data.isEmpty {
            if archive.meta.stale || (usingTeams ? teams?.meta.stale == true : model.rosterSavedAt == .distantPast) {
                Text(copy("Showing cached season data", "赛季数据使用缓存")).font(.caption).foregroundStyle(.secondary)
            }
            ChampionshipSeasonCharts(entries: entries, weekends: archive.data, usingTeams: usingTeams,
                                      sharedSelection: constructorsOnly ? $selection : nil)
                .id("\(model.dataContext):\(usingTeams)")
        } else if let error = (usingTeams ? teamError : model.rosterLoadError) ?? model.seasonArchiveError {
            ContentUnavailableView(copy("Couldn't Load Season Charts", "无法载入赛季图表"), systemImage: "chart.xyaxis.line", description: Text(english ? error.pulseEnglishError : error))
        } else if model.seasonArchive?.data.isEmpty == true || (usingTeams && teams?.data.isEmpty == true) {
            ContentUnavailableView(copy("No Season Data", "暂无可用赛季数据"), systemImage: "chart.xyaxis.line")
        } else {
            Group { if english { PulseSkeleton(label: "Loading season charts…", chart: true) } else { ProgressView("读取赛季图表…") } }
        }
    }

    private var constructorPointsPreview: some View {
        let archive = model.seasonArchive
        let samples = ChampionshipSeasonCharts.makeSamples(entries: entries, weekends: archive?.data ?? [], usingTeams: true)
        let rounds = Array(Set(samples.map(\.round)).sorted().suffix(10))
        let pointsByRound = Dictionary(grouping: samples, by: \.round).mapValues { roundSamples in
            Dictionary(uniqueKeysWithValues: roundSamples.compactMap { sample in
                sample.roundPoints.map { (sample.team.id, $0) }
            })
        }
        let maxPoints = max(1, samples.compactMap(\.roundPoints).max() ?? 0)
        return Button {
            showConstructorCharts = true
        } label: {
            PulseCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(copy("Points by Round", "分站得分热力图")).font(.headline)
                        Spacer()
                        PulseChevron()
                    }
                    if let first = rounds.first, let last = rounds.last {
                        let range = first == last ? "R\(last)" : "R\(first)–R\(last)"
                        Text(range + (archive?.meta.stale == true || teams?.meta.stale == true ? copy(" · Cached", " · 缓存") : ""))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Color.clear.frame(width: 24, height: 1)
                                ForEach(rounds, id: \.self) { round in
                                    Text(String(round)).font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .minimumScaleFactor(0.75).lineLimit(1)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            ForEach(entries, id: \.id) { team in
                                HStack(spacing: 4) {
                                    AssetImage(name: team.asset).frame(width: 24, height: 14)
                                    ForEach(rounds, id: \.self) { round in
                                        let points = pointsByRound[round]?[team.id]
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(heatmapColor(points, maxPoints: maxPoints, team: team))
                                            .frame(maxWidth: .infinity).frame(height: 14)
                                    }
                                }
                            }
                        }
                        .accessibilityHidden(true)
                    } else if archive == nil && model.seasonArchiveError == nil {
                        Group { if english { PulseSkeleton(rows: 2, label: "Loading round points…") } else { ProgressView("读取分站得分…") } }.font(.caption)
                    } else {
                        Text(copy("No round points", "暂无分站得分")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(PulseStyle.cardShape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(copy("Open constructor season charts", "打开车队赛季图表"))
    }

    private func heatmapColor(_ points: Double?, maxPoints: Double, team: StandingEntry) -> Color {
        guard let points else { return .clear }
        guard points > 0 else { return Color.secondary.opacity(0.12) }
        return DashboardArt.teamColor(team.colorID).opacity(0.22 + 0.78 * points / maxPoints)
    }

    private func standingsTable(_ leader: StandingEntry) -> some View {
        let entity = usingTeams ? copy("Team", "车队") : copy("Driver", "车手")
        let samples = ChampionshipSeasonCharts.makeSamples(entries: entries, weekends: model.seasonArchive?.data ?? [], usingTeams: usingTeams)
        let rounds = Set(samples.map(\.round)).sorted().suffix(2)
        let lastRound = rounds.last
        let changes = Dictionary(grouping: samples.filter { rounds.contains($0.round) }, by: { $0.team.id })
            .compactMapValues { ranks -> Int? in
                guard ranks.count == 2, let earlier = ranks.first, let later = ranks.last else { return nil }
                return earlier.ranking - later.ranking
            }
        return PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(copy("\(String(model.season)) \(entity) Standings", "\(String(model.season)) \(entity)积分榜")).font(.headline)
                if usingTeams ? teams?.meta.stale == true : model.rosterSavedAt == .distantPast {
                    Text(copy("Standings · Stale Cache", "缓存积分 · 已过期")).font(.caption).foregroundStyle(.secondary)
                }
                constructorColumns {
                    Text("POS.").frame(minWidth: 30, alignment: .leading)
                    Text(usingTeams ? "CONSTRUCTOR" : "DRIVER").frame(maxWidth: .infinity, alignment: .leading)
                    Text("POINTS").frame(minWidth: 50, alignment: .trailing)
                    Text(lastRound.map { "R\($0) Δ" } ?? "EVO.")
                        .frame(width: 38, alignment: .trailing)
                        .accessibilityLabel(copy("Position change in the latest archived race", "最近一站归档排名变动"))
                }.font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(entries, id: \.id) { entry in
                    Button {
                        standingDetail = entry
                    } label: {
                        constructorColumns {
                            Text(String(entry.position)).monospacedDigit().frame(minWidth: 30, alignment: .leading)
                            HStack(spacing: 7) {
                                AssetImage(name: entry.asset).frame(width: 26, height: 21).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(usingTeams ? entry.name.replacingOccurrences(of: " F1 Team", with: "") : entry.name)
                                        .font(.subheadline.weight(.medium))
                                    if !usingTeams, let team = entry.team {
                                        Text(team).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            VStack(alignment: .trailing, spacing: 2) {
                                PulseNumber(entry.points.formatted()).fontWeight(.semibold)
                                if entry.position > 1 {
                                    PulseNumber((entry.points - leader.points).formatted(.number.sign(strategy: .always())))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }.monospacedDigit().frame(minWidth: 50, alignment: .trailing)
                            constructorEvolution(changes[entry.id])
                                .frame(width: 38, alignment: .trailing)
                        }.font(.subheadline).frame(minHeight: 44).contentShape(.rect)
                            .accessibilityElement(children: .combine)
                    }.buttonStyle(PulsePressStyle())
                        .accessibilityIdentifier("\(usingTeams ? "constructors" : "drivers").detail.\(entry.id)")
                }
            }
        }
    }

    private func constructorColumns<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        return HStack(spacing: 8) {
            content()
        }
    }

    private func constructorEvolution(_ change: Int?) -> some View {
        return Group {
            if let change, change != 0 {
                HStack(spacing: 2) {
                    Image(systemName: change > 0 ? "arrow.up" : "arrow.down")
                    Text(String(abs(change))).monospacedDigit()
                }.foregroundStyle(change > 0 ? Color.green : PulseStyle.red)
                    .accessibilityLabel(change > 0 ? copy("Up \(change) places", "上升 \(change) 位") : copy("Down \(-change) places", "下降 \(-change) 位"))
            } else {
                Text(change == nil ? "—" : "0").monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityLabel(change == nil ? copy("No comparable ranking", "没有可比较的排名") : copy("No position change", "无排名变动"))
            }
        }.font(.caption2)
    }

    private func constructorLead(_ leader: StandingEntry) -> some View {
        let tint = DashboardArt.teamColor(leader.id)
        return Button {
            standingDetail = leader
        } label: {
            PulseCardDestination {
                VStack(alignment: .leading, spacing: 8) {
                    Text(copy("Constructor Leader", "车队积分领跑")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(leader.name).font(.title3.bold())
                    PulseNumber(copy("\(leader.points.formatted()) pts", "\(leader.points.formatted()) 分")).font(.headline.monospacedDigit())
                    if let car = DashboardArt.image(.carSide, id: leader.id, season: leader.season) {
                        Image(uiImage: car).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 62)
                            .accessibilityHidden(true)
                    }
                }
            }
            .overlay(alignment: .leading) {
                Capsule().fill(tint).frame(width: 3, height: 32).padding(.leading, 4).accessibilityHidden(true)
            }
        }.buttonStyle(PulsePressStyle())
    }

    private func link(_ entry: StandingEntry, leader: Double?, latest: RoundMovement?) -> some View {
        NavigationLink {
            StandingProfile(entry: entry)
        } label: {
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text(String(entry.position)).font(.headline.monospacedDigit())
                    if let prior = latest?.previousRanks[entry.id], prior != entry.position {
                        let change = prior - entry.position
                        Label(String(abs(change)), systemImage: change > 0 ? "arrow.up" : "arrow.down")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(change > 0 ? copy("Up \(change) places", "上升 \(change) 位") : copy("Down \(-change) places", "下降 \(-change) 位"))
                    }
                }.frame(minWidth: 22)
                AssetImage(name: entry.asset).frame(width: 40, height: 34)
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.name).font(.subheadline.weight(.semibold))
                    if let team = entry.team { Text(team).font(.caption2).foregroundStyle(.secondary) }
                    if let leader, leader > 0 {
                        GeometryReader { geometry in
                            Capsule().fill(entry.position == 1 ? PulseStyle.red : Color.secondary.opacity(0.36))
                                .frame(width: geometry.size.width * min(1, max(0, entry.points / leader)))
                        }
                        .frame(height: 3)
                        .background(.quaternary, in: .capsule)
                        .accessibilityHidden(true)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    PulseNumber(copy("\(entry.points.formatted()) pts", "\(entry.points.formatted()) 分")).font(.headline.monospacedDigit())
                    if let points = latest?.points[entry.id] {
                        PulseNumber(copy("This round \(points.formatted()) pts", "本轮 \(points.formatted()) 分")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if let leader, leader > entry.points {
                        Text(copy("Behind by \((leader - entry.points).formatted())", "落后 \((leader - entry.points).formatted())"))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }.padding(.vertical, 1)
        }.listRowBackground(PulseStyle.surface).listRowSeparator(.hidden)
    }

    private func loadTeams() async {
        guard let url = model.serverURL else { teamError = copy("Invalid server address", "服务器地址无效"); return }
        let context = model.dataContext
        do {
            let response = try await APIClient(baseURL: url).constructorStandings(season: model.season, token: model.currentToken)
            guard context == model.dataContext, !Task.isCancelled else { return }
            teams = response
            teamError = nil
        } catch {
            guard context == model.dataContext, !Task.isCancelled else { return }
            teamError = MobileModel.message(for: error)
        }
    }
}

private struct ChampionshipSeasonCharts: View {
    @Environment(\.pulseEnglishPresentation) private var english

    private func copy(_ englishText: @autoclosure () -> String, _ original: @autoclosure () -> String) -> String {
        english ? englishText() : original()
    }

    @EnvironmentObject private var model: MobileModel
    let entries: [StandingEntry]
    let weekends: [SeasonResultWeekend]
    let usingTeams: Bool
    var sharedSelection: Binding<Set<String>?>? = nil
    @State private var showRanks = false
    @State private var selectedRound: Int?
    @State private var selectedDistributionRound: Int?
    @State private var distributionWeekend: SeasonResultWeekend?
    @State private var selection: Set<String>?
    @State private var showFilters = false
    @State private var compareChampion = false
    @State private var previousChampion: StandingEntry?
    @State private var championUnavailable = false
    @State private var championStale = false
    @State private var metrics = Set(ResultMetric.allCases)

    private enum ResultMetric: String, CaseIterable, Identifiable {
        case wins = "胜场", podiums = "领奖台", points = "得分完赛", poles = "杆位", retirements = "未完赛 / 未分类"
        var id: Self { self }

        var color: Color {
            switch self {
            case .wins: .orange
            case .podiums: .blue
            case .points: .teal
            case .poles: .purple
            case .retirements: PulseStyle.red
            }
        }

        func matches(_ row: SessionResult) -> Bool {
            let classified = row.classification.uppercased() == "CLASSIFIED"
            switch self {
            case .wins, .poles: return classified && row.position == 1
            case .podiums: return classified && (1...3).contains(row.position ?? 0)
            case .points: return classified && (row.points ?? 0) > 0
            case .retirements: return !classified
            }
        }
    }

    struct Sample: Identifiable {
        let round: Int
        let team: StandingEntry
        let points: Double
        let ranking: Int
        let roundPoints: Double?
        var id: String { "\(team.id)-\(round)" }
    }

    static func makeSamples(entries: [StandingEntry], weekends: [SeasonResultWeekend], usingTeams: Bool) -> [Sample] {
        func identifier(_ row: SessionResult) -> String { usingTeams ? row.constructorId : row.driverId }
        var totals: [String: Double] = [:]
        var finishes: [String: [Int: Int]] = [:]
        var complete = true
        return weekends.sorted { ($0.meeting.round ?? 0) < ($1.meeting.round ?? 0) }.flatMap { weekend -> [Sample] in
            guard complete, let round = weekend.meeting.round else { return [] }
            let raceRows = weekend.sessions["race"]?.rows ?? []
            let sprintRows = weekend.sessions["sprint"]?.rows ?? []
            let scoredSessions = weekend.meeting.sessions.filter {
                ($0.sessionType == .race || $0.sessionType == .sprint) && $0.status == .finished
            }
            let rows = raceRows + sprintRows
            guard scoredSessions.allSatisfy({ weekend.sessions[$0.sessionType.rawValue]?.rows.isEmpty == false }),
                  rows.allSatisfy({ $0.points != nil }) else {
                complete = false
                return []
            }
            guard !rows.isEmpty else { return [] }
            let scored = Dictionary(grouping: rows, by: identifier)
                .mapValues { $0.compactMap(\.points).reduce(0, +) }
            for (id, points) in scored { totals[id, default: 0] += points }
            for row in raceRows {
                if let position = row.position, position > 0 {
                    finishes[identifier(row), default: [:]][position, default: 0] += 1
                }
            }
            let ranked = entries.filter { totals[$0.id] != nil }.sorted { a, b in
                let left = totals[a.id, default: 0], right = totals[b.id, default: 0]
                if left != right { return left > right }
                for position in 1...30 {
                    let l = finishes[a.id]?[position] ?? 0, r = finishes[b.id]?[position] ?? 0
                    if l != r { return l > r }
                }
                return a.position < b.position
            }
            return ranked.enumerated().compactMap { index, team in
                guard let points = totals[team.id] else { return nil }
                return Sample(round: round, team: team, points: points, ranking: index + 1, roundPoints: scored[team.id])
            }
        }
    }

    private var selectedEntries: [StandingEntry] {
        let ids = sharedSelection?.wrappedValue ?? selection
        return entries.filter { ids?.contains($0.id) ?? true }
    }

    var body: some View {
        let history = Self.makeSamples(entries: entries, weekends: weekends, usingTeams: usingTeams)
        let shownEntries = selectedEntries
        let shownIDs = Set(shownEntries.map(\.id))
        let visible = history.filter { shownIDs.contains($0.team.id) }
        VStack(spacing: 12) {
            if sharedSelection == nil {
                Button {
                    showFilters = true
                } label: {
                    HStack {
                        Label(usingTeams ? copy("Filter Teams", "筛选车队") : copy("Filter Drivers", "筛选车手"), systemImage: "line.3.horizontal.decrease")
                        Spacer()
                        Text("\(shownEntries.count) / \(entries.count)").monospacedDigit()
                    }.frame(minHeight: 28)
                }
                .buttonStyle(.glass)
                .accessibilityValue(copy("\(shownEntries.count) of \(entries.count) selected", "已选 \(shownEntries.count) 项，共 \(entries.count) 项"))
            }

            if shownEntries.isEmpty {
                ContentUnavailableView(usingTeams ? copy("Select Teams", "请选择车队") : copy("Select Drivers", "请选择车手"), systemImage: "line.3.horizontal.decrease")
            } else {
                if sharedSelection == nil {
                    if visible.isEmpty {
                        ContentUnavailableView(copy("No Standings Trend", "暂无可计算的累计走势"), systemImage: "chart.xyaxis.line")
                    } else {
                        trend(visible, shownEntries: shownEntries, ranks: showRanks, round: $selectedRound)
                    }
                }
                distribution(visible, shownEntries: shownEntries)
                if sharedSelection == nil { resultBreakdown(shownEntries) }
            }
        }
        .sheet(isPresented: $showFilters) { filters }
        .sheet(item: $distributionWeekend) { weekend in
            ConstructorRoundPointsSheet(weekend: weekend, season: entries.first?.season ?? model.season)
        }
        .task(id: compareChampion) { await loadPreviousChampion() }
    }

    private var filters: some View {
        NavigationStack {
            List {
                Section {
                    Button(copy("Select All", "全选")) { selection = nil }.disabled(selectedEntries.count == entries.count)
                    Button(copy("Clear", "清空")) { selection = [] }.disabled(selectedEntries.isEmpty)
                }
                ForEach(entries, id: \.id) { team in
                    let checked = selection?.contains(team.id) ?? true
                    Button {
                        var ids = selection ?? Set(entries.map(\.id))
                        if checked { ids.remove(team.id) }
                        else { ids.insert(team.id) }
                        selection = ids
                    } label: {
                        HStack {
                            AssetImage(name: team.asset).frame(width: 28, height: 22)
                            Text(team.name)
                            Spacer()
                            if checked { Image(systemName: "checkmark").foregroundStyle(PulseStyle.red) }
                        }.contentShape(.rect)
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(checked ? .isSelected : [])
                }
            }
            .scrollContentBackground(.hidden)
            .background(PulseStyle.background)
            .navigationTitle(usingTeams ? copy("Filter Teams", "筛选车队") : copy("Filter Drivers", "筛选车手"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy("Done", "完成")) { showFilters = false }
                }
            }
        }
    }

    private func legend(_ shownEntries: [StandingEntry]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(shownEntries, id: \.id) { team in
                    Label {
                        Text(team.name).font(.caption)
                    } icon: {
                        Circle().fill(seriesColor(team)).frame(width: 7, height: 7)
                    }
                }
            }
        }.scrollIndicators(.hidden)
    }

    private func trend(_ visible: [Sample], shownEntries: [StandingEntry], ranks: Bool, round: Binding<Int?>) -> some View {
        let counts = Dictionary(grouping: visible, by: { $0.team.id }).mapValues(\.count)
        let selectedRound = round.wrappedValue
        return PulseCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(ranks ? copy("Rank by Round", "分站排名走势") : copy("Season Points", "赛季累计积分")).font(.headline)
                PulseSectionPicker(sections: [(false, copy("Cumulative Points", "累计积分")), (true, copy("Rank", "排名"))], selection: $showRanks)
                if !ranks {
                    Toggle(copy("Compare with Last Season's Champion", "显示上季冠军基准"), isOn: $compareChampion).font(.subheadline)
                    if compareChampion {
                        if let previousChampion {
                            Label(copy("\(String(previousChampion.season)) · \(previousChampion.name) · \(previousChampion.points.formatted()) pts", "\(String(previousChampion.season)) · \(previousChampion.name) · \(previousChampion.points.formatted()) 分") + (championStale ? copy(" · Cached", " · 缓存") : ""),
                                  systemImage: "line.horizontal.3")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        } else if championUnavailable {
                            Text(copy("No points for last season's champion", "没有可用的上季冠军积分")).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Group { if english { PulseSkeleton(label: "Loading the previous champion…") } else { ProgressView("读取上季冠军积分…") } }.font(.caption)
                        }
                    }
                }
                legend(shownEntries)
                Chart {
                    ForEach(visible) { sample in
                        let y = ranks ? Double(sample.ranking) : sample.points
                        LineMark(x: .value(copy("Round", "轮次"), sample.round), y: .value(copy("Results", "成绩"), y),
                                 series: .value(copy("Team", "车队"), sample.team.id))
                            .foregroundStyle(seriesColor(sample.team))
                        if sample.round == selectedRound || counts[sample.team.id] == 1 {
                            PointMark(x: .value(copy("Round", "轮次"), sample.round), y: .value(copy("Results", "成绩"), y))
                                .foregroundStyle(seriesColor(sample.team)).symbolSize(26)
                        }
                    }
                    if !ranks, compareChampion, let previousChampion {
                        RuleMark(y: .value(copy("Previous Champion", "上季冠军"), previousChampion.points))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1.1, dash: [4, 3]))
                    }
                    if let selectedRound {
                        RuleMark(x: .value(copy("Selected Round", "选中轮次"), selectedRound)).foregroundStyle(.secondary)
                    }
                }.pulseChart()
                .chartYScale(domain: .automatic(includesZero: !ranks, reversed: ranks))
                .chartXSelection(value: round)
                .frame(height: 210)
                if let selectedRound {
                    Text(roundTitle(selectedRound)).font(.subheadline.weight(.semibold))
                    ForEach(visible.filter { $0.round == selectedRound }) { sample in
                        LabeledContent(sample.team.name, value: ranks ? "P\(sample.ranking)" : sample.points.formatted() + copy(" pts", " 分"))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
    }

    private func distribution(_ visible: [Sample], shownEntries: [StandingEntry]) -> some View {
        let overall = shownEntries.filter { $0.points > 0 }
        let overallPoints = overall.reduce(0) { $0 + $1.points }
        let rounded = visible.filter { sample in
            guard let points = sample.roundPoints else { return false }
            return sharedSelection != nil || points > 0
        }
        let rounds = Set(rounded.map(\.round)).sorted()
        let meetingsByRound = Dictionary(weekends.compactMap { weekend in
            weekend.meeting.round.map { ($0, weekend.meeting) }
        }, uniquingKeysWith: { first, _ in first })
        let teamNames = shownEntries.map(\.name)
        let colors = shownEntries.map(seriesColor)
        return VStack(spacing: 12) {
            PulseCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(copy("Total Points Distribution", "总积分分布")).font(.headline)
                    if !overall.isEmpty {
                        Chart(overall, id: \.id) { team in
                            BarMark(x: .value(copy("Points", "积分"), team.points), stacking: .normalized)
                                .foregroundStyle(by: .value(copy("Team", "车队"), team.name))
                                .accessibilityLabel(team.name)
                                .accessibilityValue(share(team.points, of: overallPoints))
                        }.pulseChart()
                        .chartForegroundStyleScale(domain: teamNames, range: colors)
                        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
                        .frame(height: 28)
                    } else {
                        Text(copy("No season points", "暂无可用的赛季积分")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            PulseCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(copy("Round Points Distribution", "分站积分分布")).font(.headline)
                    if rounds.isEmpty {
                        Text(copy("No round points", "暂无可用的分站积分")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        roundDistribution(rounded, rounds: rounds, meetingsByRound: meetingsByRound, teamNames: teamNames, colors: colors)
                    }
                }
            }
        }
    }

    private func roundDistribution(
        _ rounded: [Sample], rounds: [Int], meetingsByRound: [Int: Meeting], teamNames: [String], colors: [Color]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if sharedSelection == nil {
                Picker(copy("View Round", "查看分站"), selection: $selectedDistributionRound) {
                    Text(copy("Select Round", "选择分站")).tag(Int?.none)
                    ForEach(rounds, id: \.self) { round in
                        Text(roundTitle(round)).tag(Int?.some(round))
                    }
                }
            }
            if let selectedDistributionRound {
                let selected = rounded.filter { $0.round == selectedDistributionRound }
                let total = selected.compactMap(\.roundPoints).reduce(0, +)
                ForEach(selected) { sample in
                    LabeledContent(sample.team.name, value: share(sample.roundPoints ?? 0, of: total))
                        .font(.caption.monospacedDigit())
                }
            }
            Chart(rounded) { sample in
                BarMark(x: .value(copy("Points", "积分"), sample.roundPoints ?? 0), y: .value(copy("Round", "轮次"), String(sample.round)), height: 24)
                    .foregroundStyle(by: .value(copy("Team", "车队"), sample.team.name))
                    .opacity(selectedDistributionRound == nil || selectedDistributionRound == sample.round ? 1 : 0.4)
                    .accessibilityLabel("\(roundTitle(sample.round)) · \(sample.team.name)")
            }.pulseChart()
            .chartYScale(domain: rounds.map(String.init))
            .chartForegroundStyleScale(domain: teamNames, range: colors)
            .chartXAxis { AxisMarks { AxisValueLabel() } }
            .chartYAxis {
                AxisMarks(preset: .aligned, position: .leading, values: rounds.map(String.init)) { value in
                    if let rank = value.as(String.self), let round = Int(rank) {
                        AxisValueLabel(centered: true, horizontalSpacing: 10) {
                            HStack(spacing: 6) {
                                FlagBadge(countryCode: meetingsByRound[round]?.countryCode)
                                    .accessibilityHidden(true)
                                Text("R\(round)")
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Color.primary)
                                    .frame(width: 31, height: 19)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.35))
                                    }
                            }
                        }
                    }
                }
            }
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { event in
                    guard let value: String = proxy.value(atY: event.location.y), let round = Int(value) else { return }
                    if sharedSelection != nil {
                        distributionWeekend = weekends.first { $0.meeting.round == round }
                    } else {
                        selectedDistributionRound = round
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: CGFloat(rounds.count) * 36 + 24)
        }
    }

    private func metricTitle(_ metric: ResultMetric) -> String {
        guard english else { return metric.rawValue }
        switch metric {
        case .wins: return "Wins"
        case .podiums: return "Podiums"
        case .points: return "Points Finishes"
        case .poles: return "Poles"
        case .retirements: return "Retired / Unclassified"
        }
    }

    private func resultBreakdown(_ shownEntries: [StandingEntry]) -> some View {
        let selectedMetrics = ResultMetric.allCases.filter { metrics.contains($0) }
        let races = weekends.flatMap { $0.sessions["race"]?.rows ?? [] }
        let qualifying = weekends.flatMap { $0.sessions["qualifying"]?.rows ?? [] }
        let values = shownEntries.flatMap { team in
            selectedMetrics.compactMap { metric -> MetricPoint? in
                let source = metric == .poles ? qualifying : races
                guard !source.isEmpty else { return nil }
                let count = source.count { $0.constructorId == team.id && metric.matches($0) }
                return MetricPoint(team: team, metric: metric, count: count)
            }
        }
        let chartMetrics = selectedMetrics.filter { metric in values.contains { $0.metric == metric } }
        return PulseCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(usingTeams ? copy("Constructor Performance", "车队赛季表现") : copy("Driver Performance", "车手赛季表现")).font(.headline)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(ResultMetric.allCases) { metric in
                            let active = metrics.contains(metric)
                            Button {
                                if active { metrics.remove(metric) }
                                else { metrics.insert(metric) }
                            } label: {
                                Label(metricTitle(metric), systemImage: active ? "checkmark.circle.fill" : "circle")
                                    .font(.caption)
                            }.buttonStyle(.glass)
                                .foregroundStyle(active ? metric.color : .secondary)
                                .accessibilityAddTraits(active ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
                if chartMetrics.isEmpty {
                    Text(selectedMetrics.isEmpty ? copy("Select Metrics", "请选择指标") : copy("No archived data for these metrics", "暂无此指标的归档数据"))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Chart(values) { item in
                        BarMark(x: .value(copy("Count", "次数"), item.metric == .retirements ? -item.count : item.count),
                                y: .value(copy("Team", "车队"), item.team.name))
                            .position(by: .value(copy("Metric", "指标"), metricTitle(item.metric)))
                            .foregroundStyle(by: .value(copy("Metric", "指标"), metricTitle(item.metric)))
                            .accessibilityLabel("\(item.team.name) · \(metricTitle(item.metric))")
                            .accessibilityValue(item.count.formatted())
                    }.pulseChart()
                    .chartForegroundStyleScale(domain: chartMetrics.map(metricTitle), range: chartMetrics.map(\.color))
                    .chartLegend(.hidden)
                    .frame(height: max(130, CGFloat(shownEntries.count * max(35, chartMetrics.count * 11) + 30)))
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(chartMetrics) { metric in
                                Label(metricTitle(metric), systemImage: "circle.fill")
                                    .labelStyle(.titleAndIcon).font(.caption)
                                    .foregroundStyle(metric.color)
                            }
                        }
                    }.scrollIndicators(.hidden)
                    Text(copy("Race results and qualifying poles. Unclassified finishes extend left.", "正赛统计 · 杆位取自排位赛 · 未完赛 / 未分类向左显示"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private struct MetricPoint: Identifiable {
        let team: StandingEntry
        let metric: ResultMetric
        let count: Int
        var id: String { "\(team.id)-\(metric.rawValue)" }
    }

    private func identifier(_ row: SessionResult) -> String {
        usingTeams ? row.constructorId : row.driverId
    }

    private func seriesColor(_ entry: StandingEntry) -> Color {
        let tint = DashboardArt.teamColor(entry.colorID)
        if usingTeams || entries.first(where: { $0.colorID == entry.colorID })?.id == entry.id { return tint }
        return tint.opacity(0.54)
    }

    private func share(_ points: Double, of total: Double) -> String {
        let fraction = total > 0 ? points / total : 0
        return copy("\(points.formatted()) pts · \(fraction.formatted(.percent.precision(.fractionLength(1))))", "\(points.formatted()) 分 · \(fraction.formatted(.percent.precision(.fractionLength(1))))")
    }

    private func roundTitle(_ round: Int) -> String {
        let meeting = weekends.first { $0.meeting.round == round }?.meeting.name
        return ["R\(round)", meeting].compactMap { $0 }.joined(separator: " · ")
    }

    private func loadPreviousChampion() async {
        guard compareChampion, previousChampion == nil,
              let season = entries.first?.season, let url = model.serverURL else { return }
        championUnavailable = false
        let context = model.dataContext
        do {
            let client = APIClient(baseURL: url)
            let champion: StandingEntry?
            let stale: Bool
            if usingTeams {
                let response = try await client.constructorStandings(season: season - 1, token: model.currentToken)
                champion = response.data.first { $0.position == 1 }.map(StandingEntry.init(team:))
                stale = response.meta.stale
            } else {
                let response = try await client.driverStandings(season: season - 1, token: model.currentToken)
                champion = response.data.first { $0.position == 1 }.map(StandingEntry.init(driver:))
                stale = response.meta.stale
            }
            guard context == model.dataContext, !Task.isCancelled else { return }
            previousChampion = champion
            championStale = stale
            championUnavailable = champion == nil
        } catch {
            guard context == model.dataContext, !Task.isCancelled else { return }
            championUnavailable = true
        }
    }
}

private struct ConstructorRoundPointsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let weekend: SeasonResultWeekend
    let season: Int

    private struct Team: Identifiable {
        let id: String
        let results: [SessionResult]
        var name: String { results.first?.team ?? id }
        var points: Double? { ConstructorRoundPointsSheet.points(results) }
        var color: Color { DashboardArt.teamColor(id) }
    }

    nonisolated private static func points(_ rows: [SessionResult]) -> Double? {
        guard rows.allSatisfy({ $0.points != nil }) else { return nil }
        return rows.compactMap(\.points).reduce(0, +)
    }

    var body: some View {
        let race = weekend.sessions["race"]?.rows ?? []
        let sprint = weekend.sessions["sprint"]?.rows ?? []
        let teams = Dictionary(grouping: race + sprint, by: \.constructorId)
            .map { Team(id: $0.key, results: $0.value) }
            .filter { ($0.points ?? 0) > 0 }
            .sorted { lhs, rhs in
                let left = lhs.points ?? -1, right = rhs.points ?? -1
                return left == right ? lhs.name < rhs.name : left > right
            }
        let maxPoints = max(1, teams.compactMap(\.points).max() ?? 0)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PulseCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(sprint.isEmpty ? "Race Points" : "Round Points · Including Sprint").font(.headline)
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                                ForEach(teams) { team in
                                    if let points = team.points {
                                        GridRow(alignment: .center) {
                                            AssetImage(name: MotorsportAssetName.name(kind: .teamLogo, id: team.id, season: season))
                                                .frame(width: 32, height: 24)
                                                .help(team.name)
                                            GeometryReader { geometry in
                                                RoundedRectangle(cornerRadius: 5)
                                                    .fill(team.color)
                                                    .frame(width: geometry.size.width * CGFloat(points / maxPoints))
                                            }
                                            .frame(height: 24)
                                            PulseNumber(points.formatted()).font(.caption.monospacedDigit().weight(.semibold))
                                                .gridColumnAlignment(.trailing)
                                        }
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(team.name)
                                        .accessibilityValue(pointsLabel(points))
                                    }
                                }
                            }
                        }
                    }
                    if teams.isEmpty {
                        Text("No archived constructor points").foregroundStyle(.secondary)
                    }
                    VStack(spacing: 10) {
                        ForEach(teams) { team in
                            PulseCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 8) {
                                        AssetImage(name: MotorsportAssetName.name(kind: .teamLogo, id: team.id, season: season))
                                            .frame(width: 30, height: 24).accessibilityHidden(true)
                                        Text(team.name).font(.subheadline.bold())
                                        Spacer()
                                        PulseNumber(pointsLabel(team.points)).font(.subheadline.monospacedDigit().bold())
                                    }
                                    let drivers = Dictionary(grouping: team.results, by: \.driverId).values
                                        .sorted { ($0.first?.position ?? Int.max, $0.first?.driverName ?? "") <
                                                  ($1.first?.position ?? Int.max, $1.first?.driverName ?? "") }
                                    ForEach(drivers.compactMap(\.first)) { driver in
                                        let raceResult = race.first { $0.driverId == driver.driverId && $0.constructorId == team.id }
                                        HStack(spacing: 8) {
                                            AssetImage(name: MotorsportAssetName.helmetName(driverID: driver.driverId, name: driver.driverName, season: season))
                                                .frame(width: 26, height: 23).accessibilityHidden(true)
                                            Text(driver.driverName)
                                            Spacer(minLength: 4)
                                            if let raceResult {
                                                Text(raceResult.classification.uppercased() == "CLASSIFIED"
                                                     ? raceResult.position.map { "P\($0)" } ?? raceResult.classification.uppercased()
                                                     : raceResult.classification.uppercased())
                                                    .foregroundStyle(.secondary)
                                            }
                                            PulseNumber(pointsLabel(Self.points(team.results.filter { $0.driverId == driver.driverId })))
                                                .monospacedDigit().frame(minWidth: 42, alignment: .trailing)
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(PulseStyle.background)
            .navigationTitle(weekend.meeting.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private func pointsLabel(_ points: Double?) -> String {
        points.map { $0.formatted() + " pts" } ?? "—"
    }
}

private struct RoundMovement {
    let round: Int
    let points: [String: Double]
    let previousRanks: [String: Int]

    init?(entries: [StandingEntry], weekends: [SeasonResultWeekend], teams: Bool) {
        let scored = weekends.sorted { $0.meeting.startDate < $1.meeting.startDate }
            .filter { weekend in
                ["race", "sprint"].contains { weekend.sessions[$0]?.rows.isEmpty == false }
            }
        guard let latest = scored.last, let round = latest.meeting.round else { return nil }
        self.round = round

        func id(_ row: SessionResult) -> String { teams ? row.constructorId : row.driverId }

        let latestRows = ["race", "sprint"].flatMap { latest.sessions[$0]?.rows ?? [] }
        points = Dictionary(grouping: latestRows, by: id).compactMapValues { rows in
            guard rows.allSatisfy({ $0.points != nil }) else { return nil }
            return rows.compactMap(\.points).reduce(0, +)
        }
        var totals: [String: Double] = [:]
        var finishes: [String: [Int: Int]] = [:]
        for weekend in scored.dropLast() {
            for kind in ["race", "sprint"] {
                for row in weekend.sessions[kind]?.rows ?? [] {
                    if let value = row.points { totals[id(row), default: 0] += value }
                    if kind == "race", let position = row.position, position > 0 {
                        finishes[id(row), default: [:]][position, default: 0] += 1
                    }
                }
            }
        }
        // Show movement only when archive points reconcile against the official table.
        // Penalties, missing sessions or a still-updating standings snapshot can prevent this.
        let roundPoints = points
        guard scored.count > 1, entries.allSatisfy({
            abs(totals[$0.id, default: 0] + roundPoints[$0.id, default: 0] - $0.points) < 0.001
        }) else {
            previousRanks = [:]
            return
        }
        let prior = entries.sorted { lhs, rhs in
            let a = totals[lhs.id, default: 0], b = totals[rhs.id, default: 0]
            if a != b { return a > b }
            for position in 1...30 {
                let a = finishes[lhs.id]?[position] ?? 0, b = finishes[rhs.id]?[position] ?? 0
                if a != b { return a > b }
            }
            return lhs.position < rhs.position
        }
        previousRanks = Dictionary(uniqueKeysWithValues: prior.enumerated().map { ($0.element.id, $0.offset + 1) })
    }
}

struct StandingEntry: Hashable {
    let id: String
    let name: String
    let team: String?
    let asset: String
    let colorID: String
    let season: Int
    let position: Int
    let points: Double
    let wins: Int

    init(driver: DriverStanding) {
        id = driver.id
        name = driver.driverName
        team = driver.constructor
        colorID = driver.constructorIds.first ?? driver.constructor
        season = driver.season
        position = driver.position
        points = driver.points
        wins = driver.wins
        asset = MotorsportAssetName.helmetName(driverID: driver.id, name: driver.driverName, season: driver.season)
    }

    init(team: ConstructorStanding) {
        id = team.id
        name = team.constructorName
        self.team = nil
        colorID = team.id
        season = team.season
        position = team.position
        points = team.points
        wins = team.wins
        asset = MotorsportAssetName.name(kind: .teamLogo, id: team.id, season: team.season)
    }
}

private struct ConstructorFinishingChart: View {
    let rounds: [AnalysisRound]
    let season: Int
    @State private var sprints = false
    @State private var selectedRound: Int?

    private struct Finish: Identifiable {
        let round: Int
        let driver: String
        let position: Int
        var id: String { "\(round)-\(driver)" }
    }

    var body: some View {
        let sessions = rounds.filter { $0.round != nil && !$0.entries.isEmpty }
        let hasSprints = sessions.contains { $0.sessionType == "Sprint" }
        let hasRaces = sessions.contains { $0.sessionType != "Sprint" }
        let shown = sessions.filter { ($0.sessionType == "Sprint") == (hasSprints && (sprints || !hasRaces)) }
            .sorted { ($0.round ?? 0) < ($1.round ?? 0) }
        let samples = shown.flatMap { session -> [Finish] in
            guard let round = session.round else { return [] }
            return session.entries.compactMap { result in
                guard let driver = result.driverName, let position = result.position, position > 0 else { return nil }
                return Finish(round: round, driver: driver, position: position)
            }
        }
        let drivers = Set(samples.map(\.driver)).sorted()
        let depth = max(20, samples.map(\.position).max() ?? 0)
        let focused = selectedRound.flatMap { round in shown.min { abs(($0.round ?? 0) - round) < abs(($1.round ?? 0) - round) } } ?? shown.last
        VStack(alignment: .leading, spacing: 12) {
            Text("Finishing Positions by Round").font(.headline).accessibilityAddTraits(.isHeader)
            if hasSprints && hasRaces {
                PulseSectionPicker(sections: [(false, "Race"), (true, "Sprint")], selection: $sprints)
                    .onChange(of: sprints) { selectedRound = nil }
            }
            if let first = shown.first?.round, let last = shown.last?.round, !samples.isEmpty {
                Chart {
                    if let round = focused?.round {
                        RuleMark(x: .value("Round", round)).foregroundStyle(Color.secondary.opacity(0.4))
                    }
                    ForEach(samples) { finish in
                        LineMark(x: .value("Round", finish.round), y: .value("Position", -finish.position), series: .value("Driver", finish.driver))
                            .foregroundStyle(by: .value("Driver", finish.driver))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        PointMark(x: .value("Round", finish.round), y: .value("Position", -finish.position))
                            .foregroundStyle(by: .value("Driver", finish.driver))
                            .symbol(by: .value("Driver", finish.driver))
                            .symbolSize(finish.round == focused?.round ? 62 : 24)
                            .accessibilityLabel("\(finish.driver), round \(finish.round)")
                            .accessibilityValue("Position \(finish.position)")
                    }
                }.pulseChart()
                .chartForegroundStyleScale(domain: drivers, range: [.blue, .orange, .purple, .teal])
                .chartXScale(domain: (Double(first) - 0.5)...(Double(last) + 0.5))
                .chartYScale(domain: (-Double(depth) - 0.5)...(-0.5))
                .chartXAxis {
                    AxisMarks(values: Array(stride(from: first, through: last, by: max(1, (last - first + 4) / 5)))) { value in
                        AxisValueLabel { if let round = value.as(Int.self) { Text("R\(round)") } }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: Array(stride(from: -20, through: -5, by: 5)) + [-1]) { value in
                        AxisGridLine()
                        AxisValueLabel { if let rank = value.as(Int.self) { Text("P\(-rank)") } }
                    }
                }
                .chartXSelection(value: $selectedRound)
                .frame(height: 200)
            } else {
                Text("No finishing positions to plot").font(.subheadline).foregroundStyle(.secondary)
            }
            if let focused { readout(focused) }
        }
        .padding(14)
        .dashboardPanel(WebDashboardStyle.homePanel)
        .accessibilityIdentifier("constructors.finishingChart")
    }

    private func readout(_ session: AnalysisRound) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text([session.round.map { "R\($0)" }, session.raceName].compactMap { $0 }.joined(separator: " · "))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) { driverResults(session.entries) }
                VStack(spacing: 8) { driverResults(session.entries) }
            }
        }
    }

    @ViewBuilder private func driverResults(_ entries: [AnalysisEntry]) -> some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, result in
            let name = result.driverName ?? "—"
            HStack(spacing: 6) {
                AssetImage(name: MotorsportAssetName.helmetName(driverID: result.driverId, name: name, season: season))
                    .frame(width: 26, height: 24).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.caption.weight(.medium)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    Text([result.position.map { "P\($0)" } ?? result.status ?? "—", result.points.map { "\($0.formatted()) pts" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

struct StandingProfile: View {
    @Environment(\.pulseEnglishPresentation) private var english

    private func copy(_ englishText: @autoclosure () -> String, _ original: @autoclosure () -> String) -> String {
        english ? englishText() : original()
    }

    @EnvironmentObject private var model: MobileModel
    let entry: StandingEntry
    @State private var analysis: APIEnvelope<SeasonAnalysis>?
    @State private var priorAnalysis: SeasonAnalysis?
    @State private var comparePrevious = false
    @State private var priorUnavailable = false
    @State private var priorStale = false
    @State private var selectedPointsRound: Int?
    @State private var selectedContributionRound: Int?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 18) {
                    AssetImage(name: entry.asset).frame(width: 82, height: 76)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.name).font(.title2.bold())
                        if let team = entry.team { Text(team).foregroundStyle(.secondary) }
                        Text(copy("P\(entry.position) · \(entry.points.formatted()) pts · \(entry.wins) wins", "P\(entry.position) · \(entry.points.formatted()) 分 · \(entry.wins) 胜"))
                            .font(.subheadline.monospacedDigit())
                    }
                }
                if entry.team == nil, let car = DashboardArt.image(.carSide, id: entry.id, season: entry.season) {
                    Image(uiImage: car).resizable().scaledToFit().frame(maxHeight: 95)
                        .frame(maxWidth: .infinity).accessibilityHidden(true)
                }
                driverContext
                if let analysis {
                    let trend = analysis.data.cumulativePointsByRound
                    if analysis.meta.stale { Text(copy("Trend Data Is Stale", "趋势数据已过期")).foregroundStyle(.secondary) }
                    if !trend.isEmpty {
                        Text(copy("Cumulative Points", "累计积分")).font(.headline)
                        if entry.season > 2023 {
                            Toggle(copy("Compare with Last Season", "与上季比较"), isOn: $comparePrevious).font(.subheadline)
                        }
                        pointsChart(trend)
                        if comparePrevious && priorAnalysis == nil {
                            if priorUnavailable { Text(copy("No comparable points from last season", "上季暂无可比较积分")).font(.caption).foregroundStyle(.secondary) }
                            else { Group { if english { PulseSkeleton(label: "Loading last season's points…") } else { ProgressView("读取上季积分…") } }.font(.caption) }
                        }
                    }
                    if entry.team == nil {
                        ConstructorFinishingChart(rounds: analysis.data.rounds, season: entry.season)
                        constructorContribution(analysis.data.rounds)
                    } else {
                        driverStatistics
                        driverRoundHistory(analysis.data.rounds)
                    }
                    ForEach(analysis.data.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
                if let error { Text(english ? error.pulseEnglishError : error).foregroundStyle(.secondary) }
                else if analysis == nil { Group { if english { PulseSkeleton(label: "Loading season performance…", chart: true) } else { ProgressView("读取赛季表现…") } } }
            }.padding(.horizontal, 20).padding(.vertical, 20)
        }
        .background(PulseStyle.background)
        .navigationTitle(entry.team == nil ? entry.name : String(entry.season))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if entry.team != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.favoriteDriverID = model.favoriteDriverID == entry.id ? nil : entry.id
                    } label: {
                        Label(copy("Favorite driver", "收藏车手"), systemImage: model.favoriteDriverID == entry.id ? "star.fill" : "star")
                    }
                }
            }
        }
        .task(id: model.dataContext) {
            async let archive: Void = entry.team == nil ? () : model.loadSeasonArchive()
            await load()
            await archive
        }
        .task(id: "\(comparePrevious)-\(model.dataContext)") {
            guard comparePrevious, let url = model.serverURL else { return }
            let context = model.dataContext
            priorAnalysis = nil
            priorUnavailable = false
            do {
                let response = try await APIClient(baseURL: url).seasonAnalysis(
                    kind: entry.team == nil ? "constructors" : "drivers",
                    id: entry.id, season: entry.season - 1, token: model.currentToken
                )
                guard !Task.isCancelled, model.dataContext == context else { return }
                priorStale = response.meta.stale
                if !response.data.cumulativePointsByRound.isEmpty { priorAnalysis = response.data }
                else { priorUnavailable = true }
            } catch {
                guard !Task.isCancelled, model.dataContext == context else { return }
                priorUnavailable = true
            }
        }
        .refreshable { await load() }
    }

    @ViewBuilder private func driverRoundHistory(_ rounds: [AnalysisRound]) -> some View {
        Text(copy("Performance by Round", "逐站表现")).font(.headline)
        ForEach(Array(rounds.enumerated().reversed()), id: \.offset) { _, round in
            VStack(alignment: .leading, spacing: 8) {
                Text([round.round.map { "R\($0)" }, round.raceName, round.sessionType]
                    .compactMap { $0 }.joined(separator: " · ")).font(.subheadline.bold())
                ForEach(Array(round.entries.enumerated()), id: \.offset) { _, result in
                    HStack {
                        Text(result.driverName ?? entry.name)
                        Spacer()
                        Text(result.position.map { "P\($0)" } ?? result.status ?? "—")
                        Text(result.points.map { copy("\($0.formatted()) pts", "\($0.formatted()) 分") } ?? "—")
                    }.font(.subheadline.monospacedDigit())
                }
            }
        }
        if rounds.isEmpty { Text(copy("No round records", "暂无逐站记录")).foregroundStyle(.secondary) }
    }

    private func pointsChart(_ trend: [(round: Int, points: Double)]) -> some View {
        let current = String(entry.season)
        let previous = String(entry.season - 1)
        let samples = trend.map { ProfilePoint(year: current, round: $0.round, points: $0.points) }
            + (comparePrevious ? priorAnalysis?.cumulativePointsByRound ?? [] : [])
                .map { ProfilePoint(year: previous, round: $0.round, points: $0.points) }
        let comparing = comparePrevious && priorAnalysis != nil
        let tint = entry.team == nil ? DashboardArt.teamColor(entry.id) : PulseStyle.red
        return VStack(alignment: .leading, spacing: 9) {
            Chart {
                ForEach(samples) { item in
                    LineMark(x: .value(copy("Round", "站"), item.round), y: .value(copy("Points", "积分"), item.points),
                             series: .value(copy("Season", "赛季"), item.year))
                        .foregroundStyle(by: .value(copy("Season", "赛季"), item.year))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: item.year == current ? [] : [4, 3]))
                    if item.round == selectedPointsRound {
                        PointMark(x: .value(copy("Round", "站"), item.round), y: .value(copy("Points", "积分"), item.points))
                            .foregroundStyle(by: .value(copy("Season", "赛季"), item.year))
                    }
                }
                if let selectedPointsRound {
                    RuleMark(x: .value(copy("Selected Round", "选中轮次"), selectedPointsRound)).foregroundStyle(.secondary.opacity(0.6))
                }
            }.pulseChart()
            .chartForegroundStyleScale(domain: comparing ? [current, previous] : [current],
                                       range: comparing ? [tint, Color.secondary] : [tint])
            .chartXSelection(value: $selectedPointsRound)
            .frame(height: 175)
            if let selectedPointsRound {
                let selected = samples.filter { $0.round == selectedPointsRound }
                ForEach(selected) { item in
                    LabeledContent("\(item.year) · R\(selectedPointsRound)", value: item.points.formatted() + copy(" pts", " 分"))
                        .font(.caption.monospacedDigit())
                }
                if selected.count == 2 {
                    let delta = selected[0].points - selected[1].points
                    LabeledContent(copy("Year-over-Year", "同比"), value: delta.formatted(.number.sign(strategy: .always())) + copy(" pts", " 分"))
                        .font(.caption.monospacedDigit())
                }
            }
            if comparing && priorStale { Text(copy("Last season's trend is cached", "上季走势使用缓存")).font(.caption).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func constructorContribution(_ rounds: [AnalysisRound]) -> some View {
        let racePoints = rounds.flatMap { group -> [Contribution] in
            guard let round = group.round, group.points != nil else { return [] }
            return group.entries.compactMap { result in
                guard let driver = result.driverId, let name = result.driverName, let points = result.points else { return nil }
                return Contribution(round: round, driver: driver, name: name, points: points)
            }
        }
        let samples = Dictionary(grouping: racePoints, by: \.id).values.compactMap { group -> Contribution? in
            guard let item = group.first else { return nil }
            return Contribution(round: item.round, driver: item.driver, name: item.name,
                                points: group.reduce(0) { $0 + $1.points })
        }.sorted { ($0.round, $0.driver) < ($1.round, $1.driver) }
        let grouped = Dictionary(grouping: samples, by: \.driver)
        let totals = grouped.values.compactMap { group -> Contribution? in
            guard let item = group.first else { return nil }
            return Contribution(round: 0, driver: item.driver, name: item.name,
                                points: group.reduce(0) { $0 + $1.points })
        }.sorted { ($0.points, $0.driver) > ($1.points, $1.driver) }
        let total = totals.reduce(0) { $0 + $1.points }
        if total > 0 {
            let colors = [DashboardArt.teamColor(entry.id), Color.indigo, .orange, .mint, .purple]
            let names = totals.map(\.name)
            let scale = names.indices.map { colors[$0 % colors.count] }
            PulseCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(copy("Driver Points Contribution", "车手积分贡献")).font(.headline)
                    Chart(totals) { item in
                        BarMark(x: .value(copy("Points", "积分"), item.points), stacking: .normalized)
                            .foregroundStyle(by: .value(copy("Driver", "车手"), item.name))
                    }.pulseChart()
                    .chartForegroundStyleScale(domain: names, range: scale)
                    .chartLegend(.hidden).chartXAxis(.hidden).chartYAxis(.hidden)
                    .frame(height: 28)
                    ForEach(Array(totals.enumerated()), id: \.element.id) { index, item in
                        LabeledContent {
                            Text(copy("\(item.points.formatted()) pts · \((item.points / total).formatted(.percent.precision(.fractionLength(1))))", "\(item.points.formatted()) 分 · \((item.points / total).formatted(.percent.precision(.fractionLength(1))))"))
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(scale[index]).frame(width: 8, height: 8).accessibilityHidden(true)
                                Text(item.name)
                            }
                        }.font(.caption.monospacedDigit())
                    }
                    Text(copy("Driver Points by Round", "各站车手得分")).font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal) {
                    Chart {
                        ForEach(samples) { value in
                            BarMark(x: .value(copy("Round", "轮次"), value.round), y: .value(copy("Points", "积分"), value.points), width: 24)
                                .foregroundStyle(by: .value(copy("Driver", "车手"), value.name))
                                .opacity(selectedContributionRound == nil || selectedContributionRound == value.round ? 1 : 0.4)
                        }
                        if let selectedContributionRound {
                            RuleMark(x: .value(copy("Selected Round", "选中轮次"), selectedContributionRound)).foregroundStyle(.secondary.opacity(0.6))
                        }
                    }.pulseChart()
                    .chartForegroundStyleScale(domain: names, range: scale)
                    .chartLegend(.hidden)
                    .chartXAxis { AxisMarks { AxisValueLabel() } }
                    .chartYAxis { AxisMarks { AxisValueLabel() } }
                    .chartXSelection(value: $selectedContributionRound)
                    .frame(width: max(240, CGFloat((samples.map(\.round).max() ?? 1) + 1) * 33), height: 175)
                    }
                    if let selectedContributionRound {
                        ForEach(samples.filter { $0.round == selectedContributionRound }) { value in
                            LabeledContent("R\(selectedContributionRound) · \(value.name)", value: value.points.formatted() + copy(" pts", " 分"))
                                .font(.caption.monospacedDigit())
                        }
                    }
                    Text(copy("Includes archived sprint points.", "基于归档积分，含冲刺赛")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private struct Contribution: Identifiable {
        let round: Int
        let driver: String
        let name: String
        let points: Double
        var id: String { "\(round)-\(driver)" }
    }

    private struct ProfilePoint: Identifiable {
        let year: String
        let round: Int
        let points: Double
        var id: String { "\(year)-\(round)" }
    }

    @ViewBuilder private var driverContext: some View {
        if let team = entry.team, entry.season == model.season,
           let leader = model.driverRoster.min(by: { $0.position < $1.position }) {
            let teammates = model.driverRoster.filter { $0.constructor == team }
            let other = teammates.filter { $0.id != entry.id }.max { $0.points < $1.points }
            let teamPoints = teammates.reduce(0) { $0 + $1.points }
            PulseCard {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent(copy("Gap to Leader", "距榜首"), value: entry.position == 1 ? copy("Leader", "领跑") : copy("\((leader.points - entry.points).formatted()) pts", "\((leader.points - entry.points).formatted()) 分"))
                        .font(.subheadline.monospacedDigit())
                    if teamPoints > 0, entry.points >= 0, entry.points <= teamPoints {
                        let share = entry.points / teamPoints
                        VStack(alignment: .leading, spacing: 7) {
                            LabeledContent(copy("Share of Team Points", "车队车手积分占比"), value: share.formatted(.percent.precision(.fractionLength(1))))
                                .font(.subheadline.monospacedDigit())
                            ProgressView(value: share).tint(PulseStyle.red).accessibilityHidden(true)
                        }
                    }
                    if let other {
                        let gap = (entry.points - other.points).formatted(.number.sign(strategy: .always()))
                        LabeledContent(copy("vs. \(other.driverName)", "对 \(other.driverName)"), value: copy("\(gap) pts", "\(gap) 分"))
                            .font(.subheadline.monospacedDigit())
                        NavigationLink {
                            DriverComparison(firstDriverID: entry.id, secondDriverID: other.id)
                                .navigationTitle("Head to Head")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label(copy("View Teammate Comparison", "查看队友对比"), systemImage: "arrow.left.arrow.right")
                        }.buttonStyle(.glass)
                    }
                    if model.rosterSavedAt == .distantPast {
                        Text(copy("Standings cache is stale", "积分缓存已过期")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var driverStatistics: some View {
        if let archive = model.seasonArchive, entry.season == model.season {
            let races = archive.data.compactMap { $0.sessions["race"]?.rows.first { $0.id == entry.id } }
            let qualifying = archive.data.compactMap { $0.sessions["qualifying"]?.rows.first { $0.id == entry.id } }
            if !races.isEmpty || !qualifying.isEmpty {
                driverPerformance(races, qualifying: qualifying, stale: archive.meta.stale)
                driverResultCharts(archive.data)
            }
        }
    }

    private func driverPerformance(_ races: [SessionResult], qualifying: [SessionResult], stale: Bool) -> some View {
        let scored = races.compactMap(\.points)
        let inPoints = scored.count { $0 > 0 }
        let pointsRate = scored.isEmpty ? nil : Double(inPoints) / Double(scored.count)
        let podiums = races.count { (1...3).contains($0.position ?? 0) && $0.classification.uppercased() == "CLASSIFIED" }
        let retired = races.count { ["DNF", "DNS", "DSQ", "NC"].contains($0.classification.uppercased()) }
        let metrics = [
            (copy("Race Wins", "正赛获胜"), races.count { $0.position == 1 && $0.classification.uppercased() == "CLASSIFIED" }, races.count, Color.orange),
            (copy("Race Podiums", "正赛领奖台"), podiums, races.count, Color.blue),
            (copy("Pole Positions", "排位杆位"), qualifying.count { $0.position == 1 && $0.classification.uppercased() == "CLASSIFIED" }, qualifying.count, Color.purple),
            (copy("Retired / Unclassified", "退赛 / 未分类"), retired, races.count, PulseStyle.red)
        ]
        return PulseCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(copy("Season Performance", "赛季表现")).font(.headline)
                if let pointsRate {
                    HStack(spacing: 14) {
                        ZStack {
                            Chart {
                                SectorMark(angle: .value(copy("Points Finishes", "得分场次"), inPoints), innerRadius: .ratio(0.76))
                                    .foregroundStyle(PulseStyle.red)
                                SectorMark(angle: .value(copy("Non-Scoring Races", "零分场次"), scored.count - inPoints), innerRadius: .ratio(0.76))
                                    .foregroundStyle(.secondary.opacity(0.23))
                            }.pulseChart().chartLegend(.hidden)
                            PulseNumber(pointsRate.formatted(.percent.precision(.fractionLength(0))))
                                .font(.headline.monospacedDigit())
                        }.frame(width: 80, height: 80)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(copy("Points Finish Rate", "正赛得分率")).font(.subheadline.weight(.semibold))
                            Text(copy("\(inPoints) of \(scored.count) races scored", "\(inPoints) / \(scored.count) 场有积分"))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }.accessibilityElement(children: .combine)
                }
                ForEach(metrics, id: \.0) { label, count, total, tint in
                    if total > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(label, value: "\(count) / \(total)")
                                .font(.subheadline.monospacedDigit())
                            ProgressView(value: Double(count), total: Double(total))
                                .tint(tint)
                                .accessibilityHidden(true)
                        }
                    }
                }
                if stale { Text(copy("Cached Data · Stale", "缓存数据 · 已过期")).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder private func driverResultCharts(_ weekends: [SeasonResultWeekend]) -> some View {
        let rounds = weekends.compactMap { weekend -> DriverRoundChartPoint? in
            guard let round = weekend.meeting.round,
                  let row = weekend.sessions["race"]?.rows.first(where: { $0.id == entry.id }) else { return nil }
            return DriverRoundChartPoint(id: round, grid: row.gridPosition, result: row)
        }
        let finishes = rounds.filter { $0.result.classification.uppercased() == "CLASSIFIED" && ($0.result.position ?? 0) > 0 }
        if !rounds.isEmpty {
            PulseCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(copy("Race Finish Distribution", "正赛完赛名次分布")).font(.headline)
                    let positions = finishes.compactMap { $0.result.position }
                    let counts = Dictionary(grouping: positions, by: { $0 }).mapValues(\.count)
                    let notClassified = rounds.count - positions.count
                    let entries = counts.keys.sorted().map { (label: "P\($0)", count: counts[$0] ?? 0) }
                        + (notClassified > 0 ? [(label: copy("Unclassified", "未分类"), count: notClassified)] : [])
                    if let best = positions.min() {
                        let average = Double(positions.reduce(0, +)) / Double(positions.count)
                        Text(copy("Best P\(best) · Average P\(average.formatted(.number.precision(.fractionLength(1))))", "最佳 P\(best) · 平均 P\(average.formatted(.number.precision(.fractionLength(1))))"))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Chart(entries, id: \.label) { value in
                        BarMark(x: .value(copy("Session", "场次"), value.count), y: .value(copy("Position", "名次"), value.label), height: 24)
                            .foregroundStyle(value.label == copy("Unclassified", "未分类") ? Color.secondary : PulseStyle.red)
                            .cornerRadius(3)
                            .annotation(position: .trailing) {
                                PulseNumber(value.count.formatted()).font(.caption.monospacedDigit())
                            }
                    }.pulseChart()
                    .chartXScale(domain: 0...((entries.map(\.count).max() ?? 0) + 1))
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(preset: .aligned, position: .leading, values: entries.map(\.label)) { value in
                            if let label = value.as(String.self) {
                                AxisValueLabel(label, centered: true, horizontalSpacing: 10)
                            }
                        }
                    }
                    .frame(height: max(84, CGFloat(entries.count) * 36))
                    .accessibilityLabel(copy("Number of races by finishing position", "按正赛完赛名次统计场次"))

                }
            }
        }
        if !finishes.isEmpty {
            PulseCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(copy("Grid and Finishing Positions", "发车位与完赛位置")).font(.headline)
                    Chart(finishes) { round in
                        if let position = round.result.position {
                            PointMark(x: .value(copy("Round", "轮次"), round.id), y: .value(copy("Finish", "完赛"), position))
                                .foregroundStyle(by: .value(copy("Position", "位置"), copy("Finish", "完赛")))
                            if let grid = round.grid, grid > 0 {
                                RuleMark(x: .value(copy("Round", "轮次"), round.id),
                                         yStart: .value(copy("Start", "发车"), grid), yEnd: .value(copy("Finish", "完赛"), position))
                                    .foregroundStyle(.secondary.opacity(0.5))
                                PointMark(x: .value(copy("Round", "轮次"), round.id), y: .value(copy("Start", "发车"), grid))
                                    .foregroundStyle(by: .value(copy("Position", "位置"), copy("Start", "发车")))
                            }
                        }
                    }.pulseChart()
                    .chartForegroundStyleScale([copy("Start", "发车"): Color.secondary, copy("Finish", "完赛"): PulseStyle.red])
                    .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                    .frame(height: 165)
                }
            }
        }
        let points = rounds.filter { $0.result.points != nil }
        if !points.isEmpty {
            PulseCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(copy("Race Points by Round", "各站正赛得分")).font(.headline)
                    Chart(points) { round in
                        if let points = round.result.points {
                            BarMark(x: .value(copy("Round", "轮次"), round.id), y: .value(copy("Points", "积分"), points))
                                .foregroundStyle(DashboardArt.teamColor(round.result.constructorId))
                                .cornerRadius(3)
                        }
                    }.pulseChart().frame(height: 145)
                }
            }
        }
    }

    private struct DriverRoundChartPoint: Identifiable {
        let id: Int
        let grid: Int?
        let result: SessionResult
    }

    private func load() async {
        guard let url = model.serverURL else { error = copy("Invalid server address", "服务器地址无效"); return }
        let context = model.dataContext
        do {
            let response = try await APIClient(baseURL: url).seasonAnalysis(
                kind: entry.team == nil ? "constructors" : "drivers",
                id: entry.id, season: entry.season, token: model.currentToken
            )
            guard context == model.dataContext, !Task.isCancelled else { return }
            analysis = response
            error = nil
        } catch {
            if context == model.dataContext, !Task.isCancelled { self.error = MobileModel.message(for: error) }
        }
    }
}
