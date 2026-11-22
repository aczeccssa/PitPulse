import Charts
import SharedData
import SwiftUI

struct DriverScore {
    let performance: Double?
    let teammate: Double?

    init(driverID: String, teammateID: String?, weekends: [SeasonResultWeekend]) {
        var race: [Double] = []
        var qualifying: [Double] = []
        var matches: [Double] = []
        for weekend in weekends {
            for kind in ["race", "qualifying"] {
                guard let rows = weekend.sessions[kind]?.rows, rows.count > 1,
                      let own = rows.first(where: { $0.id == driverID }) else { continue }
                if let position = own.position, (1...rows.count).contains(position),
                   own.classification.uppercased() == "CLASSIFIED" {
                    let percentile = Double(rows.count - position) / Double(rows.count - 1)
                    if kind == "race" { race.append(percentile) }
                    else { qualifying.append(percentile) }
                }
                if let teammateID, let rival = rows.first(where: { $0.id == teammateID }),
                   own.constructorId == rival.constructorId,
                   let winner = comparisonWinner(own, rival, onlyClassified: false) {
                    matches.append(winner == 0 ? 0.5 : winner > 0 ? 1 : 0)
                }
            }
        }
        func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        if let raceAverage = average(race) {
            performance = average(qualifying).map { (raceAverage * 0.7 + $0 * 0.3) * 100 } ?? (raceAverage * 100)
        } else {
            performance = nil
        }
        self.teammate = average(matches).map { $0 * 100 }
    }
}

private struct DriverTile: View {
    let driver: DriverStanding

    var body: some View {
        let id = driver.constructorIds.first ?? driver.constructor
        let tint = DashboardArt.teamColor(id)
        let shortName = driver.driverName.split(separator: " ").last.map(String.init) ?? driver.driverName
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                if let logo = DashboardArt.image(.teamLogo, id: id, season: driver.season) {
                    Image(uiImage: logo).resizable().scaledToFit()
                        .frame(width: width * 0.54, height: height * 0.70)
                        .opacity(0.34).offset(x: width * 0.32, y: height * 0.12)
                }
                Group {
                    if let photo = DashboardArt.image(.driverPhoto, id: driver.id, season: driver.season) {
                        Image(uiImage: photo).resizable().scaledToFit()
                    } else {
                        AssetImage(name: StandingEntry(driver: driver).asset)
                    }
                }.frame(width: width * 0.45, height: height * 0.88, alignment: .bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(shortName).font(.headline).foregroundStyle(tint)
                    Text(driver.constructor).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(driver.driverNumber ?? "—").font(.title3.bold()).monospacedDigit()
                }.lineLimit(2).frame(width: width * 0.49, alignment: .leading).padding(12)
            }
        }
        .aspectRatio(1.35, contentMode: .fit)
        .background {
            PulseStyle.cardShape
                .fill(PulseStyle.surface)
                .overlay {
                PulseStyle.cardShape.fill(
                        LinearGradient(colors: [tint.opacity(0.29), tint.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                }
        }
        .clipShape(PulseStyle.cardShape)
        .overlay { PulseStyle.cardShape.strokeBorder(tint.opacity(0.45)).allowsHitTesting(false) }
        .accessibilityElement(children: .combine)
    }
}

struct DriverComparison: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.pulseEnglishPresentation) private var english
    @State private var selectedQualifyingRound: Int?
    @State private var showQualifyingDistribution = false
    @State private var highlightLatestQualifying = false
    @State private var selectedQualifyingGap: Double?
    @State private var selectedFinish: Int?
    @State private var showFilters = false
    @State private var first: String
    @State private var second: String
    @State private var category: SessionType
    @State private var combineSprint: Bool
    @State private var excludeRetirements: Bool

    private let teammateTeamID: String?

    init(
        firstDriverID: String = "",
        secondDriverID: String = "",
        teammateTeamID: String? = nil,
        category: SessionType = .race,
        combineSprint: Bool = false,
        excludeRetirements: Bool = false
    ) {
        self.teammateTeamID = teammateTeamID
        _first = State(initialValue: firstDriverID)
        _second = State(initialValue: secondDriverID)
        _category = State(initialValue: category)
        _combineSprint = State(initialValue: combineSprint)
        _excludeRetirements = State(initialValue: excludeRetirements)
    }

    private var isQualifying: Bool { category == .qualifying || category == .sprintQualifying }

    var body: some View {
        List {
            if english, !first.isEmpty, !second.isEmpty {
                comparisonCard("Matchup") {
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: 12))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                    layout {
                        driverIdentity(first, marker: "circle.fill", color: .teal)
                        driverIdentity(second, marker: "diamond.fill", color: .indigo)
                    }
                }
            } else if let left = model.driverRoster.first(where: { $0.id == first }),
                      let right = model.driverRoster.first(where: { $0.id == second }) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 10))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
                layout {
                    DriverTile(driver: left)
                    DriverTile(driver: right)
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else if teammateTeamID != nil {
                Text("\(name(first)) / \(name(second))").font(.headline)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            Group {
                if english {
                    PulseSectionPicker<SessionType>(
                        sections: [(.race, "Race"), (.qualifying, "Qualifying"), (.sprint, "Sprint")],
                        selection: Binding(
                            get: { category == .sprintQualifying ? .sprint : category },
                            set: { category = $0 }
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        DisclosureGroup(isExpanded: $showFilters) {
                            if teammateTeamID == nil {
                                picker("车手 1", selection: $first, excluding: second)
                                picker("车手 2", selection: $second, excluding: first)
                            }
                            PulseSectionPicker(sections: comparisonCategoriesForPicker, selection: $category)
                            comparisonToggles
                        } label: {
                            Label(category.displayName, systemImage: "line.3.horizontal.decrease")
                                .accessibilityLabel("比较设置：\(category.displayName)")
                        }
                    }.listRowBackground(PulseStyle.surface)
                }
            }
            if let archive = model.seasonArchive, !first.isEmpty, !second.isEmpty {
                if archive.meta.stale {
                    Label(copy("Season results may be out of date", "赛季成绩已过期"), systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                let pairs = comparisons(in: archive.data)
                let firstName = name(first)
                let secondName = name(second)
                if pairs.isEmpty {
                    ContentUnavailableView(copy("No Shared Results", "暂无可比较场次"), systemImage: "chart.bar")
                        .listRowBackground(Color.clear)
                } else {
                    comparisonCard(copy("Head-to-Head Results", "同场排名对比 · \(pairs.count) 场")) {
                        let left = pairs.count { $0.winner == 1 }
                        let right = pairs.count { $0.winner == -1 }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                PulseNumber(String(left)).font(.title2.bold().monospacedDigit())
                                    .foregroundStyle(english ? Color.teal : Color.primary)
                                Spacer()
                                PulseNumber(String(right)).font(.title2.bold().monospacedDigit())
                                    .foregroundStyle(english ? Color.indigo : Color.primary)
                            }
                            GeometryReader { geometry in
                                HStack(spacing: 0) {
                                    Color.teal.frame(width: geometry.size.width * CGFloat(left) / CGFloat(pairs.count))
                                    Color.secondary.opacity(0.24)
                                    Color.indigo.frame(width: geometry.size.width * CGFloat(right) / CGFloat(pairs.count))
                                }
                            }.frame(height: 8).clipShape(.capsule).accessibilityHidden(true)
                            HStack {
                                Text(firstName).foregroundStyle(.secondary)
                                Spacer()
                                Text(secondName).foregroundStyle(.secondary)
                            }.font(.caption)
                            if english {
                                let ties = pairs.count - left - right
                                Text("\(pairs.count) sessions · \(ties) \(ties == 1 ? "tie" : "ties")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if category == .race || category == .sprint {
                        championship(archive.data)
                    }
                    comparisonCard(copy("Position Distribution", "名次分布")) {
                        let bins = finishCounts(pairs.compactMap(\.first), driver: firstName)
                            + finishCounts(pairs.compactMap(\.second), driver: secondName)
                        Chart(bins) { bin in
                            BarMark(x: .value(copy("Position", "名次"), bin.position), y: .value(copy("Count", "次数"), bin.count))
                                .foregroundStyle(by: .value(copy("Driver", "车手"), bin.driver))
                                .position(by: .value(copy("Driver", "车手"), bin.driver))
                        }
                        .chartForegroundStyleScale(domain: [firstName, secondName], range: [.teal, .indigo])
                        .frame(height: 170)
                        .pulseChart()
                    }
                    if isQualifying {
                        qualifyingGaps(pairs)
                        comparisonCard(copy("Team Gap to Pole", "车队距杆位")) {
                            let teams = teammateTeamID.map { Set([$0]) } ?? Set(model.driverRoster
                                .filter { $0.id == first || $0.id == second }.compactMap { $0.constructorIds.first })
                            TeamPoleTrend(weekends: archive.data, teamIDs: teams, types: comparisonCategories)
                        }
                        poles(archive.data)
                    }
                    finishTrend(pairs)
                }
            }
            if let error = model.seasonArchiveError {
                Text(english ? error.pulseEnglishError : error).foregroundStyle(.secondary)
                Button(copy("Retry", "重试")) { Task { await model.loadSeasonArchive(force: true) } }
            } else if model.seasonArchive == nil {
                if english { PulseSkeleton(label: "Loading season results", chart: true).listRowBackground(Color.clear) }
                else { ProgressView("读取赛季成绩…") }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, english ? 8 : nil, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(PulseStyle.background)
        .pulseSwap(model.seasonArchive != nil)
        .pulseSwap(comparisonCategories)
        .dashboardDetail()
        .toolbar {
            if english {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        comparisonToggles
                        if category == .sprint || category == .sprintQualifying {
                            Picker("Sprint Session", selection: $category) {
                                Text("Sprint Race").tag(SessionType.sprint)
                                Text("Sprint Qualifying").tag(SessionType.sprintQualifying)
                            }
                        }
                    } label: {
                        Label("Comparison Options", systemImage: "ellipsis").labelStyle(.iconOnly)
                    }
                }
            }
        }
        .task(id: model.dataContext) { await model.loadSeasonArchive() }
        .refreshable { await model.loadSeasonArchive(force: true) }
        .onChange(of: comparisonCategories) { resetChartSelections() }
        .onChange(of: first) { resetChartSelections() }
        .onChange(of: second) { resetChartSelections() }
        .onChange(of: excludeRetirements) { resetChartSelections() }
        .onChange(of: model.dataContext) { resetChartSelections() }
        .onChange(of: model.driverRoster.map(\.id), initial: true) { _, ids in
            guard teammateTeamID == nil, let leader = model.driverRoster.first else { return }
            if first.isEmpty || (!english && !ids.contains(first)) { first = leader.id }
            if second == first || second.isEmpty || (!english && !ids.contains(second)) {
                let driver = model.driverRoster.first { $0.id == first }
                let candidates = model.driverRoster.filter { $0.id != first }
                second = candidates.first { $0.constructor == driver?.constructor }?.id
                    ?? candidates.first?.id ?? ""
            }
        }
    }

    private func copy(_ englishText: String, _ original: String) -> String {
        english ? englishText : original
    }

    @ViewBuilder private var comparisonToggles: some View {
        if category == .race || category == .qualifying {
            Toggle(copy("Include Sprint Sessions", "合并冲刺场次"), isOn: $combineSprint)
        }
        Toggle(copy("Classified Results Only", "仅比较已分类成绩"), isOn: $excludeRetirements)
    }

    private func resetChartSelections() {
        selectedFinish = nil
        selectedQualifyingRound = nil
        selectedQualifyingGap = nil
    }

    private func driverIdentity(_ id: String, marker: String, color: Color) -> some View {
        let driver = model.driverRoster.first { $0.id == id }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let driver {
                    AssetImage(name: StandingEntry(driver: driver).asset).frame(width: 42, height: 35)
                }
                Spacer(minLength: 0)
                Image(systemName: marker).font(.caption2).foregroundStyle(color).accessibilityHidden(true)
            }
            if typeSize.isAccessibilitySize {
                Text(name(id)).font(.subheadline.weight(.semibold))
            } else {
                Text(name(id)).font(.subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)
            }
            if let driver {
                Text(driver.seasonTeamName).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.09), in: PulseStyle.insetShape)
        .accessibilityElement(children: .combine)
    }

    private func comparisonCard<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        comparisonCard(title, trailing: { EmptyView() }, content: content)
    }

    @ViewBuilder private func comparisonCard<Content: View, Trailing: View>(
        _ title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content
    ) -> some View {
        if english {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    trailing()
                }
                content()
            }
            .padding(14)
            .dashboardPanel(WebDashboardStyle.homePanel)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            Section {
                content()
            } header: {
                HStack {
                    Text(title)
                    Spacer(minLength: 0)
                    trailing()
                }
            }
            .listRowBackground(PulseStyle.surface)
        }
    }

    private var comparisonCategoriesForPicker: [(SessionType, String)] {
        [.race, .sprint, .qualifying, .sprintQualifying].map { ($0, english ? $0.resultLabel : $0.displayName) }
    }

    private func finishTrend(_ pairs: [ComparisonRound]) -> some View {
        let rounds = pairs.sorted { $0.start < $1.start }
        let selectedIndex = selectedFinish.flatMap { rounds.indices.contains($0) ? $0 : nil } ?? rounds.indices.last
        let lastPosition = max(1, rounds.flatMap { [$0.first, $0.second].compactMap { $0 } }.max() ?? 1)
        return comparisonCard(copy("Results by Round", "逐站成绩走势")) {
            if let index = selectedIndex {
                let result = rounds[index]
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.meeting).font(.headline)
                    HStack(alignment: .top) {
                        Label("\(name(first)) · \(result.firstLabel)", systemImage: "circle.fill").foregroundStyle(.teal)
                        Spacer(minLength: 12)
                        Label("\(name(second)) · \(result.secondLabel)", systemImage: "diamond.fill").foregroundStyle(.indigo)
                    }.font(.caption.weight(.semibold))
                    Chart {
                        RuleMark(x: .value(copy("Session", "场次"), index)).foregroundStyle(.secondary.opacity(0.35))
                        ForEach(Array(rounds.enumerated()), id: \.element.id) { slot, round in
                            if let position = round.first {
                                PointMark(x: .value(copy("Session", "场次"), slot), y: .value(copy("Position", "名次"), -position))
                                    .foregroundStyle(Color.teal).symbol(.circle)
                            }
                            if let position = round.second {
                                PointMark(x: .value(copy("Session", "场次"), slot), y: .value(copy("Position", "名次"), -position))
                                    .foregroundStyle(Color.indigo).symbol(.diamond)
                            }
                        }
                    }
                    .chartXScale(domain: -0.5...(Double(rounds.count) - 0.5))
                    .chartYScale(domain: (-Double(lastPosition) - 0.5)...(-0.5))
                    .chartXSelection(value: $selectedFinish)
                    .chartXAxis {
                        AxisMarks(values: Array(stride(from: 0, to: rounds.count, by: max(1, (rounds.count + 4) / 5)))) { value in
                            AxisTick()
                            if let slot = value.as(Int.self), let round = rounds[slot].round {
                                AxisValueLabel("R\(round)")
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: Array(stride(from: -1, through: -lastPosition, by: -max(1, lastPosition / 5)))) { value in
                            AxisGridLine()
                            if let position = value.as(Int.self) { AxisValueLabel("P\(-position)") }
                        }
                    }
                    .frame(height: 204)
                    .pulseChart()
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: selectedFinish = min(index + 1, rounds.count - 1)
                        case .decrement: selectedFinish = max(index - 1, 0)
                        @unknown default: break
                        }
                    }
                }.padding(.vertical, 8)
            }
        }
    }

    private func finishCounts(_ positions: [Int], driver: String) -> [FinishCount] {
        Dictionary(grouping: positions, by: { $0 }).map { position, finishes in
            FinishCount(position: position, count: finishes.count, driver: driver)
        }.sorted { $0.position < $1.position }
    }

    private struct FinishCount: Identifiable {
        let position: Int
        let count: Int
        let driver: String
        var id: String { "\(driver)-\(position)" }
    }

    private func name(_ id: String) -> String {
        if let driver = model.driverRoster.first(where: { $0.id == id }) { return driver.driverName }
        for weekend in (model.seasonArchive?.data ?? []).reversed() {
            for session in weekend.sessions.values {
                if let row = session.rows.first(where: { $0.id == id }) { return row.driverName }
            }
        }
        return id
    }

    private func picker(_ title: String, selection: Binding<String>, excluding: String) -> some View {
        Picker(title, selection: selection) {
            Text(copy("Select Driver", "选择车手")).tag("")
            ForEach(model.driverRoster.filter { $0.id != excluding }) { driver in
                Text(driver.driverName).tag(driver.id)
            }
        }
    }

    private var comparisonCategories: [SessionType] {
        comparisonSessionTypes(category, includingSprint: combineSprint)
    }

    private func comparisons(in weekends: [SeasonResultWeekend]) -> [ComparisonRound] {
        let categories = comparisonCategories
        return weekends.flatMap { weekend in
            categories.compactMap { type in
                guard let rows = weekend.sessions[type.rawValue]?.rows,
                      let firstRow = rows.first(where: { $0.driverId == first }),
                      let secondRow = rows.first(where: { $0.driverId == second }),
                      teammateTeamID.map({ team in
                          MobileModel.normalizedConstructorID(firstRow.constructorId) == MobileModel.normalizedConstructorID(team)
                              && MobileModel.normalizedConstructorID(secondRow.constructorId) == MobileModel.normalizedConstructorID(team)
                      }) ?? true,
                      let winner = comparisonWinner(firstRow, secondRow, onlyClassified: excludeRetirements) else { return nil }
                return ComparisonRound(id: "\(weekend.id)-\(type.rawValue)",
                                       meeting: categories.count == 1 ? weekend.meeting.name : "\(weekend.meeting.name) · \(english ? type.resultLabel : type.displayName)",
                                       round: weekend.meeting.round, type: type,
                                       start: weekend.meeting.sessions.first { $0.sessionType == type }?.startTime ?? weekend.meeting.startDate,
                                       left: firstRow, right: secondRow, winner: winner)
            }
        }
    }

    @ViewBuilder private func championship(_ weekends: [SeasonResultWeekend]) -> some View {
        let series = [first, second].flatMap { driver -> [ChampionshipPoint] in
            var total = 0.0
            var available = true
            return weekends.compactMap { weekend in
                guard available, let round = weekend.meeting.round,
                      weekend.sessions["race"]?.rows.isEmpty == false else { return nil }
                let rows = ["race", "sprint"].flatMap { weekend.sessions[$0]?.rows ?? [] }.filter { $0.driverId == driver }
                if rows.contains(where: { $0.points == nil }) {
                    available = false
                    return nil
                }
                total += rows.compactMap(\.points).reduce(0, +)
                return ChampionshipPoint(driver: driver, round: round, points: total)
            }
        }
        if !series.isEmpty {
            comparisonCard(copy("Championship Points", "锦标赛积分走势")) {
                Chart(series) { item in
                    LineMark(x: .value(copy("Round", "轮次"), item.round), y: .value(copy("Points", "积分"), item.points),
                             series: .value(copy("Driver", "车手"), item.driver))
                        .foregroundStyle(by: .value(copy("Driver", "车手"), name(item.driver)))
                }
                .chartForegroundStyleScale(domain: [name(first), name(second)], range: [Color.teal, Color.indigo])
                .frame(height: 165)
                .pulseChart()
            }
        }
    }

    private struct ChampionshipPoint: Identifiable {
        let driver: String
        let round: Int
        let points: Double
        var id: String { "\(driver)-\(round)" }
    }

    @ViewBuilder private func qualifyingGaps(_ pairs: [ComparisonRound]) -> some View {
        let dots = pairs.flatMap { pair -> [QualifyingGap] in
            guard let round = pair.round else { return [] }
            let lhs = [pair.left.q1, pair.left.q2, pair.left.q3]
            let rhs = [pair.right.q1, pair.right.q2, pair.right.q3]
            let prefix = pair.type == .sprintQualifying ? "SQ" : "Q"
            let phases = (0..<3).compactMap { i -> QualifyingGap? in
                guard let a = AnalysisMath.elapsedSeconds(lhs[i]), let b = AnalysisMath.elapsedSeconds(rhs[i]) else { return nil }
                return QualifyingGap(id: "\(pair.id)-\(i)", round: round, phase: "\(prefix)\(i + 1)", start: pair.start, seconds: a - b)
            }
            if lhs.allSatisfy({ $0 == nil }), rhs.allSatisfy({ $0 == nil }),
               let left = AnalysisMath.elapsedSeconds(pair.left.bestLap), let right = AnalysisMath.elapsedSeconds(pair.right.bestLap) {
                return [QualifyingGap(id: pair.id, round: round, phase: "\(prefix) \(copy("Best Lap", "最快圈"))", start: pair.start, seconds: left - right)]
            }
            return phases
        }
        if !dots.isEmpty {
            comparisonCard(copy("Qualifying Phase Gaps", "排位分段差距"), trailing: {
                Button {
                    highlightLatestQualifying.toggle()
                } label: {
                    Label(copy("Highlight Latest Session", "突出最近一场"),
                          systemImage: highlightLatestQualifying ? "clock.badge.checkmark.fill" : "clock")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(highlightLatestQualifying ? PulseStyle.red : Color.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(highlightLatestQualifying ? .isSelected : [])
                .accessibilityIdentifier("comparison.highlightLatestQualifying")
            }) {
                PulseSectionPicker(
                    sections: [(false, copy("By Round", "逐站")), (true, copy("Distribution", "差距分布"))],
                    selection: $showQualifyingDistribution
                )
                if showQualifyingDistribution {
                    qualifyingDistribution(dots)
                } else {
                    let latest = dots.map(\.start).max()
                    Chart {
                        RuleMark(y: .value(copy("Equal", "持平"), 0)).foregroundStyle(.secondary)
                        ForEach(dots) { dot in
                            PointMark(x: .value(copy("Round", "轮次"), dot.round), y: .value(copy("Seconds", "秒"), dot.seconds))
                                .foregroundStyle(by: .value(copy("Phase", "分段"), dot.phase))
                                .opacity(!highlightLatestQualifying || dot.start == latest ? 1 : 0.24)
                        }
                        if let selectedQualifyingRound {
                            RuleMark(x: .value(copy("Selected Round", "选中轮次"), selectedQualifyingRound))
                                .foregroundStyle(.secondary.opacity(0.65))
                        }
                    }
                    .chartXSelection(value: $selectedQualifyingRound)
                    .frame(height: 150)
                    .pulseChart()
                    if let selectedQualifyingRound {
                        let active = dots.filter { $0.round == selectedQualifyingRound }
                        if !active.isEmpty {
                            LabeledContent("R\(selectedQualifyingRound)", value: active.map {
                                "\($0.phase) \($0.seconds.formatted(.number.sign(strategy: .always()).precision(.fractionLength(3)))) s"
                            }.joined(separator: " · ")).font(.caption.monospacedDigit())
                        }
                    }
                }
                Text(copy("Gaps compare the same qualifying phase. Negative values favor \(name(first)).",
                          "同一轮次的同一分段相减。负值代表车手 1 更快。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func qualifyingDistribution(_ dots: [QualifyingGap]) -> some View {
        let latest = dots.map(\.start).max()
        let mean = dots.reduce(0.0) { $0 + $1.seconds } / Double(dots.count)
        return VStack(alignment: .leading, spacing: 9) {
            LabeledContent(copy("Average Gap", "平均差距")) {
                PulseNumber(signedSeconds(mean))
            }.font(.subheadline.monospacedDigit())
            Chart {
                RuleMark(x: .value(copy("Equal", "持平"), 0.0)).foregroundStyle(.secondary)
                RuleMark(x: .value(copy("Average", "平均"), mean))
                    .foregroundStyle(PulseStyle.red.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(dots) { dot in
                    PointMark(x: .value(copy("Gap", "秒差"), dot.seconds), y: .value(copy("Phase", "分段"), dot.phase))
                        .foregroundStyle(by: .value(copy("Phase", "分段"), dot.phase))
                        .opacity(!highlightLatestQualifying || dot.start == latest ? 1 : 0.24)
                        .accessibilityLabel("R\(dot.round) · \(dot.phase)")
                        .accessibilityValue(signedSeconds(dot.seconds))
                }
                if let selectedQualifyingGap {
                    RuleMark(x: .value(copy("Selected Gap", "选中秒差"), selectedQualifyingGap)).foregroundStyle(.secondary.opacity(0.6))
                }
            }
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedQualifyingGap)
            .frame(height: max(130, CGFloat(Set(dots.map(\.phase)).count) * 27))
            .pulseChart()
            if let selection = selectedQualifyingGap,
               let closest = dots.min(by: { abs($0.seconds - selection) < abs($1.seconds - selection) }) {
                LabeledContent("R\(closest.round) · \(closest.phase)", value: signedSeconds(closest.seconds))
                    .font(.caption.monospacedDigit())
            }
        }
    }

    private func signedSeconds(_ value: Double) -> String {
        value.formatted(.number.sign(strategy: .always()).precision(.fractionLength(3))) + " s"
    }

}

private struct TeamPoleTrend: View {
    let weekends: [SeasonResultWeekend]
    let teamIDs: Set<String>
    let types: [SessionType]
    var constructorPositions: [String: Int] = [:]
    var tabletWebLayout = false
    @Environment(\.pulseEnglishPresentation) private var english
    @State private var selectedPoleSession: Int?

    var body: some View {
        let sessions = weekends.sorted { $0.meeting.startDate < $1.meeting.startDate }.flatMap { weekend in
            weekend.meeting.sessions.filter { types.contains($0.sessionType) }
                .sorted { $0.startTime < $1.startTime }
                .compactMap { session -> (label: String, rows: [SessionResult])? in
                    guard let rows = weekend.sessions[session.sessionType.rawValue]?.rows, !rows.isEmpty else { return nil }
                    let round = weekend.meeting.round.map { "R\($0)" } ?? weekend.meeting.country
                    let suffix = session.sessionType == .sprintQualifying ? " SQ" : ""
                    return (round + suffix, rows)
                }
        }
        let phases: [(String, KeyPath<SessionResult, String?>)] = [
            ("3", \.q3), ("2", \.q2), ("1", \.q1), ("最快圈", \.bestLap)
        ]
        let orderedTeams = teamIDs.sorted {
            let left = MobileModel.normalizedConstructorID($0)
            let right = MobileModel.normalizedConstructorID($1)
            return (constructorPositions[left] ?? .max, $0) < (constructorPositions[right] ?? .max, $1)
        }
        let points = orderedTeams.flatMap { team -> [TeamPolePoint] in
            var run = 0
            return sessions.enumerated().compactMap { index, session in
                guard let pole = session.rows.first(where: {
                    $0.position == 1 && (tabletWebLayout || $0.classification.uppercased() == "CLASSIFIED")
                }),
                      let timing = phases.first(where: { AnalysisMath.elapsedSeconds(pole[keyPath: $0.1]) != nil }),
                      let poleTime = AnalysisMath.elapsedSeconds(pole[keyPath: timing.1]) else {
                    run += 1
                    return nil
                }
                let teamRows = session.rows.filter {
                    MobileModel.normalizedConstructorID($0.constructorId) == MobileModel.normalizedConstructorID(team)
                        && (tabletWebLayout || $0.classification.uppercased() == "CLASSIFIED")
                }
                guard let sample = teamRows.compactMap({ row in
                    AnalysisMath.elapsedSeconds(row[keyPath: timing.1]).map { (row, $0) }
                }).min(by: { $0.1 < $1.1 }), sample.1 >= poleTime else {
                    run += 1
                    return nil
                }
                let prefix = session.label.hasSuffix(" SQ") ? "SQ" : "Q"
                let phase = timing.0 == "最快圈" ? (english ? "Best Lap" : timing.0) : prefix + timing.0
                return TeamPolePoint(index: index, run: run, teamID: team, name: sample.0.team,
                                     driver: sample.0.driverName, phase: phase, gap: sample.1 - poleTime)
            }
        }
        let poleAxisMaximum = max(1, ceil(points.map(\.gap).max() ?? 0))
        VStack(alignment: .leading, spacing: 8) {
            if points.isEmpty {
                if tabletWebLayout {
                    Text("No pole comparison lap times are available.")
                        .font(.subheadline).foregroundStyle(WebDashboardStyle.homeMuted)
                } else {
                    ContentUnavailableView(english ? "No Matching Lap Times" : "暂无同阶段圈速可对照", systemImage: "timer")
                }
            } else {
                let legend = orderedTeams.compactMap { team in points.first { $0.teamID == team } }
                let chart = Chart {
                    ForEach(points) { point in
                        LineMark(x: .value(english ? "Session" : "场次", point.index), y: .value(english ? "Gap to Pole" : "距杆位秒差", point.gap),
                                 series: .value(english ? "Consecutive Sessions" : "连续场次", "\(point.teamID)-\(point.run)"))
                            .foregroundStyle(by: .value(english ? "Team" : "车队", point.name))
                        PointMark(x: .value(english ? "Session" : "场次", point.index), y: .value(english ? "Gap to Pole" : "距杆位秒差", point.gap))
                            .foregroundStyle(by: .value(english ? "Team" : "车队", point.name))
                            .symbolSize(20)
                    }
                    if let selectedPoleSession, sessions.indices.contains(selectedPoleSession) {
                        RuleMark(x: .value(english ? "Selected Session" : "选中场次", selectedPoleSession))
                            .foregroundStyle(.secondary.opacity(0.58))
                    }
                }
                .chartForegroundStyleScale(domain: legend.map(\.name), range: legend.map { tabletWebLayout ? WebDashboardStyle.chartTeamColor($0.teamID) : DashboardArt.teamColor($0.teamID) })
                .chartXScale(domain: 0...max(1, sessions.count - 1))
                poleAxes(chart, labels: sessions.map(\.label), maximum: poleAxisMaximum)
                .chartXSelection(value: $selectedPoleSession)
                .frame(height: 180)
                .pulseChart()
                if let selectedPoleSession, sessions.indices.contains(selectedPoleSession) {
                    ForEach(points.filter { $0.index == selectedPoleSession }) { point in
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(point.name) {
                                PulseNumber(point.gap.formatted(.number.precision(.fractionLength(3))) + " s")
                            }
                                .font(.subheadline.monospacedDigit())
                            Text("\(sessions[selectedPoleSession].label) · \(point.driver) · \(point.phase)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onChange(of: types) { selectedPoleSession = nil }
        .onChange(of: teamIDs) { selectedPoleSession = nil }
    }

    @ViewBuilder
    private func poleAxes(_ chart: some View, labels: [String], maximum: Double) -> some View {
        if tabletWebLayout {
            chart.chartYScale(domain: 0...maximum)
                .chartXAxis {
                    AxisMarks(values: Array(labels.indices)) { value in
                        if let index = value.as(Int.self), labels.indices.contains(index) {
                            AxisValueLabel {
                                Text(labels[index].replacingOccurrences(of: " SQ", with: " (SQ)"))
                                    .font(.system(size: 9))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: (0...6).map { maximum * Double($0) / 6 }) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.13))
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(seconds == 0 ? "0" : "+\(seconds.formatted(.number.precision(.fractionLength(1))))s")
                            }
                        }
                    }
                }
        } else {
            let ticks = Array(stride(from: 0, to: labels.count, by: max(1, (labels.count + 4) / 5)))
            chart.chartXAxis {
                AxisMarks(values: ticks) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                    if let index = value.as(Int.self), labels.indices.contains(index) {
                        AxisValueLabel(labels[index])
                    }
                }
            }
        }
    }

    private struct TeamPolePoint: Identifiable {
        let index: Int
        let run: Int
        let teamID: String
        let name: String
        let driver: String
        let phase: String
        let gap: Double
        var id: String { "\(teamID)-\(index)" }
    }

}

private extension DriverComparison {
    @ViewBuilder func poles(_ weekends: [SeasonResultWeekend]) -> some View {
        let keys = category == .sprintQualifying ? ["sprintQualifying"]
            : combineSprint ? ["qualifying", "sprintQualifying"] : ["qualifying"]
        let leaders = weekends.flatMap { weekend in
            keys.compactMap { key in
                weekend.sessions[key]?.rows.first { $0.position == 1 && $0.classification.uppercased() == "CLASSIFIED" }
            }
        }
        let groups = Dictionary(grouping: leaders, by: \.constructorId)
        let labels = groups.keys.sorted {
            let left = groups[$0]?.count ?? 0, right = groups[$1]?.count ?? 0
            return left == right ? $0 < $1 : left > right
        }
        if !labels.isEmpty {
            comparisonCard(copy("Pole Positions by Team", "车队杆位分布")) {
                Chart(labels, id: \.self) { identifier in
                    if let group = groups[identifier], let title = group.first?.team {
                        let counts = Dictionary(grouping: group, by: \.driverId)
                        ForEach(counts.keys.sorted(), id: \.self) { driver in
                            BarMark(x: .value(copy("Poles", "杆位"), counts[driver]?.count ?? 0), y: .value(copy("Team", "车队"), title))
                                .foregroundStyle(by: .value(copy("Driver", "车手"), counts[driver]?.first?.driverName ?? driver))
                        }
                    }
                }
                .chartLegend(.hidden)
                .frame(height: CGFloat(labels.count) * 27 + 30)
                .pulseChart()
            }
        }
    }

    private struct QualifyingGap: Identifiable {
        let id: String
        let round: Int
        let phase: String
        let start: Date
        let seconds: Double
    }

    private struct ComparisonRound: Identifiable {
        let id: String
        let meeting: String
        let round: Int?
        let type: SessionType
        let start: Date
        let left: SessionResult
        let right: SessionResult
        let winner: Int
        var first: Int? { left.position.flatMap { $0 > 0 ? $0 : nil } }
        var second: Int? { right.position.flatMap { $0 > 0 ? $0 : nil } }
        var firstLabel: String { first.map { "P\($0)" } ?? left.classificationLabel }
        var secondLabel: String { second.map { "P\($0)" } ?? right.classificationLabel }
    }
}

private func comparisonWinner(_ a: SessionResult, _ b: SessionResult, onlyClassified: Bool) -> Int? {
    let aFinished = a.classification.uppercased() == "CLASSIFIED"
    let bFinished = b.classification.uppercased() == "CLASSIFIED"
    if onlyClassified && (!aFinished || !bFinished) { return nil }
    if let first = a.position, let second = b.position, first > 0, second > 0 {
        return first == second ? 0 : (first < second ? 1 : -1)
    }
    let retirements = ["DNF", "DNS", "DSQ", "NC"]
    if aFinished, a.position != nil, retirements.contains(b.classification.uppercased()) { return 1 }
    if bFinished, b.position != nil, retirements.contains(a.classification.uppercased()) { return -1 }
    return nil
}


private func comparisonSessionTypes(_ category: SessionType, includingSprint: Bool) -> [SessionType] {
    switch category {
    case .race where includingSprint: [.race, .sprint]
    case .qualifying where includingSprint: [.qualifying, .sprintQualifying]
    default: [category]
    }
}

struct TeammateComparisonBoard: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var team: String?
    @State private var first = ""
    @State private var second = ""
    @State private var showCustom = false
    @State private var customMatchup: PairID?
    @State private var pendingMatchup: PairID?
    @State private var pickingFirst = true
    @State private var searchText = ""
    @State private var qualifyingMode = Mode.combined
    @State private var raceMode = Mode.combined
    @State private var gapMode = Mode.combined
    @State private var poleMode = Mode.combined
    @State private var highlightLatest = false
    @State private var selectedGap: [PairID: Double] = [:]
    @State private var tappedGapPoint: GapPointSelection?
    @State private var hoveredGapPoint: GapPointSelection?
    @State private var constructorPositions: [String: Int] = [:]
    @State private var matchupScroll = ScrollPosition(edge: .leading)
    @State private var nextMatchupOffset: CGFloat?

    private let tabletWebLayout: Bool

    init(initialDriver: String? = nil, teammate: String? = nil, tabletWebLayout: Bool = false) {
        self.tabletWebLayout = tabletWebLayout
        if let initialDriver {
            _first = State(initialValue: initialDriver)
            _second = State(initialValue: teammate ?? "")
            _showCustom = State(initialValue: !tabletWebLayout)
            if let teammate, !tabletWebLayout {
                _customMatchup = State(initialValue: PairID(team: "", left: initialDriver, right: teammate))
            }
        }
    }

    private enum Mode: Hashable {
        case combined, regular, sprint

        func types(for category: SessionType) -> [SessionType] {
            let sprintType: SessionType = category == .race ? .sprint : .sprintQualifying
            return switch self {
            case .combined: [category, sprintType]
            case .regular: [category]
            case .sprint: [sprintType]
            }
        }
    }

    private struct MatchupDriver: Identifiable {
        let id: String
        let name: String
        let teamID: String
        let team: String
        let number: String?
        let rank: Int
    }

    private struct PairID: Hashable, Identifiable {
        let team: String
        let left: String
        let right: String
        var id: Self { self }
    }

    private struct Pair: Identifiable {
        let id: PairID
        let left: String
        let right: String
        let leftTeamID: String
        let rightTeamID: String
        var wins = 0
        var losses = 0
        var ties = 0

        var total: Int { wins + losses + ties }

        mutating func record(_ outcome: Int) {
            if outcome > 0 { wins += 1 }
            else if outcome < 0 { losses += 1 }
            else { ties += 1 }
        }
    }

    private var teams: [(key: String, value: String)] {
        let drivers = tabletWebLayout ? tabletDrivers : currentLineup
        return Dictionary(drivers.map { ($0.teamID, $0.team) }, uniquingKeysWith: { name, _ in name })
            .sorted { ($0.value, $0.key) < ($1.value, $1.key) }
    }

    private var currentLineup: [MatchupDriver] {
        let archive = model.seasonArchive?.data ?? []
        let now = Date.now
        let meetings = model.meetings.isEmpty ? archive.map(\.meeting) : model.meetings
        guard let meeting = meetings.filter({ $0.status == .scheduled && $0.startDate <= now })
            .max(by: { $0.startDate < $1.startDate }) else { return [] }
        let weekend = archive.first { $0.id == meeting.id }
        let recent = meeting.sessions.sorted { $0.startTime > $1.startTime }.first { session in
            session.startTime <= now && session.status != .cancelled && session.status != .postponed
                && weekend?.sessions[session.sessionType.rawValue]?.rows.contains {
                    $0.classification.uppercased() != "DNS"
                } == true
        }
        let standings = Dictionary(model.driverRoster.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recentRows = recent.flatMap { weekend?.sessions[$0.sessionType.rawValue]?.rows } ?? []
        let knownDrivers = customDrivers.map { FavoriteDriver(id: $0.id, name: $0.name) }
        if let timing = model.liveSnapshots[.f1], timing.sourceMode == .live,
           timing.sourceStatus != .disconnected, model.season == meeting.season,
           timing.meetingName.map(LiveIslandLogic.normalizedName) == LiveIslandLogic.normalizedName(meeting.name),
           let label = timing.sessionType ?? timing.sessionName,
           let session = meeting.sessions.filter({ $0.startTime <= now && LiveIslandLogic.sessionTypeMatches(label, $0.sessionType) })
            .max(by: { $0.startTime < $1.startTime }),
           (recent.map { session.startTime >= $0.startTime } ?? true),
           (LiveIslandLogic.isActive(timing.sessionStatus) || LiveIslandLogic.isFinished(timing.sessionStatus)) {
            let live = timing.drivers.compactMap { driver -> MatchupDriver? in
                guard let id = LiveIslandLogic.rosterID(for: driver, favorites: knownDrivers),
                      let name = driver.name, let team = driver.team,
                      let teamID = LiveIslandLogic.teamAssetID(for: driver, isWec: false) else { return nil }
                return MatchupDriver(id: id, name: name, teamID: teamID, team: team, number: driver.number,
                                     rank: standings[id]?.position ?? .max)
            }
            if !live.isEmpty { return live }
        }
        return recentRows.filter { $0.classification.uppercased() != "DNS" && !$0.constructorId.isEmpty }.map { row in
            MatchupDriver(id: row.id, name: row.driverName, teamID: MobileModel.normalizedConstructorID(row.constructorId),
                          team: row.team, number: row.driverNumber, rank: standings[row.id]?.position ?? .max)
        }
    }

    private var customDrivers: [MatchupDriver] {
        var drivers: [String: MatchupDriver] = [:]
        for weekend in (model.seasonArchive?.data ?? []).sorted(by: { $0.meeting.startDate > $1.meeting.startDate }) {
            for session in weekend.meeting.sessions.sorted(by: { $0.startTime > $1.startTime }) {
                for row in weekend.sessions[session.sessionType.rawValue]?.rows ?? [] where drivers[row.id] == nil {
                    drivers[row.id] = MatchupDriver(id: row.id, name: row.driverName,
                        teamID: MobileModel.normalizedConstructorID(row.constructorId),
                        team: row.team, number: row.driverNumber, rank: .max)
                }
            }
        }
        for driver in model.driverRoster {
            drivers[driver.id] = MatchupDriver(id: driver.id, name: driver.driverName, teamID: driver.seasonTeamID,
                team: driver.seasonTeamName, number: driver.driverNumber, rank: driver.position)
        }
        return drivers.values.sorted { ($0.rank, $0.name, $0.id) < ($1.rank, $1.name, $1.id) }
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    popularComparisons
                    if tabletWebLayout, let left = tabletDrivers.first(where: { $0.id == first }),
                       let right = tabletDrivers.first(where: { $0.id == second }) {
                        let standings = model.driverRoster.filter { $0.season == model.season }
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(left.name)  vs  \(right.name)").bold()
                                let scores = [left, right].compactMap { driver in
                                    standings.first { $0.id == driver.id }.map { "\($0.points.formatted()) pts · P\($0.position)" }
                                }
                                Text(scores.joined(separator: "   /   ")).font(.caption).foregroundStyle(WebDashboardStyle.homeMuted)
                            }
                            Spacer()
                            Button("Show all comparisons", action: resetFilters)
                                .buttonStyle(.plain)
                        }
                        .padding(14)
                        .dashboardPanel(WebDashboardStyle.homePanel)
                    }
                    Group {
                        if let archive = model.seasonArchive {
                            if archive.meta.stale {
                                Label("Season results may be out of date", systemImage: "clock.arrow.circlepath")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            let layout = viewport.size.width >= 840 && !typeSize.isAccessibilitySize
                                ? AnyLayout(HStackLayout(alignment: .top, spacing: 14))
                                : AnyLayout(VStackLayout(spacing: 14))
                            layout {
                                comparisonCard(.qualifying, mode: $qualifyingMode)
                                comparisonCard(.race, mode: $raceMode)
                            }
                            qualifyingGapCard(archive.data)
                            poleCard(archive.data)
                        } else if let error = model.seasonArchiveError {
                            analysisCard("Season Results") {
                                Text(error.pulseEnglishError).foregroundStyle(.secondary)
                                Button("Retry") { Task { await model.loadSeasonArchive(force: true) } }
                                    .buttonStyle(.bordered)
                            }
                        } else {
                            PulseSkeleton(rows: 5, label: "Loading head-to-head results")
                        }
                    }
                    .pulseSwap(model.seasonArchive != nil)
                }
                .padding(16)
            }
        }
        .onChange(of: first) { resetGapSelection() }
        .onChange(of: second) { resetGapSelection() }
        .onChange(of: team) { resetGapSelection() }
        .foregroundStyle(WebDashboardStyle.homeText)
        .background(WebDashboardStyle.homeBackground)
        .onChange(of: model.dataContext) {
            resetFilters()
            constructorPositions = [:]
        }
        .task(id: model.dataContext) { await loadStandingsAndArchive() }
        .refreshable { await loadStandingsAndArchive(force: true) }
        .sheet(isPresented: $showCustom, onDismiss: {
            searchText = ""
            if let pendingMatchup {
                customMatchup = pendingMatchup
                self.pendingMatchup = nil
            }
        }) {
            customSheet
        }
        .navigationDestination(item: $customMatchup) { pair in
            DriverComparison(firstDriverID: pair.left, secondDriverID: pair.right, combineSprint: true)
                .navigationTitle("Driver Comparison").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func loadStandingsAndArchive(force: Bool = false) async {
        let context = model.dataContext
        async let archive: Void = model.loadSeasonArchive(force: force)
        async let roster: Void = model.loadF1Roster(force: force)
        if let url = model.serverURL,
           let standings = try? await APIClient(baseURL: url)
               .constructorStandings(season: model.season, token: model.currentToken),
           model.dataContext == context, !Task.isCancelled {
            constructorPositions = Dictionary(standings.data.map {
                (MobileModel.normalizedConstructorID($0.id), $0.position)
            }, uniquingKeysWith: min)
        }
        _ = await (archive, roster)
    }

    private var customSheet: some View {
        let selected = pickingFirst ? first : second
        let excluded = pickingFirst ? second : first
        let options = customDrivers.filter {
            $0.id != excluded && (searchText.isEmpty || $0.name.localizedStandardContains(searchText)
                || $0.team.localizedStandardContains(searchText)
                || $0.number.map { "#\($0)".localizedStandardContains(searchText) } == true)
        }
        return NavigationStack {
            List {
                Section {
                    let slots = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: 8))
                        : AnyLayout(HStackLayout(spacing: 8))
                    slots {
                        matchupSlot(firstSlot: true)
                        matchupSlot(firstSlot: false)
                    }
                }
                ForEach(options) { driver in
                    Button {
                        if pickingFirst {
                            first = driver.id
                            pickingFirst = false
                        } else {
                            second = driver.id
                        }
                    } label: {
                        HStack(spacing: 10) {
                            AssetImage(name: MotorsportAssetName.helmetName(
                                driverID: driver.id, name: driver.name, season: model.season
                            )).frame(width: 38, height: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(driver.name).font(.subheadline.weight(.semibold))
                                Text(driver.number.map { "#\($0) · \(driver.team)" } ?? driver.team)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selected == driver.id {
                                Image(systemName: "checkmark").foregroundStyle(PulseStyle.red)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == driver.id ? .isSelected : [])
                }
            }
            .overlay {
                if options.isEmpty, !searchText.isEmpty { ContentUnavailableView.search(text: searchText) }
                else if customDrivers.isEmpty { ContentUnavailableView("No Drivers Available", systemImage: "person.2") }
            }
            .searchable(text: $searchText, prompt: "Driver, number or team")
            .navigationTitle("Custom Matchup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { showCustom = false }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Compare") {
                        pendingMatchup = PairID(team: "", left: first, right: second)
                        showCustom = false
                    }.disabled(first.isEmpty || second.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func matchupSlot(firstSlot: Bool) -> some View {
        let id = firstSlot ? first : second
        let active = pickingFirst == firstSlot
        return Button {
            pickingFirst = firstSlot
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(firstSlot ? "Driver 1" : "Driver 2").font(.caption).foregroundStyle(.secondary)
                Text(customDrivers.first { $0.id == id }?.name ?? "Select Driver")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .background(active ? PulseStyle.red.opacity(0.12) : Color.secondary.opacity(0.06),
                        in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func resetFilters() {
        team = nil
        first = ""
        second = ""
        pendingMatchup = nil
        resetGapSelection()
    }

    private func resetGapSelection() {
        selectedGap = [:]
        tappedGapPoint = nil
        hoveredGapPoint = nil
    }

    private var tabletDrivers: [MatchupDriver] {
        model.driverRoster.filter { $0.season == model.season }.map { driver in
            MatchupDriver(id: driver.id, name: driver.driverName, teamID: driver.seasonTeamID,
                          team: driver.seasonTeamName, number: driver.driverNumber, rank: driver.position)
        }.sorted { ($0.rank, $0.id) < ($1.rank, $1.id) }
    }

    private var popularComparisons: some View {
        let teams = teams
        let currentTeam = team.flatMap { id in teams.first { $0.key == id } }
        let groups = Dictionary(grouping: currentLineup, by: \.teamID)
        let pairs = tabletWebLayout ? tabletPopularPairs : groups.filter { currentTeam == nil || currentTeam?.key == $0.key }
            .compactMap { team, drivers -> (team: String, first: MatchupDriver, second: MatchupDriver)? in
                let ranked = drivers.sorted { ($0.rank, $0.id) < ($1.rank, $1.id) }
                guard ranked.count >= 2 else { return nil }
                return (team, ranked[0], ranked[1])
            }.sorted { ($0.first.rank, $0.first.teamID) < ($1.first.rank, $1.first.teamID) }

        return VStack(alignment: .leading, spacing: 8) {
            if tabletWebLayout {
                HStack {
                    Text("Popular Driver Comparisons").font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if let nextMatchupOffset {
                        Button {
                            withAnimation(.smooth) { matchupScroll.scrollTo(x: nextMatchupOffset) }
                        } label: {
                            Image(systemName: "chevron.right").frame(width: 32, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show more comparisons")
                    }
                }
            } else {
                HStack {
                    Text("Teammate Matchups").font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button {
                        pickingFirst = first.isEmpty || !second.isEmpty
                        showCustom = true
                    } label: {
                        Label("Custom Matchup", systemImage: "person.2.badge.plus")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.glass)
                }
                Menu {
                    Picker("Team", selection: $team) {
                        Text("All Teams").tag(String?.none)
                        ForEach(teams, id: \.key) { entry in
                            Text(entry.value).tag(Optional(entry.key))
                        }
                    }
                } label: {
                    Label(currentTeam?.value ?? "All Teams", systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline.weight(.medium))
                }
            }
            if pairs.isEmpty {
                if model.seasonArchive == nil, model.seasonArchiveError == nil {
                    PulseSkeleton(rows: 2, label: "Loading weekend lineup")
                } else {
                    Text("No teammate lineup available for this weekend.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(pairs, id: \.team) { pair in
                            Group {
                                if tabletWebLayout {
                                    Button {
                                        team = nil
                                        first = pair.first.id
                                        second = pair.second.id
                                    } label: {
                                        matchupCard(pair.first, pair.second)
                                    }
                                } else {
                                    NavigationLink {
                                        DriverComparison(firstDriverID: pair.first.id, secondDriverID: pair.second.id,
                                                         teammateTeamID: pair.first.teamID, combineSprint: true)
                                            .navigationTitle("Driver Comparison").navigationBarTitleDisplayMode(.inline)
                                    } label: {
                                        matchupCard(pair.first, pair.second)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Compare \(pair.first.name) and \(pair.second.name)")
                        }
                    }.scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition($matchupScroll)
                .onScrollGeometryChange(for: CGFloat?.self) { geometry in
                    let maximum = max(0, geometry.contentSize.width - geometry.containerSize.width)
                    let current = max(0, geometry.contentOffset.x)
                    return current < maximum - 4
                        ? min(maximum, current + max(240, geometry.containerSize.width * 0.8))
                        : nil
                } action: { _, offset in
                    if tabletWebLayout { nextMatchupOffset = offset }
                }
                .scrollIndicators(.hidden)
                .frame(height: 135)
            }
        }
        .onChange(of: teams.map(\.key)) { _, ids in
            if let team, !ids.contains(team) { self.team = nil }
        }
    }

    private var tabletPopularPairs: [(team: String, first: MatchupDriver, second: MatchupDriver)] {
        let drivers = Dictionary(uniqueKeysWithValues: customDrivers.map { ($0.id, $0) })
        let pairs = summaries(types: seasonComparisonTypes, catalog: true, ignoresFilters: true)
        let ranked = pairs.sorted {
            (drivers[$0.id.left]?.rank ?? .max, drivers[$0.id.right]?.rank ?? .max, $0.id.team, $0.id.left, $0.id.right)
                < (drivers[$1.id.left]?.rank ?? .max, drivers[$1.id.right]?.rank ?? .max, $1.id.team, $1.id.left, $1.id.right)
        }
        var used: Set<String> = []
        return ranked.compactMap { pair in
            guard let left = drivers[pair.id.left], let right = drivers[pair.id.right],
                  used.insert(pair.id.team).inserted else { return nil }
            return (pair.id.team, left, right)
        }
    }

    private func matchupCard(_ left: MatchupDriver, _ right: MatchupDriver) -> some View {
        let leftTint = DashboardArt.teamColor(left.teamID)
        let rightTint = DashboardArt.teamColor(right.teamID)
        return ZStack(alignment: .bottom) {
            LinearGradient(colors: [rightTint, rightTint.opacity(0.62)], startPoint: .topTrailing, endPoint: .bottomLeading)
            LinearGradient(colors: [leftTint, leftTint.opacity(0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .mask {
                    GeometryReader { geometry in
                        Path { path in
                            path.move(to: .zero)
                            path.addLine(to: CGPoint(x: geometry.size.width * 0.57, y: 0))
                            path.addLine(to: CGPoint(x: geometry.size.width * 0.43, y: geometry.size.height))
                            path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                            path.closeSubpath()
                        }
                    }
                }
            GeometryReader { geometry in
                Path { path in
                    path.move(to: CGPoint(x: geometry.size.width * 0.57, y: 0))
                    path.addLine(to: CGPoint(x: geometry.size.width * 0.43, y: geometry.size.height))
                }
                .stroke(.white.opacity(0.5), lineWidth: 1)
            }
            HStack {
                matchupPortrait(left)
                Spacer(minLength: 0)
                matchupPortrait(right)
            }.padding(.horizontal, 6)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .frame(height: 88)
            Text("VS").font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.black.opacity(0.66), in: .capsule)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(shortName(left.name))
                Spacer()
                Text(shortName(right.name))
            }.font(.caption.weight(.medium)).padding(12)
        }
        .foregroundStyle(.white)
        .background(.black)
        .frame(width: 257, height: 135)
        .clipShape(PulseStyle.cardShape)
        .contentShape(PulseStyle.cardShape)
        .accessibilityElement(children: .ignore)
    }

    @ViewBuilder private func matchupPortrait(_ driver: MatchupDriver) -> some View {
        if let photo = DashboardArt.image(.driverPhoto, id: driver.id, season: model.season) {
            Image(uiImage: photo).resizable().scaledToFit()
                .frame(width: 112, height: 116, alignment: .bottom)
        } else {
            AssetImage(name: MotorsportAssetName.helmetName(driverID: driver.id, name: driver.name, season: model.season))
                .frame(width: 85, height: 90, alignment: .bottom)
        }
    }

    private func comparisonCard(_ category: SessionType, mode: Binding<Mode>) -> some View {
        let qualifying = category == .qualifying
        let types = mode.wrappedValue.types(for: category)
        let summaries = summaries(types: types)
        let pairs = tabletWebLayout ? summaries.sorted {
            Double(abs($0.wins - $0.losses)) / Double($0.total)
                > Double(abs($1.wins - $1.losses)) / Double($1.total)
        } : summaries
        let session = qualifying ? "Qualifying" : "Race"
        let title = session + (tabletWebLayout ? " H2H" : " Head to Head")
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            }
            sessionModes(mode, qualifying: qualifying)
            if pairs.isEmpty {
                Text("No shared results for the selected drivers and session type.")
                    .font(.subheadline).foregroundStyle(WebDashboardStyle.homeMuted)
            }
            ForEach(pairs) { pair in
                if tabletWebLayout {
                    Button {
                        team = nil
                        let winnerFirst = pair.wins >= pair.losses
                        first = winnerFirst ? pair.id.left : pair.id.right
                        second = winnerFirst ? pair.id.right : pair.id.left
                    } label: {
                        tabletPairBar(pair)
                    }
                    .buttonStyle(.plain)
                } else {
                    if pair.id != pairs.first?.id { Divider() }
                    NavigationLink {
                        DriverComparison(firstDriverID: pair.id.left, secondDriverID: pair.id.right,
                                         teammateTeamID: pair.id.team.isEmpty ? nil : pair.id.team,
                                         category: types[0], combineSprint: types.count > 1)
                            .navigationTitle("\(shortName(pair.left)) vs \(shortName(pair.right))")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        pairRow(pair)
                    }
                    .buttonStyle(.plain).navigationLinkIndicatorVisibility(.hidden)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .dashboardPanel(WebDashboardStyle.homePanel)
        .pulseSwap(mode.wrappedValue)
    }

    private func sessionModes(_ selection: Binding<Mode>, qualifying: Bool = true) -> some View {
        PulseSectionPicker(sections: [(.combined, "Combined"), (.regular, qualifying ? "Qualifying" : "Race"),
                                      (.sprint, qualifying ? "Sprint Qualifying" : "Sprint Race")], selection: selection)
    }

    private struct GapSample: Identifiable {
        let session: Int
        let phase: String
        let meeting: String
        let seconds: Double
        var id: String { "\(session)-\(phase)" }
    }

    private typealias GapRow = (pair: Pair, samples: [GapSample], average: Double)

    private struct GapPointSelection: Equatable {
        let pair: PairID
        let sample: String
    }

    private func qualifyingGapCard(_ weekends: [SeasonResultWeekend]) -> some View {
        let types = gapMode.types(for: .qualifying)
        let sessions = weekends.flatMap { weekend in
            types.compactMap { type -> (name: String, sprint: Bool, rows: [String: SessionResult])? in
                guard let rows = weekend.sessions[type.rawValue]?.rows, !rows.isEmpty else { return nil }
                return (weekend.meeting.name, type == .sprintQualifying,
                        Dictionary(rows.map { ($0.driverId, $0) }, uniquingKeysWith: { first, _ in first }))
            }
        }
        let pairs = tabletWebLayout ? summaries(types: seasonComparisonTypes, catalog: true) : summaries(types: types)
        let matches = pairs.compactMap { pair -> GapRow? in
            let samples = sessions.enumerated().flatMap { index, session -> [GapSample] in
                guard let left = session.rows[pair.id.left], let right = session.rows[pair.id.right],
                      pair.id.team.isEmpty || (
                        MobileModel.normalizedConstructorID(left.constructorId) == pair.id.team
                        && MobileModel.normalizedConstructorID(right.constructorId) == pair.id.team
                      ) else { return [] }
                let leftTimes = [left.q1, left.q2, left.q3]
                let rightTimes = [right.q1, right.q2, right.q3]
                let prefix = session.sprint ? "SQ" : "Q"
                if (leftTimes + rightTimes).allSatisfy({ $0 == nil }),
                   let firstLap = AnalysisMath.elapsedSeconds(left.bestLap),
                   let secondLap = AnalysisMath.elapsedSeconds(right.bestLap) {
                    return [GapSample(session: index, phase: "Best lap", meeting: session.name, seconds: firstLap - secondLap)]
                }
                return leftTimes.indices.compactMap { phase in
                    guard let firstLap = AnalysisMath.elapsedSeconds(leftTimes[phase]),
                          let secondLap = AnalysisMath.elapsedSeconds(rightTimes[phase]) else { return nil }
                    return GapSample(session: index, phase: "\(prefix)\(phase + 1)", meeting: session.name, seconds: firstLap - secondLap)
                }
            }
            guard !samples.isEmpty else { return nil }
            return (pair, samples, samples.reduce(0.0) { $0 + $1.seconds } / Double(samples.count))
        }
        let rows = tabletWebLayout ? matches.sorted { $0.average < $1.average } : matches
        let extent = tabletWebLayout ? 2 : max(0.25, (rows.lazy.flatMap(\.samples).map { abs($0.seconds) }.max() ?? 0) * 1.08)
        let title = tabletWebLayout ? "Teammate Qualifying Gaps" : "Qualifying Gaps"
        return analysisCard(title) {
            sessionModes($gapMode)
            Toggle(tabletWebLayout ? "Highlight last quali" : "Highlight Latest Session", isOn: $highlightLatest).font(.subheadline)
            Text(tabletWebLayout
                 ? "Each dot compares matching Q1, Q2 and Q3 (or SQ1, SQ2 and SQ3) lap times. Only phases with valid times for both drivers are included."
                 : "Each dot shows the gap in the same qualifying phase. Tap the chart for the session and exact time.")
                .font(.caption).foregroundStyle(WebDashboardStyle.homeMuted)
            if rows.isEmpty {
                Text("No matching qualifying lap times are available for this selection.")
                    .font(.subheadline).foregroundStyle(WebDashboardStyle.homeMuted)
            }
            ForEach(rows, id: \.pair.id) { row in
                gapPlot(row.pair, samples: row.samples, average: row.average, extent: extent)
            }
        }
        .onChange(of: gapMode) { resetGapSelection() }
    }

    private func gapPlot(_ pair: Pair, samples: [GapSample], average: Double, extent: Double) -> some View {
        let tint = tabletWebLayout ? WebDashboardStyle.chartTeamColor(pair.leftTeamID) : DashboardArt.teamColor(pair.leftTeamID)
        let latest = samples.last?.session
        func plottedGap(_ seconds: Double) -> Double { max(-extent, min(extent, seconds)) }
        let ticks = tabletWebLayout ? (-4...4).map { Double($0) / 2 } : [-extent * 0.75, 0, extent * 0.75]
        let selection = Binding<Double?>(get: { selectedGap[pair.id] }, set: { selectedGap[pair.id] = $0 })
        let activePoint = hoveredGapPoint ?? tappedGapPoint
        let sample = if tabletWebLayout {
            activePoint.flatMap { point in
                point.pair == pair.id ? samples.first { $0.id == point.sample } : nil
            }
        } else {
            selection.wrappedValue.flatMap { value in
                samples.min { abs($0.seconds - value) < abs($1.seconds - value) }
            }
        }
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(shortName(pair.left))
                Spacer()
                Text(shortName(pair.right))
            }.font(.subheadline.weight(.semibold))
            Chart {
                RuleMark(x: .value("Equal", 0.0)).foregroundStyle(.secondary)
                RuleMark(x: .value("Mean", plottedGap(average))).foregroundStyle(tint)
                ForEach(Array(samples.enumerated()), id: \.element.id) { index, point in
                    PointMark(x: .value("Gap", plottedGap(point.seconds)), y: .value("Lane", index % 3))
                        .foregroundStyle(tint.opacity(!highlightLatest || point.session == latest ? 1 : (tabletWebLayout ? 0.18 : 0.22)))
                        .accessibilityLabel("\(point.meeting) · \(point.phase)")
                        .accessibilityValue(gapLabel(point.seconds))
                }
                if let sample {
                    RuleMark(x: .value("Selected Gap", plottedGap(sample.seconds)))
                        .foregroundStyle(.primary.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXScale(domain: -extent...extent)
            .chartYScale(domain: -1...3)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: ticks) { value in
                    AxisGridLine()
                    if let seconds = value.as(Double.self) {
                        AxisValueLabel(seconds == 0 ? "0" : seconds.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))) + " s")
                    }
                }
            }
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { event in proxy.selectXValue(at: event.location.x) }
            }
            .chartXSelection(value: tabletWebLayout ? .constant(nil) : selection)
            .chartOverlay { proxy in
                if tabletWebLayout {
                    GeometryReader { geometry in
                        if let frame = proxy.plotFrame {
                            let plot = geometry[frame]
                            Color.clear.contentShape(.rect)
                                .onTapGesture { location in
                                    let point = gapPoint(at: location, plot: plot, proxy: proxy, pair: pair.id,
                                                         samples: samples, extent: extent)
                                    tappedGapPoint = tappedGapPoint == point ? nil : point
                                }
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        hoveredGapPoint = gapPoint(at: location, plot: plot, proxy: proxy, pair: pair.id,
                                                                   samples: samples, extent: extent)
                                    case .ended:
                                        if hoveredGapPoint?.pair == pair.id { hoveredGapPoint = nil }
                                    }
                                }
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .frame(height: 80)
            .pulseChart()
            if let sample {
                LabeledContent("\(sample.meeting) · \(sample.phase)") {
                    PulseNumber(gapLabel(sample.seconds) + (tabletWebLayout && abs(sample.seconds) > extent ? " (outside ±2s axis)" : ""))
                }
                .font(.caption).monospacedDigit()
            } else {
                let faster = average < 0 ? pair.left : pair.right
                let value = abs(average).formatted(.number.precision(.fractionLength(3)))
                Text(average == 0 ? "Even on average" : "\(shortName(faster)) faster by \(value) s on average")
                    .font(.caption).foregroundStyle(WebDashboardStyle.homeMuted)
            }
        }
        .padding(10)
        .background(.primary.opacity(0.035), in: PulseStyle.insetShape)
        .onDisappear {
            if hoveredGapPoint?.pair == pair.id { hoveredGapPoint = nil }
            if tappedGapPoint?.pair == pair.id { tappedGapPoint = nil }
        }
    }

    private func gapPoint(
        at location: CGPoint, plot: CGRect, proxy: ChartProxy, pair: PairID, samples: [GapSample], extent: Double
    ) -> GapPointSelection? {
        guard plot.insetBy(dx: -8, dy: -8).contains(location) else { return nil }
        var nearest: GapPointSelection?
        var bestDistance: CGFloat = 10 * 10
        for (index, sample) in samples.enumerated() {
            let plotted = max(-extent, min(extent, sample.seconds))
            guard let x = proxy.position(forX: plotted), let y = proxy.position(forY: index % 3) else { continue }
            let dx = location.x - plot.minX - x
            let dy = location.y - plot.minY - y
            let distance = dx * dx + dy * dy
            if distance <= bestDistance {
                bestDistance = distance
                nearest = GapPointSelection(pair: pair, sample: sample.id)
            }
        }
        return nearest
    }

    private func gapLabel(_ seconds: Double) -> String {
        seconds.formatted(.number.sign(strategy: .always()).precision(.fractionLength(3))) + " s"
    }

    private func poleCard(_ weekends: [SeasonResultWeekend]) -> some View {
        let types = poleMode.types(for: .qualifying)
        let pairs = summaries(types: seasonComparisonTypes, catalog: tabletWebLayout)
        let teams = Set(pairs.flatMap { pair in
            pair.id.team.isEmpty ? [pair.leftTeamID, pair.rightTeamID] : [pair.id.team]
        })
        return analysisCard("Team Gap to Pole") {
            sessionModes($poleMode)
            Text("Each team's fastest qualifying lap compared with the pole sitter's time in the same qualifying phase.")
                .font(.caption).foregroundStyle(WebDashboardStyle.homeMuted)
            TeamPoleTrend(weekends: weekends, teamIDs: teams, types: types,
                          constructorPositions: constructorPositions, tabletWebLayout: tabletWebLayout)
        }
    }

    private func analysisCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .dashboardPanel(WebDashboardStyle.homePanel)
    }

    private func pairRow(_ pair: Pair) -> some View {
        let leftTint = DashboardArt.teamColor(pair.leftTeamID)
        let rightTint = DashboardArt.teamColor(pair.rightTeamID)
        return VStack(spacing: 7) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    PulseNumber(pair.wins.formatted()).font(.headline.monospacedDigit())
                    Text(shortName(pair.left)).font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 3) {
                    if let logo = DashboardArt.image(.teamLogo, id: pair.leftTeamID, season: model.season) {
                        Image(uiImage: logo).resizable().scaledToFit().frame(width: 19, height: 15)
                    }
                    if pair.rightTeamID != pair.leftTeamID,
                       let logo = DashboardArt.image(.teamLogo, id: pair.rightTeamID, season: model.season) {
                        Image(uiImage: logo).resizable().scaledToFit().frame(width: 19, height: 15)
                    }
                }
                .frame(minWidth: 19).accessibilityHidden(true)
                HStack(spacing: 8) {
                    Text(shortName(pair.right)).font(.subheadline.weight(.medium))
                    PulseNumber(pair.losses.formatted()).font(.headline.monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    leftTint.frame(width: geometry.size.width * CGFloat(pair.wins) / CGFloat(pair.total))
                    Color.secondary.opacity(0.24)
                    rightTint.opacity(pair.leftTeamID == pair.rightTeamID ? 0.5 : 1)
                        .frame(width: geometry.size.width * CGFloat(pair.losses) / CGFloat(pair.total))
                }
            }
            .frame(height: 3).clipShape(.capsule).accessibilityHidden(true)
        }
        .padding(.vertical, 5)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pair.left) \(pair.wins), \(pair.right) \(pair.losses)")
        .accessibilityValue("\(pair.total) comparable sessions, \(pair.ties) ties")
        .accessibilityHint("Open driver comparison")
    }

    private func shortName(_ name: String) -> String {
        name.split(separator: " ").last.map(String.init) ?? name
    }

    private struct ComparisonBar {
        let leftTeam: String
        let rightTeam: String
        let leftName: String
        let rightName: String
        let leftWins: Int
        let rightWins: Int

        init(_ pair: Pair) {
            let swapped = pair.losses > pair.wins
            leftTeam = swapped ? pair.rightTeamID : pair.leftTeamID
            rightTeam = swapped ? pair.leftTeamID : pair.rightTeamID
            leftName = swapped ? pair.right : pair.left
            rightName = swapped ? pair.left : pair.right
            leftWins = max(pair.wins, pair.losses)
            rightWins = min(pair.wins, pair.losses)
        }

        var fraction: CGFloat {
            let decisive = leftWins + rightWins
            let proportion = decisive > 0 ? CGFloat(leftWins) / CGFloat(decisive) : 0.5
            return min(645.0 / 780, max(135.0 / 780, proportion))
        }

        var darkInk: Bool {
            ["mclaren", "mercedes", "haas", "williams", "cadillac", "rb", "racing-bulls"]
                .contains(LiveIslandLogic.assetSlug(leftTeam))
        }
    }

    private func tabletPairBar(_ pair: Pair) -> some View {
        let bar = ComparisonBar(pair)
        let leftInk: Color = bar.darkInk ? Color(red: 7 / 255, green: 17 / 255, blue: 27 / 255) : .white
        return GeometryReader { geometry in
            let scale = geometry.size.width / 780
            ZStack {
                WebDashboardStyle.chartTeamColor(bar.rightTeam, adjustsForLight: false)
                Color.black.opacity(0.42)
                HStack(spacing: 0) {
                    WebDashboardStyle.chartTeamColor(bar.leftTeam, adjustsForLight: false).frame(width: geometry.size.width * bar.fraction)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10 * scale) {
                    Text(String(bar.leftWins)).font(.system(size: 19 * scale, weight: .bold))
                    Text(shortName(bar.leftName)).font(.system(size: 14 * scale, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(shortName(bar.rightName)).font(.system(size: 14 * scale, weight: .semibold)).lineLimit(1).foregroundStyle(.white)
                    Text(String(bar.rightWins)).font(.system(size: 19 * scale, weight: .bold)).foregroundStyle(.white)
                }
                .foregroundStyle(leftInk)
                .padding(.horizontal, 14 * scale)
                if let logo = DashboardArt.image(.teamLogo, id: bar.leftTeam, season: model.season) {
                    Image(uiImage: logo).resizable().scaledToFit().frame(width: 46 * scale, height: 28 * scale)
                }
            }
            .frame(height: 52 * scale)
            .clipShape(.rect(cornerRadius: 4 * scale))
        }
        .aspectRatio(780.0 / 52, contentMode: .fit)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bar.leftName) \(bar.leftWins), \(bar.rightName) \(bar.rightWins)")
        .accessibilityValue("\(pair.total) comparable sessions, \(pair.ties) ties")
        .accessibilityHint("Open driver comparison")
    }

    private var seasonComparisonTypes: [SessionType] { [.race, .sprint, .qualifying, .sprintQualifying] }

    private func summaries(types: [SessionType], catalog: Bool = false, ignoresFilters: Bool = false) -> [Pair] {
        let weekends = model.seasonArchive?.data ?? []
        let rankedDrivers = tabletWebLayout ? tabletDrivers : currentLineup
        if tabletWebLayout, !ignoresFilters,
           let left = rankedDrivers.first(where: { $0.id == first }),
           let right = rankedDrivers.first(where: { $0.id == second }) {
            let team = left.teamID == right.teamID ? left.teamID : ""
            let id = PairID(team: team, left: left.id, right: right.id)
            var pair = Pair(id: id, left: left.name, right: right.name, leftTeamID: left.teamID, rightTeamID: right.teamID)
            if catalog { return [pair] }
            for weekend in weekends {
                for type in types {
                    let rows = weekend.sessions[type.rawValue]?.rows ?? []
                    guard let first = rows.first(where: { $0.id == left.id }),
                          let second = rows.first(where: { $0.id == right.id }),
                          team.isEmpty || (MobileModel.normalizedConstructorID(first.constructorId) == team
                            && MobileModel.normalizedConstructorID(second.constructorId) == team),
                          let outcome = comparisonWinner(first, second, onlyClassified: false) else { continue }
                    pair.record(outcome)
                }
            }
            return pair.total == 0 ? [] : [pair]
        }
        let lineup = rankedDrivers
        let driverPositions = Dictionary(lineup.map { ($0.id, $0.rank) }, uniquingKeysWith: min)
        let currentTeams = Dictionary(lineup.map { ($0.id, $0.teamID) }, uniquingKeysWith: { first, _ in first })
        var pairs: [PairID: Pair] = [:]
        for weekend in weekends {
            for type in types {
                let rows = weekend.sessions[type.rawValue]?.rows ?? []
                let groups = Dictionary(grouping: rows.filter { row in
                    let id = MobileModel.normalizedConstructorID(row.constructorId)
                    return (tabletWebLayout || currentTeams[row.id] == id) && (ignoresFilters || team == nil || id == team)
                }) { MobileModel.normalizedConstructorID($0.constructorId) }.values
                for group in groups where group.count > 1 {
                    let sorted = group.sorted {
                        (driverPositions[$0.id] ?? .max, $0.id) < (driverPositions[$1.id] ?? .max, $1.id)
                    }
                    for (index, left) in sorted.enumerated() {
                        for right in sorted.dropFirst(index + 1) where left.id != right.id {
                            if tabletWebLayout, !ignoresFilters,
                               [first, second].contains(where: { !$0.isEmpty && $0 != left.id && $0 != right.id }) {
                                continue
                            }
                            let key = PairID(team: MobileModel.normalizedConstructorID(left.constructorId), left: left.id, right: right.id)
                            var pair = pairs[key] ?? Pair(id: key, left: left.driverName, right: right.driverName,
                                                         leftTeamID: left.constructorId, rightTeamID: right.constructorId)
                            if !catalog {
                                guard let outcome = comparisonWinner(left, right, onlyClassified: false) else { continue }
                                pair.record(outcome)
                            }
                            pairs[key] = pair
                        }
                    }
                }
            }
        }
        return pairs.values.sorted {
            (constructorPositions[$0.id.team] ?? .max, $0.id.team,
             driverPositions[$0.id.left] ?? .max, driverPositions[$0.id.right] ?? .max, $0.id.left, $0.id.right)
                < (constructorPositions[$1.id.team] ?? .max, $1.id.team,
                   driverPositions[$1.id.left] ?? .max, driverPositions[$1.id.right] ?? .max, $1.id.left, $1.id.right)
        }
    }
}

struct DriverConsistency: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openDashboardDriverProfile) private var openDriver
    var tabletWebLayout = false
    var tabletFilter: Binding<Bool>? = nil
    @State private var localFilter = false

    private var retirementFilter: Binding<Bool> { tabletFilter ?? $localFilter }
    private var excludeRetirements: Bool { retirementFilter.wrappedValue }
    @State private var selectedDrivers: [SessionType: String] = [:]
    @State private var hoveredDriver: [SessionType: String] = [:]

    private let sessions: [SessionType] = [.race, .sprint, .qualifying, .sprintQualifying]

    var body: some View {
        GeometryReader { geometry in
            let columns = geometry.size.width >= (tabletWebLayout ? 1051 : 980) && !typeSize.isAccessibilitySize ? 2 : 1
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !tabletWebLayout { consistencyOptions }
                    Group {
                        if let archive = model.seasonArchive {
                            if archive.meta.stale {
                                Label("Season results may be out of date", systemImage: "clock.arrow.circlepath")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columns),
                                      alignment: .leading, spacing: 14) {
                                ForEach(sessions, id: \.self) { category in
                                    consistencyCard(category, archive: archive.data)
                                        .accessibilityElement(children: .contain)
                                }
                            }
                        } else if let error = model.seasonArchiveError {
                            ContentUnavailableView {
                                Label("Couldn’t Load Season Results", systemImage: "chart.box")
                            } description: {
                                Text(error.pulseEnglishError)
                            } actions: {
                                Button("Retry") { Task { await model.loadSeasonArchive(force: true) } }
                                    .buttonStyle(.bordered)
                            }
                        } else {
                            PulseSkeleton(label: "Loading position distributions", chart: true)
                            PulseSkeleton(label: "Loading qualifying distributions", chart: true)
                        }
                    }
                    .pulseSwap(model.seasonArchive != nil)
                }
                .padding(16)
            }
        }
        .onChange(of: model.dataContext) { resetDistributionSelection() }
        .onChange(of: excludeRetirements) { resetDistributionSelection() }
        .foregroundStyle(WebDashboardStyle.homeText)
        .background(WebDashboardStyle.homeBackground)
        .task(id: model.dataContext) {
            async let roster: Void = tabletWebLayout ? model.loadF1Roster() : ()
            await model.loadSeasonArchive()
            await roster
        }
        .refreshable { await model.loadSeasonArchive(force: true) }
    }

    private func resetDistributionSelection() {
        selectedDrivers = [:]
        hoveredDriver = [:]
    }

    private var consistencyOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Position Consistency").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(String(model.season)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("The line shows best to worst. The box shows the middle 50%, with a marker at the median.")
                .font(.footnote).foregroundStyle(.secondary)
            Divider()
            Toggle("Exclude DNF, DNS, DSQ and NC", isOn: retirementFilter)
                .font(.subheadline.weight(.medium))
                .tint(PulseStyle.red)
                .accessibilityIdentifier("consistency.excludeDNF")
        }
        .padding(14)
        .dashboardPanel(WebDashboardStyle.homePanel)
    }

    private func consistencyCard(_ category: SessionType, archive: [SeasonResultWeekend]) -> some View {
        let rows = archive.map { $0.sessions[category.rawValue]?.rows ?? [] }
        let groups = distributions(rows.flatMap { $0 })
        let fieldSize = max(20, rows.map(\.count).max() ?? 0, groups.compactMap { $0.positions.last }.max() ?? 0)
        let selection = Binding<String?>(get: { selectedDrivers[category] },
                                         set: { selectedDrivers[category] = $0 })
        let selected = groups.first { $0.id == selection.wrappedValue }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(distributionTitle(category))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("consistency.chart.\(category.rawValue)")
            }
            if tabletWebLayout {
                if groups.isEmpty {
                    Text("No recorded positions for this season and selection.")
                        .foregroundStyle(WebDashboardStyle.homeMuted)
                } else {
                    tabletDistributionChart(groups, fieldSize: fieldSize, category: category)
                }
            } else if groups.isEmpty {
                ContentUnavailableView("No recorded positions", systemImage: "chart.box")
                    .frame(minHeight: 160)
            } else {
                distributionChart(groups, fieldSize: fieldSize, category: category, selection: selection)
                if let selected {
                    Divider()
                    driverDistribution(selected, fieldSize: fieldSize)
                } else {
                    Text("Swipe for more drivers. Tap a driver to see their results.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardPanel(WebDashboardStyle.homePanel)
        .pulseSwap(selected != nil)
    }

    private func distributionTitle(_ category: SessionType) -> String {
        switch category {
        case .race where tabletWebLayout: "Race Finishing Position Distribution"
        case .sprint where tabletWebLayout: "Sprint Finishing Position Distribution"
        case .qualifying where tabletWebLayout: "Qualifying Position Distribution"
        case .sprintQualifying where tabletWebLayout: "Sprint Qualifying Position Distribution"
        case .race: "Race Results"
        case .sprint: "Sprint Results"
        case .qualifying: "Qualifying Results"
        case .sprintQualifying: "Sprint Qualifying Results"
        default: "Position Distribution"
        }
    }

    private struct DistributionGeometry {
        let fieldSize: Int
        let count: Int
        var step: CGFloat { 734 / CGFloat(max(1, count)) }
        var width: CGFloat { min(26, step * 0.72) }
        func x(_ index: Int) -> CGFloat { 34 + step * (CGFloat(index) + 0.5) }
        func y(_ position: Double) -> CGFloat { 24 + CGFloat((position - 1) / Double(fieldSize - 1)) * 538 }
    }

    private func tabletDistributionChart(_ groups: [Distribution], fieldSize: Int, category: SessionType) -> some View {
        let layout = DistributionGeometry(fieldSize: fieldSize, count: groups.count)
        let width = layout.width
        let lines = cutoffs(category: category, fieldSize: fieldSize)
        let qualifying = category == .qualifying || category == .sprintQualifying
        let muted = WebDashboardStyle.homeMuted

        return Canvas { context, size in
            var context = context
            context.scaleBy(x: size.width / 780, y: size.height / 620)
            func line(_ first: CGPoint, _ last: CGPoint, color: Color, style: StrokeStyle = StrokeStyle(lineWidth: 1)) {
                var path = Path()
                path.move(to: first)
                path.addLine(to: last)
                context.stroke(path, with: .color(color), style: style)
            }
            for rank in 1...fieldSize {
                let level = layout.y(Double(rank))
                line(CGPoint(x: 34, y: level), CGPoint(x: 768, y: level), color: muted.opacity(0.17))
                context.draw(Text(String(rank)).font(.system(size: 11, weight: .semibold)).foregroundStyle(muted),
                             at: CGPoint(x: 27, y: level), anchor: .trailing)
            }
            for cutoff in lines {
                let level = layout.y(Double(cutoff.position))
                line(CGPoint(x: 34, y: level), CGPoint(x: 768, y: level),
                     color: muted.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                context.draw(Text(qualifying ? cutoff.label : "In points").font(.system(size: 11, weight: .semibold)).foregroundStyle(muted),
                             at: CGPoint(x: qualifying ? 44 : 760, y: level - 10), anchor: qualifying ? .leading : .trailing)
            }
            for (index, driver) in groups.enumerated() {
                let x = layout.x(index)
                let color = WebDashboardStyle.chartTeamColor(driver.team, adjustsForLight: false)
                let best = layout.y(Double(driver.positions.first ?? 1))
                let worst = layout.y(Double(driver.positions.last ?? 1))
                let lower = layout.y(driver.quantile(0.25))
                let upper = layout.y(driver.quantile(0.75))
                let middle = layout.y(driver.median)
                line(CGPoint(x: x, y: best), CGPoint(x: x, y: worst), color: color)
                for level in [best, worst] {
                    line(CGPoint(x: x - width * 0.3, y: level), CGPoint(x: x + width * 0.3, y: level), color: color)
                }
                let box = CGRect(x: x - width / 2, y: lower == upper ? lower - 1 : lower,
                                 width: width, height: max(2, upper - lower))
                context.fill(Path(roundedRect: box, cornerRadius: 2), with: .color(color))
                line(CGPoint(x: x - width / 2, y: middle), CGPoint(x: x + width / 2, y: middle),
                     color: .black.opacity(0.28), style: StrokeStyle(lineWidth: 2.2))
                var rotated = context
                rotated.translateBy(x: x + 2, y: 577)
                rotated.rotate(by: .degrees(-48))
                rotated.draw(Text(MotorsportAssetName.abbreviation(driver.name)).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(muted), at: .zero, anchor: .trailing)
            }
        }
        .accessibilityHidden(true)
        .overlay {
            GeometryReader { geometry in
                let scaleX = geometry.size.width / 780
                let scaleY = geometry.size.height / 620
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, driver in
                    let profile = model.driverRoster.first { $0.id == driver.id && $0.season == model.season }
                    Button {
                        if let profile { openDriver?(.stats(StandingEntry(driver: profile))) }
                    } label: {
                        Color.clear.contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .frame(width: layout.step * scaleX, height: 589 * scaleY)
                    .position(x: (layout.x(index)) * scaleX, y: 313.5 * scaleY)
                    .disabled(profile == nil || openDriver == nil)
                    .onHover { inside in
                        if inside { hoveredDriver[category] = driver.id }
                        else if hoveredDriver[category] == driver.id { hoveredDriver[category] = nil }
                    }
                    .accessibilityLabel(driver.name)
                    .accessibilityValue(distributionSummary(driver))
                    .accessibilityHint("Open driver statistics")
                }
            }
        }
        .aspectRatio(780.0 / 620, contentMode: .fit)
        .overlay(alignment: .top) {
            if let driver = groups.first(where: { $0.id == hoveredDriver[category] }) {
                Text("\(driver.name) · \(distributionSummary(driver))")
                    .font(.caption)
                    .padding(6)
                    .background(WebDashboardStyle.homePanel, in: .rect(cornerRadius: 5))
                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(WebDashboardStyle.homeLine) }
                    .allowsHitTesting(false)
            }
        }
    }

    private func distributionChart(_ groups: [Distribution], fieldSize: Int, category: SessionType,
                                   selection: Binding<String?>) -> some View {
        let lookup = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        let cutoffs = cutoffs(category: category, fieldSize: fieldSize)
        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { cutoffLabels(cutoffs) }
                VStack(alignment: .leading, spacing: 4) { cutoffLabels(cutoffs) }
            }
            ScrollView(.horizontal) {
            Chart {
                RuleMark(y: .value("Lower Axis Bound", 0.4)).foregroundStyle(.clear).accessibilityHidden(true)
                RuleMark(y: .value("Upper Axis Bound", Double(fieldSize) + 0.6)).foregroundStyle(.clear).accessibilityHidden(true)
                ForEach(cutoffs, id: \.position) { line in
                    RuleMark(y: .value(line.label, Double(line.position)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(PulseStyle.red.opacity(0.55))
                }
                ForEach(groups) { driver in
                    let color = DashboardArt.teamColor(driver.team)
                    let active = selection.wrappedValue == driver.id
                    RuleMark(
                        x: .value("Driver", driver.id),
                        yStart: .value("Best", Double(driver.positions.first ?? 1)),
                        yEnd: .value("Worst", Double(driver.positions.last ?? 1))
                    ).foregroundStyle(color.opacity(active ? 1 : 0.64))
                    RectangleMark(
                        x: .value("Driver", driver.id),
                        yStart: .value("Lower Quartile", driver.quantile(0.25)),
                        yEnd: .value("Upper Quartile", driver.quantile(0.75)),
                        width: active ? 19 : 14
                    )
                    .foregroundStyle(color.opacity(active ? 1 : 0.78))
                    .accessibilityLabel(driver.name)
                    .accessibilityValue(distributionSummary(driver))
                    RectangleMark(x: .value("Driver", driver.id), y: .value("Median", driver.median),
                                  width: active ? 18 : 14, height: 2)
                        .foregroundStyle(.primary)
                }
            }
            .chartXScale(domain: groups.map(\.id))
            .chartYScale(domain: .automatic(includesZero: false, reversed: true))
            .chartXAxis {
                AxisMarks(values: groups.map(\.id)) { value in
                    if let id = value.as(String.self), let driver = lookup[id] {
                        AxisValueLabel(MotorsportAssetName.abbreviation(driver.name))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [1, 5, 10, 15, 20, fieldSize].filter { $0 < fieldSize }.map(Double.init) + [Double(fieldSize)]) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                    if let rank = value.as(Double.self) { AxisValueLabel("P\(Int(rank))") }
                }
            }
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { event in proxy.selectXValue(at: event.location.x) }
            }
            .chartXSelection(value: selection)
            .frame(width: max(315, CGFloat(groups.count * 32 + 54)), height: 268)
            .pulseChart()
            .accessibilityAdjustableAction { direction in
                let index = groups.firstIndex { $0.id == selection.wrappedValue }
                switch direction {
                case .increment:
                    selection.wrappedValue = groups[min((index ?? -1) + 1, groups.count - 1)].id
                case .decrement:
                    selection.wrappedValue = groups[max((index ?? 1) - 1, 0)].id
                @unknown default: break
                }
            }
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.leading)
        }
    }

    private func driverDistribution(_ choice: Distribution, fieldSize: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AssetImage(name: MotorsportAssetName.helmetName(driverID: choice.id, name: choice.name, season: model.season))
                    .frame(width: 40, height: 34)
                Text(choice.name).font(.headline)
                Spacer(minLength: 4)
                if let driver = model.driverRoster.first(where: { $0.id == choice.id }) {
                    NavigationLink {
                        StandingProfile(entry: StandingEntry(driver: driver))
                    } label: {
                        Label("View Driver Profile", systemImage: "chevron.right")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 32, minHeight: 32)
                    }.buttonStyle(.glass)
                }
            }
            Text(distributionSummary(choice))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Chart(choice.counts, id: \.position) { bucket in
                BarMark(x: .value("Position", bucket.position), y: .value("Sessions", bucket.count))
                    .foregroundStyle(DashboardArt.teamColor(choice.team))
            }
            .chartXScale(domain: 0...fieldSize + 1)
            .chartXAxis {
                AxisMarks(values: [1, 5, 10, 15].filter { $0 < fieldSize } + [fieldSize]) { value in
                    if let rank = value.as(Int.self) { AxisValueLabel("P\(rank)") }
                }
            }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4, roundLowerBound: false, roundUpperBound: true)) }
            .frame(height: 140)
            .pulseChart()
            .accessibilityLabel("\(choice.name) position distribution")
        }
    }

    private func cutoffs(category: SessionType, fieldSize: Int) -> [(position: Int, label: String)] {
        switch category {
        case .qualifying: [(10, "Q3 Cutoff"), (fieldSize - (fieldSize > 20 ? 6 : 5), "Q2 Cutoff")]
        case .sprintQualifying: [(10, "SQ3 Cutoff"), (fieldSize - (fieldSize > 20 ? 6 : 5), "SQ2 Cutoff")]
        case .sprint: [(8, "Points Cutoff")]
        default: [(10, "Points Cutoff")]
        }
    }

    private func cutoffLabels(_ cutoffs: [(position: Int, label: String)]) -> some View {
        ForEach(cutoffs, id: \.position) { line in
            Label("\(line.label) · P\(line.position)", systemImage: "line.horizontal.3")
                .font(.caption.monospacedDigit()).foregroundStyle(PulseStyle.red)
        }
    }

    private func distributionSummary(_ choice: Distribution) -> String {
        let bounds = [choice.quantile(0.25), choice.quantile(0.75)]
            .map { $0.formatted(.number.precision(.fractionLength(0...2))) }
            .joined(separator: "–")
        let median = choice.median.formatted(.number.precision(.fractionLength(0...2)))
        let count = choice.positions.count
        return "\(count) \(count == 1 ? "session" : "sessions") · Median P\(median) · Middle 50% P\(bounds) · Range P\(choice.positions.first ?? 1)–P\(choice.positions.last ?? 1)"
    }

    private func distributions(_ samples: [SessionResult]) -> [Distribution] {
        let retired = Set(["DNF", "DNS", "DSQ", "NC"])
        let rows = samples.filter {
            guard ($0.position ?? 0) > 0 else { return false }
            guard excludeRetirements else { return true }
            if tabletWebLayout {
                return $0.classification.range(
                    of: "dnf|dns|dsq|disqual|retired|did not|not classified|withdrawn",
                    options: [.caseInsensitive, .regularExpression]
                ) == nil
            }
            return !retired.contains($0.classification.uppercased())
        }
        let roster = model.driverRoster.filter { $0.season == model.season }
        let standings = Dictionary(roster.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Dictionary(grouping: rows, by: \.driverId).compactMap { id, rows in
            guard let row = rows.last else { return nil }
            let driver = tabletWebLayout ? standings[id] : nil
            return Distribution(id: id, name: driver?.driverName ?? row.driverName,
                                team: driver?.seasonTeamID ?? row.constructorId, positions: rows.compactMap(\.position).sorted())
        }.sorted { ($0.median, $0.average, standings[$0.id]?.position ?? Int.max, $0.id)
            < ($1.median, $1.average, standings[$1.id]?.position ?? Int.max, $1.id) }
    }

    private struct Distribution: Identifiable {
        let id: String
        let name: String
        let team: String
        let positions: [Int]
        func quantile(_ fraction: Double) -> Double {
            let index = Double(positions.count - 1) * fraction
            let lower = Int(index.rounded(.down))
            let upper = Int(index.rounded(.up))
            return Double(positions[lower]) + (index - Double(lower)) * Double(positions[upper] - positions[lower])
        }
        var median: Double { quantile(0.5) }
        var average: Double { Double(positions.reduce(0, +)) / Double(positions.count) }
        var counts: [(position: Int, count: Int)] {
            Dictionary(grouping: positions, by: { $0 })
                .map { (position: $0.key, count: $0.value.count) }
                .sorted { $0.position < $1.position }
        }
    }
}
