import Charts
import SharedComponents
import SharedData
import SwiftUI
import UIKit

struct SeasonResultsIndex: View {
    let initialMeeting: Meeting?
    let initialSession: Session?

    init(initialMeeting: Meeting? = nil, initialSession: Session? = nil) {
        self.initialMeeting = initialMeeting
        self.initialSession = initialSession
    }
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var statsMode = SeasonResultsMode.race
    @State private var matrixShowsPosition = false
    @State private var wideResults = false
    @State private var openedInitialSession = false
    @State private var previewDestination: (weekend: SeasonResultWeekend, session: Session)?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let archive = model.seasonArchive {
                    let weekends = archive.data.sorted { $0.meeting.startDate > $1.meeting.startDate }
                    let entries = weekends.compactMap { weekend in
                        entrySession(weekend).map { (weekend: weekend, session: $0) }
                    }
                    if archive.meta.stale {
                        Label("Season data is stale", systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(WebDashboardStyle.homeMuted)
                    }
                    if wideResults, !entries.isEmpty {
                        seasonOverview(Array(weekends.reversed()), entries: entries)
                    } else if let latest = entries.first {
                        NavigationLink {
                            MeetingResultsDashboard(weekend: latest.weekend, initial: latest.session)
                        } label: {
                            latestCard(latest.weekend, session: latest.session)
                        }
                        .buttonStyle(.plain)
                        .navigationLinkIndicatorVisibility(.hidden)

                        NavigationLink {
                            SeasonResultsStatistics(weekends: Array(weekends.reversed()), season: model.season)
                        } label: {
                            SeasonLeaders(weekends: weekends, sessions: [.race], season: model.season)
                                .racePreview
                        }
                        .buttonStyle(.plain)
                        .navigationLinkIndicatorVisibility(.hidden)

                        let previous = entries.dropFirst()
                        if let first = previous.first {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(previous, id: \.weekend.id) { entry in
                                    if entry.weekend.id != first.weekend.id { Divider() }
                                    NavigationLink {
                                        MeetingResultsDashboard(weekend: entry.weekend, initial: entry.session)
                                    } label: {
                                        meetingRow(entry.weekend.meeting)
                                    }
                                    .buttonStyle(.plain)
                                    .navigationLinkIndicatorVisibility(.hidden)
                                    .contextMenu {
                                        Button("View Race Results", systemImage: "flag.checkered") {
                                            previewDestination = entry
                                        }
                                    } preview: {
                                        ResultsPodiumPreview(weekend: entry.weekend, session: entry.session)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                            .dashboardPanel(WebDashboardStyle.homePanel)
                        }
                    } else {
                        ContentUnavailableView("No results yet", systemImage: "flag.checkered")
                    }
                }

                if let error = model.seasonArchiveError {
                    Text(error.pulseEnglishError).foregroundStyle(.secondary)
                    Button("Retry") { Task { await model.loadSeasonArchive(force: true) } }
                } else if model.seasonArchive == nil {
                    loadingResults
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onGeometryChange(for: Bool.self) { geometry in
            UIDevice.current.userInterfaceIdiom == .pad && geometry.size.width >= 740 && !typeSize.isAccessibilitySize
        } action: { wideResults = $0 }
        .foregroundStyle(WebDashboardStyle.homeText)
        .background(wideResults ? WebDashboardStyle.homePanel : WebDashboardStyle.homeBackground)
        .pulseSwap(model.seasonArchive != nil)
        .navigationDestination(isPresented: Binding(
            get: { previewDestination != nil },
            set: { if !$0 { previewDestination = nil } }
        )) {
            if let destination = previewDestination {
                MeetingResultsDashboard(weekend: destination.weekend, initial: destination.session)
            }
        }
        .task {
            guard !openedInitialSession, let initialMeeting, let initialSession else { return }
            openedInitialSession = true
            let weekend = model.seasonArchive?.data.first { $0.id == initialMeeting.id }
                ?? SeasonResultWeekend(meeting: initialMeeting, sessions: [:])
            previewDestination = (weekend, initialSession)
        }
        .task(id: model.dataContext) { await model.loadSeasonArchive() }
        .refreshable { await model.loadSeasonArchive(force: true) }
    }

    private func seasonOverview(_ weekends: [SeasonResultWeekend],
                                entries: [(weekend: SeasonResultWeekend, session: Session)]) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(String(model.season)) F1 Season Results")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 6)
                Text("SEASON STATS")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Picker("Season stats", selection: $statsMode) {
                    ForEach(SeasonResultsMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 276)
            }
            SeasonLeaders(weekends: weekends, sessions: statsMode.types, season: model.season, showsCards: true)
            seasonInsights(weekends)

            VStack(alignment: .leading, spacing: 0) {
                Text("Grand Prix Results").font(.headline).accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 8)
                grandPrixColumns(height: 30) {
                    Text("GRAND PRIX")
                    Text("DATE")
                    Text("SPRINT POLEMAN")
                    Text("SPRINT WINNER")
                    Text("POLEMAN")
                    Text("RACE WINNER")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minHeight: 30)
                .accessibilityAddTraits(.isHeader)
                ForEach(entries.reversed(), id: \.weekend.id) { entry in
                    Divider()
                    NavigationLink {
                        MeetingResultsDashboard(weekend: entry.weekend, initial: entry.session)
                    } label: {
                        grandPrixColumns(height: 42) {
                            HStack(spacing: 6) {
                                FlagBadge(countryCode: entry.weekend.meeting.countryCode, width: 17)
                                    .accessibilityHidden(true)
                                if let round = entry.weekend.meeting.round {
                                    Text("R\(round)").font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 4).padding(.vertical, 3)
                                        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(WebDashboardStyle.homeLine) }
                                        .fixedSize()
                                }
                                Text(entry.weekend.meeting.name).fontWeight(.semibold).lineLimit(2)
                            }
                            Text(weekendDates(entry.weekend.meeting))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            ForEach([SessionType.sprintQualifying, .sprint, .qualifying, .race], id: \.self) { session in
                                winnerCell(entry.weekend.sessions[session.rawValue]?.rows.first { $0.position == 1 })
                            }
                        }
                        .font(.caption)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .navigationLinkIndicatorVisibility(.hidden)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(12)
            .seasonResultsPanel()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Driver Points and Positions by Round").font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Picker("Round values", selection: $matrixShowsPosition) {
                        Text("Points").tag(false)
                        Text("Position").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                }
                let rounds = statsMode.rounds(in: weekends)
                if rounds.isEmpty {
                    ContentUnavailableView("No results for this filter", systemImage: "flag.checkered")
                } else {
                    SeasonRoundMatrix(weekends: rounds, sessions: statsMode.types, season: model.season,
                                      showsPosition: matrixShowsPosition, scrollsVertically: false, showsRoundDetails: false)
                }
            }
            .padding(12)
            .seasonResultsPanel()
        }
    }

    private func seasonInsights(_ weekends: [SeasonResultWeekend]) -> some View {
        let stats = SeasonOverviewInsights(weekends: weekends, sessions: statsMode.types)
        let detailHeight: CGFloat = 136
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            seasonInsight("Best Average Finish", symbol: "target",
                          value: stats.average?.value.formatted(.number.precision(.fractionLength(1))),
                          unit: "average", row: stats.average?.row)
            seasonInsight("Most Positions Gained", symbol: "chart.line.uptrend.xyaxis",
                          value: stats.positionsGained?.value.formatted(), unit: "places", row: stats.positionsGained?.row)
            marginCard("Largest Winning Margin", symbol: "arrow.up.left.and.arrow.down.right", result: stats.largestMargin)
            marginCard("Closest Winning Margin", symbol: "arrow.down.right.and.arrow.up.left", result: stats.closestMargin,
                       minHeight: detailHeight)
            seasonInsight("Biggest Comeback", symbol: "arrow.up.forward",
                          value: stats.comeback.map { "+\($0.value)" }, unit: "places", row: stats.comeback?.row,
                          detail: stats.comeback.map { "P\($0.row.gridPosition ?? 0) → P\($0.row.position ?? 0)" },
                          meeting: stats.comeback?.meeting, minHeight: detailHeight)
            mileageCard(stats.mileage, minHeight: detailHeight)
        }
    }

    private func marginCard(_ title: String, symbol: String, result: SeasonOverviewInsights.Margin?,
                            minHeight: CGFloat = 104) -> some View {
        seasonInsight(title, symbol: symbol, value: result.map { String(format: "+%.3fs", $0.seconds) },
                      row: result?.row, meeting: result?.meeting, minHeight: minHeight)
    }

    private func seasonInsight(_ title: String, symbol: String, value: String?, unit: String = "",
                               row: SessionResult?, detail: String? = nil, meeting: Meeting? = nil,
                               minHeight: CGFloat = 104) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Image(systemName: symbol)
                    .font(.caption.weight(.medium))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.secondary)
                    .background(WebDashboardStyle.homeBackground, in: .rect(cornerRadius: 7))
                    .accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                PulseNumber(value ?? "—").font(.title2.bold()).monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            if let row {
                HStack(spacing: 5) {
                    resultTeamLogo(row.constructorId, season: model.season)
                    Text(row.driverName.split(separator: " ").last.map(String.init) ?? row.driverName)
                    if let detail { Text("· " + detail).fixedSize() }
                    if let meeting {
                        if let round = meeting.round { Text("· R\(round)").fixedSize() }
                        FlagBadge(countryCode: meeting.countryCode, width: 13).accessibilityHidden(true)
                        Text(meeting.country.isEmpty ? meeting.name : meeting.country).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .seasonResultsPanel()
        .accessibilityElement(children: .combine)
    }

    private func mileageCard(_ mileage: [SeasonOverviewInsights.Distance], minHeight: CGFloat) -> some View {
        let maxDistance = mileage.first?.km ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("Team Mileage").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            if mileage.isEmpty { Text("—").foregroundStyle(.secondary) }
            ForEach(mileage, id: \.teamID) { team in
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        resultTeamLogo(team.row.constructorId, season: model.season)
                        Text(team.row.team).lineLimit(1)
                    }
                    .frame(maxWidth: 96, alignment: .leading)
                    GeometryReader { proxy in
                        let fraction = team.km / maxDistance
                        let color = seasonResultTeamColor(team.row.constructorId)
                        Text(team.km.formatted(.number.precision(.fractionLength(1))) + " km")
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .frame(width: min(proxy.size.width, max(82, proxy.size.width * fraction)), height: proxy.size.height, alignment: .leading)
                            .foregroundStyle(.black)
                            .background(color, in: .rect(topLeadingRadius: proxy.size.height / 2,
                                                         bottomLeadingRadius: proxy.size.height / 2))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(height: 20)
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
        }
        .padding([.leading, .top], 12)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .seasonResultsPanel()
    }

    private func grandPrixColumns(height: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        let cells = content()
        return GeometryReader { proxy in
            let width = max(0, proxy.size.width - 5 * 3)
            let nameWidth = width * 0.25
            let dateWidth = width * 0.115
            let resultWidth = (width - nameWidth - dateWidth) / 4
            HStack(spacing: 3) {
                Group(subviews: cells) { columns in
                    columns[0].frame(width: nameWidth, alignment: .leading)
                    columns[1].frame(width: dateWidth, alignment: .leading)
                    ForEach(2..<6, id: \.self) { index in
                        columns[index].frame(width: resultWidth, alignment: .leading)
                    }
                }
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: height)
    }

    private func weekendDates(_ meeting: Meeting) -> String {
        let format = Date.VerbatimFormatStyle(format: "\(day: .twoDigits)/\(month: .twoDigits)",
                                              locale: .pulseEnglish, timeZone: .current, calendar: .current)
        let start = meeting.startDate.formatted(format)
        let end = meeting.endDate.formatted(format)
        return start == end ? start : "\(start) – \(end)"
    }

    private func winnerCell(_ winner: SessionResult?) -> some View {
        HStack(spacing: 5) {
            if let winner {
                resultTeamLogo(winner.constructorId, season: model.season, contrast: true)
                Text(winner.driverName).fontWeight(.semibold).lineLimit(2)
            } else {
                Text("—")
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .foregroundStyle(winner == nil ? WebDashboardStyle.homeMuted : .black)
        .background(winner.map { seasonResultTeamColor($0.constructorId) } ?? WebDashboardStyle.homeBackground,
                    in: .rect(cornerRadius: 5))
    }

    private var loadingResults: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Loading season results…")
                    .font(.caption)
                    .foregroundStyle(WebDashboardStyle.homeMuted)
                placeholder(210, height: 24)
                placeholder(104, height: 12)
                HStack(spacing: 10) {
                    placeholder(34, height: 32)
                    placeholder(104)
                    Spacer()
                    placeholder(30, height: 16)
                }
                .padding(8)
                .background(WebDashboardStyle.homeBackground, in: .rect(cornerRadius: 12))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardPanel(WebDashboardStyle.homePanel)

            VStack(alignment: .leading, spacing: 12) {
                placeholder(132, height: 16)
                HStack(spacing: 12) {
                    ForEach(0..<3) { _ in
                        VStack(alignment: .leading, spacing: 7) {
                            placeholder(45)
                            placeholder(60, height: 23)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardPanel(WebDashboardStyle.homePanel)

            VStack(spacing: 0) {
                ForEach(0..<5) { index in
                    if index > 0 { Divider() }
                    HStack(spacing: 10) {
                        placeholder(18, height: 12)
                        VStack(alignment: .leading, spacing: 6) {
                            placeholder(index.isMultiple(of: 2) ? 164 : 134)
                            placeholder(80, height: 9)
                        }
                        Spacer()
                    }
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .dashboardPanel(WebDashboardStyle.homePanel)
        }
    }

    private func placeholder(_ width: CGFloat, height: CGFloat = 11) -> some View {
        RoundedRectangle(cornerRadius: min(6, height / 2))
            .fill(WebDashboardStyle.homeLine)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    private func entrySession(_ weekend: SeasonResultWeekend) -> Session? {
        for type in [SessionType.race, .qualifying, .sprint, .sprintQualifying, .fp1, .fp2, .fp3]
            where weekend.sessions[type.rawValue]?.rows.isEmpty == false {
            if let session = weekend.meeting.sessions.first(where: { $0.sessionType == type }) { return session }
        }
        return nil
    }

    private func latestCard(_ weekend: SeasonResultWeekend, session: Session) -> some View {
        let meeting = weekend.meeting
        let leader = weekend.sessions[session.sessionType.rawValue]?.rows.first { $0.position == 1 }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Latest Result")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PulseStyle.red)
                Spacer(minLength: 4)
                FlagBadge(countryCode: meeting.countryCode).accessibilityHidden(true)
                if let round = meeting.round {
                    Text("R\(round)").font(.caption.monospacedDigit())
                        .foregroundStyle(WebDashboardStyle.homeMuted)
                }
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.name).font(.title2.bold())
                    Text(dateRange(meeting)).font(.caption)
                        .foregroundStyle(WebDashboardStyle.homeMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PulseChevron()
            }
            if let leader {
                Rectangle()
                    .fill(WebDashboardStyle.homeLine)
                    .frame(height: 1)
                    .accessibilityHidden(true)
                HStack(spacing: 10) {
                    AssetImage(name: MotorsportAssetName.helmetName(
                        driverID: leader.driverId, name: leader.driverName, season: meeting.season
                    ))
                    .frame(width: 38, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(leader.driverName).font(.subheadline.weight(.semibold))
                        Text(session.sessionType.webTitle).font(.caption)
                            .foregroundStyle(WebDashboardStyle.homeMuted)
                    }
                    Spacer(minLength: 4)
                    Text("P1")
                        .font(.caption.weight(.bold).monospacedDigit())
                }
            }
        }
        .padding(16)
        .contentShape(.rect)
        .dashboardPanel(WebDashboardStyle.homePanel)
        .accessibilityElement(children: .combine)
    }

    private func meetingRow(_ meeting: Meeting) -> some View {
        let badgeWidth: CGFloat = 30
        return HStack(alignment: .top, spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
                FlagBadge(countryCode: meeting.countryCode, width: badgeWidth, fitsWidth: true)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                if let round = meeting.round {
                    Text("R\(round)")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(WebDashboardStyle.homeMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.vertical, 2)
                        .frame(width: badgeWidth)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(WebDashboardStyle.homeMuted.opacity(0.32))
                        }
                }
            }
            .padding(.top, 3)
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.name).font(.subheadline.weight(.semibold))
                Text(dateRange(meeting)).font(.caption)
                    .foregroundStyle(WebDashboardStyle.homeMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CircuitOutlineView(meetingID: meeting.id, lineWidth: 1.6, showsPlaceholder: false)
                .foregroundStyle(WebDashboardStyle.homeMuted)
                .frame(width: 55, height: 37)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func dateRange(_ meeting: Meeting) -> String {
        guard meeting.endDate > meeting.startDate else {
            return meeting.startDate.formatted(.dateTime.day().month(.abbreviated).locale(.pulseEnglish))
        }
        return (meeting.startDate..<meeting.endDate).formatted(.interval.day().month(.abbreviated))
    }
}

private struct ResultsPodiumPreview: View {
    let weekend: SeasonResultWeekend
    let session: Session

    private var results: [SessionResult] {
        let rows = weekend.sessions[session.sessionType.rawValue]?.rows ?? []
        return rows.filter { (1...3).contains($0.position ?? 0) }
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(session.sessionType == .race || session.sessionType == .sprint ? "Podium" : session.sessionType.resultLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            if let winner = results.first(where: { $0.position == 1 }) {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .accessibilityHidden(true)
                        Text("P1").font(.subheadline.bold())
                        if let time = winner.raceTime ?? winner.time ?? winner.gap ?? winner.bestLap {
                            Text(time).font(.caption.weight(.semibold).monospacedDigit())
                        }
                    }
                    .foregroundStyle(.red)

                    helmet(winner, size: 66)
                    driverName(winner, font: .headline)
                    if let points = winner.points {
                        PulseNumber("\(points.formatted()) pts")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
            }

            let runners = results.filter { $0.position != 1 }
            if !runners.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(runners) { row in
                        VStack(spacing: 4) {
                            helmet(row, size: 49)
                            driverName(row, font: .subheadline.weight(.semibold))
                            HStack(spacing: 4) {
                                if let points = row.points {
                                    PulseNumber("\(points.formatted()) pts")
                                    Text("·").foregroundStyle(.white.opacity(0.4))
                                }
                                if let position = row.position { Text("P\(position)").foregroundStyle(.red) }
                            }
                            .font(.caption.weight(.semibold).monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            if results.isEmpty {
                Text("No podium data").font(.subheadline).padding(.vertical, 16)
            }
        }
        .padding(16)
        .frame(idealWidth: 336)
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.10)],
                                   startPoint: .top, endPoint: .bottom))
    }

    private func helmet(_ row: SessionResult, size: CGFloat) -> some View {
        AssetImage(name: MotorsportAssetName.helmetName(driverID: row.driverId,
            name: row.driverName, season: weekend.meeting.season))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private func driverName(_ row: SessionResult, font: Font) -> some View {
        Text(row.driverName).font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private enum SeasonResultsMode: String, CaseIterable {
    case race = "Race", sprint = "Sprint", combined = "Combined"

    var types: [SessionType] {
        switch self {
        case .race: [.race]
        case .sprint: [.sprint]
        case .combined: [.race, .sprint]
        }
    }

    func rounds(in weekends: [SeasonResultWeekend]) -> [SeasonResultWeekend] {
        weekends.filter { weekend in
            types.contains { weekend.sessions[$0.rawValue]?.rows.isEmpty == false }
        }
    }
}

private struct SeasonResultsStatistics: View {
    let weekends: [SeasonResultWeekend]
    let season: Int
    @State private var showsMatrix = false
    @Namespace private var matrixTransition
    @State private var mode = SeasonResultsMode.race
    @State private var viewportHeight: CGFloat = 0
    @State private var showsPosition = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SeasonLeaders(weekends: weekends, sessions: SeasonResultsMode.combined.types,
                              season: season, sheetMaxHeight: viewportHeight)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    SeasonRoundMatrix(weekends: SeasonResultsMode.race.rounds(in: weekends),
                                      sessions: [.race], season: season, showsPosition: false)
                        .preview
                } else {
                    Button {
                        mode = .race
                        showsPosition = false
                        showsMatrix = true
                    } label: {
                        SeasonRoundMatrix(weekends: SeasonResultsMode.race.rounds(in: weekends),
                                          sessions: [.race], season: season, showsPosition: false)
                            .preview
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Open the round-by-round grid in landscape")
                    .matchedTransitionSource(id: "season-round-matrix", in: matrixTransition)
                }
            }
            .padding(16)
        }
        .foregroundStyle(WebDashboardStyle.homeText)
        .background(WebDashboardStyle.homeBackground)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .navigationTitle("Season Statistics")
        .dashboardDetail()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .fullScreenCover(isPresented: $showsMatrix) {
            LandscapeCover(background: WebDashboardStyle.homeBackground) { close in
                matrixFullscreen(close: close)
            }
            .pulseNavigationZoom("season-round-matrix", in: matrixTransition)
        }
    }

    private func matrixFullscreen(close: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Driver Points and Positions by Round")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                    Text(showsPosition ? "Position" : "Points")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                Menu {
                    Picker("Session type", selection: $mode) {
                        ForEach(SeasonResultsMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } label: {
                    Label(mode.rawValue, systemImage: "chevron.down")
                        .font(.subheadline.weight(.medium))
                }
                .accessibilityLabel("Session type")
                .accessibilityValue(mode.rawValue)
                Button {
                    showsPosition.toggle()
                } label: {
                    Image(systemName: showsPosition ? "list.number" : "number")
                        .frame(width: 38, height: 40)
                        .background(WebDashboardStyle.homeLine, in: .rect(cornerRadius: 10))
                }
                .accessibilityLabel(showsPosition ? "Switch to points" : "Switch to position")
                Button(action: close) {
                    Image(systemName: "xmark")
                        .frame(width: 38, height: 40)
                }
                .accessibilityLabel("Close")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            Divider()
            let rounds = mode.rounds(in: weekends)
            if rounds.isEmpty {
                ContentUnavailableView("No results for this selection", systemImage: "flag.checkered")
            } else {
                SeasonRoundMatrix(weekends: rounds, sessions: mode.types, season: season, showsPosition: showsPosition)
            }
        }
        .foregroundStyle(WebDashboardStyle.homeText)
        .accessibilityAction(.escape, close)
    }
}

private struct SeasonRoundMatrix: View {
    let weekends: [SeasonResultWeekend]
    let sessions: [SessionType]
    let season: Int
    let showsPosition: Bool
    var scrollsVertically = true
    var showsRoundDetails = true
    @State private var selected: RoundScore?
    @ScaledMetric(relativeTo: .caption) private var rowHeight = 44

    private struct RoundScore: Identifiable {
        let weekend: SeasonResultWeekend
        let rows: [SessionResult]

        var id: String { weekend.id }
        var points: Double { rows.reduce(0) { $0 + ($1.points ?? 0) } }
        var classification: SessionResult? { rows.first }
    }

    private struct DriverScore: Identifiable {
        let driver: SessionResult
        let rounds: [String: RoundScore]

        var id: String { driver.driverId }
        var points: Double { rounds.values.reduce(0) { $0 + $1.points } }
    }

    private var standings: [DriverScore] {
        var identities: [String: SessionResult] = [:]
        var scores: [String: [String: RoundScore]] = [:]
        for weekend in weekends {
            let rows = sessions.flatMap { weekend.sessions[$0.rawValue]?.rows ?? [] }
            for (driver, results) in Dictionary(grouping: rows, by: \.driverId) {
                identities[driver] = results.first
                scores[driver, default: [:]][weekend.id] = RoundScore(weekend: weekend, rows: results)
            }
        }
        return identities.map { key, driver in
            DriverScore(driver: driver, rounds: scores[key, default: [:]])
        }.sorted { ($0.points == $1.points) ? $0.driver.driverName < $1.driver.driverName : $0.points > $1.points }
    }

    var preview: some View {
        let drivers = standings.prefix(5)
        let rounds = weekends.suffix(10)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Driver Points and Positions by Round")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                PulseChevron()
            }
            if let first = rounds.first?.meeting.round, let last = rounds.last?.meeting.round {
                Text(first == last ? "R\(last)" : "R\(first)–R\(last)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(WebDashboardStyle.homeMuted)
            }
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Color.clear.frame(width: 24, height: 1)
                    ForEach(rounds) { weekend in
                        PulseNumber(weekend.meeting.round?.formatted() ?? "—")
                            .font(.caption2.monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(WebDashboardStyle.homeMuted)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(drivers) { entry in
                    HStack(spacing: 4) {
                        driverHelmet(entry).frame(width: 24, height: 16)
                        ForEach(rounds) { weekend in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(entry.rounds[weekend.id].map { tint($0).opacity(0.30) } ?? .clear)
                                .frame(maxWidth: .infinity)
                                .frame(height: 14)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .padding(14)
        .contentShape(.rect)
        .dashboardPanel(WebDashboardStyle.homePanel)
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        let drivers = standings
        Group {
            if scrollsVertically {
                ScrollView { matrixRows(drivers) }
            } else {
                matrixRows(drivers)
            }
        }
        .sheet(item: $selected) { score in
            NavigationStack {
                List(score.rows, id: \.sessionId) { row in
                    LabeledContent(score.weekend.meeting.sessions.first { $0.id == row.sessionId }?.sessionType.webTitle ?? "Result") {
                        Text("\(position(row)) · \((row.points ?? 0).formatted()) pts")
                    }
                }
                .safeAreaInset(edge: .top) {
                    Text(score.classification?.driverName ?? "").font(.headline).padding(8)
                }
                .scrollContentBackground(.hidden)
                .background(PulseStyle.background)
                .navigationTitle(score.weekend.meeting.name)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { selected = nil }
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func matrixRows(_ drivers: [DriverScore]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("DRIVER / PTS").foregroundStyle(.secondary).frame(height: rowHeight)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(drivers.enumerated()), id: \.element.id) { rank, entry in
                    HStack(spacing: 5) {
                        Text(String(rank + 1)).foregroundStyle(.secondary).frame(width: 20)
                        driverHelmet(entry).frame(width: 22, height: 20)
                        Text(MotorsportAssetName.abbreviation(entry.driver.driverName))
                            .fontWeight(.semibold).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        PulseNumber(entry.points.formatted()).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(height: rowHeight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(rank + 1), \(entry.driver.driverName), \(entry.points.formatted()) points")
                }
            }
            .frame(width: 120)
            .padding(.trailing, 8)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 4) {
                    ForEach(weekends) { weekend in
                        VStack(spacing: 0) {
                            Text(weekend.meeting.round.map { "R\($0)" } ?? "—")
                                .foregroundStyle(.secondary).frame(height: rowHeight)
                                .accessibilityLabel(weekend.meeting.name)
                            ForEach(drivers) { entry in
                                if let score = entry.rounds[weekend.id] {
                                    let cell = Text(value(score)).fontWeight(.semibold)
                                        .frame(width: 43, height: rowHeight - 4)
                                        .background(tint(score).opacity(0.24), in: .rect(cornerRadius: 4))
                                    Group {
                                        if showsRoundDetails {
                                            Button { selected = score } label: { cell }
                                                .buttonStyle(.plain)
                                        } else {
                                            cell
                                        }
                                    }
                                    .accessibilityLabel("\(entry.driver.driverName), \(weekend.meeting.name)")
                                    .accessibilityValue(value(score))
                                    .frame(height: rowHeight)
                                } else {
                                    Text("—").foregroundStyle(.tertiary).frame(width: 43, height: rowHeight)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.leading)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 12)
    }

    private func driverHelmet(_ entry: DriverScore) -> some View {
        AssetImage(name: MotorsportAssetName.helmetName(driverID: entry.id,
            name: entry.driver.driverName, season: season))
            .accessibilityHidden(true)
    }

    private func position(_ row: SessionResult) -> String {
        row.classification.uppercased() == "CLASSIFIED"
            ? (row.position.map { "P\($0)" } ?? "—") : row.classification.uppercased()
    }

    private func value(_ score: RoundScore) -> String {
        showsPosition ? (score.classification.map(position) ?? "—") : score.points.formatted()
    }

    private func tint(_ score: RoundScore) -> Color {
        guard let row = score.classification else { return .secondary }
        guard row.classification.uppercased() == "CLASSIFIED" else { return PulseStyle.red }
        switch row.position ?? Int.max {
        case 1: return .yellow
        case 2...3: return .teal
        case 4...6: return .blue
        case 7...10: return .indigo
        default: return .secondary
        }
    }
}

private struct SeasonOverviewInsights {
    struct Margin {
        let row: SessionResult
        let seconds: Double
        let meeting: Meeting
    }

    struct Distance {
        let teamID: String
        let row: SessionResult
        var km: Double
    }

    let average: (row: SessionResult, value: Double)?
    let positionsGained: (row: SessionResult, value: Int)?
    let closestMargin: Margin?
    let largestMargin: Margin?
    let comeback: (row: SessionResult, value: Int, meeting: Meeting)?
    let mileage: [Distance]

    init(weekends: [SeasonResultWeekend], sessions: [SessionType]) {
        var finishes: [String: (row: SessionResult, sum: Int, count: Int)] = [:]
        var gains: [String: (row: SessionResult, value: Int)] = [:]
        var distances: [String: Distance] = [:]
        var margins: [Margin] = []
        var bestComeback: (row: SessionResult, value: Int, meeting: Meeting)?

        for weekend in weekends {
            for session in sessions {
                let rows = weekend.sessions[session.rawValue]?.rows ?? []
                if let winner = rows.first(where: { $0.position == 1 }),
                   let runnerUp = rows.first(where: { $0.position == 2 }),
                   let seconds = Self.winningMargin(winner: winner, runnerUp: runnerUp) {
                    margins.append(Margin(row: winner, seconds: seconds, meeting: weekend.meeting))
                }
                for row in rows {
                    if let position = row.position, position > 0 {
                        if row.classification.uppercased() == "CLASSIFIED" {
                            let prior = finishes[row.driverId] ?? (row, 0, 0)
                            finishes[row.driverId] = (prior.row, prior.sum + position, prior.count + 1)
                        }
                        if let grid = row.gridPosition, grid > 0 {
                            let gain = grid - position
                            let prior = gains[row.driverId] ?? (row, 0)
                            gains[row.driverId] = (prior.row, prior.value + gain)
                            if gain > (bestComeback?.value ?? 0) {
                                bestComeback = (row, gain, weekend.meeting)
                            }
                        }
                    }
                    if let length = weekend.meeting.circuit?.lengthKm, length.isFinite, length > 0,
                       let laps = row.laps, laps > 0 {
                        let teamID = row.constructorId.isEmpty ? row.team : row.constructorId
                        distances[teamID, default: Distance(teamID: teamID, row: row, km: 0)].km += Double(laps) * length
                    }
                }
            }
        }

        average = finishes.values.map { ($0.row, Double($0.sum) / Double($0.count)) }
            .min { ($0.1, $0.0.driverId) < ($1.1, $1.0.driverId) }
        positionsGained = gains.values.min { ($0.value == $1.value) ? $0.row.driverId < $1.row.driverId : $0.value > $1.value }
        closestMargin = margins.min { $0.seconds < $1.seconds }
        largestMargin = margins.max { $0.seconds < $1.seconds }
        comeback = bestComeback
        mileage = Array(distances.values.sorted {
            $0.km == $1.km ? $0.teamID < $1.teamID : $0.km > $1.km
        }.prefix(3))
    }

    private static func winningMargin(winner: SessionResult, runnerUp: SessionResult) -> Double? {
        if let gap = runnerUp.gap?.trimmingCharacters(in: .whitespacesAndNewlines),
           gap.range(of: #"^\+?\d+(?::\d+)?(?:\.\d+)?s?$"#, options: .regularExpression) != nil {
            let time = gap.dropFirst(gap.hasPrefix("+") ? 1 : 0).dropLast(gap.hasSuffix("s") ? 1 : 0)
            return AnalysisMath.elapsedSeconds(String(time))
        }
        guard let laps = winner.laps, laps > 0, laps == runnerUp.laps,
              let first = AnalysisMath.elapsedSeconds(winner.raceTime),
              let second = AnalysisMath.elapsedSeconds(runnerUp.raceTime), second > first else { return nil }
        return second - first
    }
}

private func seasonResultTeamColor(_ id: String) -> Color {
    let rgb: UInt32
    switch LiveIslandLogic.assetSlug(id) {
    case "mercedes": rgb = 0x27f4d2
    case "ferrari": rgb = 0xe8002d
    case "mclaren": rgb = 0xff8000
    case "red-bull", "red-bull-racing": rgb = 0x3671c6
    case "williams": rgb = 0x64c4ff
    case "rb", "racing-bulls": rgb = 0x6692ff
    case "aston-martin": rgb = 0x229971
    case "alpine": rgb = 0x0093cc
    case "haas": rgb = 0xb6babd
    case "sauber": rgb = 0x52e252
    case "alfa", "alfa-romeo": rgb = 0xc92d4b
    case "alphatauri": rgb = 0x5e8faa
    case "audi": rgb = 0xf50537
    case "cadillac": rgb = 0xc9b037
    default: return DashboardArt.teamColor(id)
    }
    return WebDashboardStyle.adaptive(dark: rgb, light: rgb)
}

@MainActor @ViewBuilder
private func resultTeamLogo(_ id: String, season: Int, contrast: Bool = false, size: CGFloat = 18) -> some View {
    let name = MotorsportAssetName.name(kind: .teamLogo, id: id, season: season)
    if contrast, ["mercedes", "mclaren"].contains(LiveIslandLogic.assetSlug(id)),
       let image = DashboardArt.image(named: name) {
        Image(uiImage: image).renderingMode(.template).resizable().scaledToFit()
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    } else {
        AssetImage(name: name).frame(width: size, height: size).accessibilityHidden(true)
    }
}

private extension View {
    func seasonResultsPanel() -> some View {
        background(WebDashboardStyle.homePanel, in: PulseStyle.cardShape)
            .clipShape(PulseStyle.cardShape)
            .overlay { PulseStyle.cardShape.strokeBorder(WebDashboardStyle.homeLine).allowsHitTesting(false) }
            .containerShape(PulseStyle.cardShape)
    }
}

private struct SeasonLeaders: View {
    let weekends: [SeasonResultWeekend]
    let sessions: [SessionType]
    let season: Int
    var showsCards = false

    @State private var selectedMetric: Metric?
    var sheetMaxHeight: CGFloat = 0

    private enum Metric: String, CaseIterable, Identifiable {
        case wins = "Wins", podiums = "Podiums", poles = "Poles"
        var id: Self { self }
    }

    private struct Record {
        let id: String
        let name: String
        let team: String
        let value: Int
    }

    private func leader(_ metric: Metric, teams: Bool, sessions: [SessionType]) -> Record? {
        let kinds = sessions.map { session in
            metric == .poles ? (session == .race ? SessionType.qualifying : .sprintQualifying) : session
        }
        let results = weekends.flatMap { weekend in kinds.flatMap { weekend.sessions[$0.rawValue]?.rows ?? [] } }
        let groups = Dictionary(grouping: results) { teams ? $0.constructorId : $0.driverId }
        return groups.compactMap { id, rows in
            guard let row = rows.first else { return nil }
            let value = rows.count { (1...(metric == .podiums ? 3 : 1)).contains($0.position ?? 0) }
            guard value > 0 else { return nil }
            return Record(id: id, name: teams ? row.team : row.driverName, team: row.constructorId, value: value)
        }.min { $0.value == $1.value ? $0.id < $1.id : $0.value > $1.value }
    }

    var body: some View {
        Group {
            if showsCards {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Metric.allCases) { metric in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Most " + metric.rawValue.lowercased())
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 10)
                                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                                .background(WebDashboardStyle.homeBackground, in: .rect)
                            HStack(spacing: 0) {
                                overviewStatCell(metric, teams: false)
                                Rectangle().fill(WebDashboardStyle.homeLine).frame(width: 1)
                                overviewStatCell(metric, teams: true)
                            }
                            .frame(height: 60)
                        }
                        .seasonResultsPanel()
                        .accessibilityElement(children: .contain)
                    }
                }
            } else {
                leaderList
            }
        }
    }

    private func overviewStatCell(_ metric: Metric, teams: Bool) -> some View {
        let best = leader(metric, teams: teams, sessions: sessions)
        let label = teams ? "Constructor" : "Driver"
        let unit = metric.rawValue.lowercased()
        return VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold)).tracking(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                PulseNumber(best?.value.formatted() ?? "—").font(.title3.bold())
                Text(unit).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, best == nil ? 8 : 37)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .bottomTrailing) {
            if let best {
                ZStack {
                    Circle().fill(seasonResultTeamColor(best.team))
                    if teams {
                        resultTeamLogo(best.team, season: season, contrast: true, size: 24)
                    } else {
                        AssetImage(name: MotorsportAssetName.name(kind: .driverPhoto, id: best.id, season: season))
                    }
                }
                .frame(width: 27, height: 27)
                .clipShape(.circle)
                .padding(.trailing, 8).padding(.bottom, 8)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(best?.name ?? "No result"), \(best?.value.formatted() ?? "—") \(unit)")
    }

    private var leaderList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Season Leaders").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(sessions.count > 1 ? "Combined" : sessions.first == .sprint ? "Sprint" : "Race")
                    .font(.caption.weight(.medium)).foregroundStyle(WebDashboardStyle.homeMuted)
            }
            .padding(.bottom, 14)

            HStack(spacing: 8) {
                columnHeading("DRIVER")
                columnHeading("CONSTRUCTOR")
                Color.clear.frame(width: 12, height: 1)
            }
            .padding(.bottom, 8)
            .accessibilityHidden(true)

            ForEach(Metric.allCases) { metric in
                Divider()
                Button { selectedMetric = metric } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(metric.rawValue).font(.subheadline.weight(.semibold))
                            leaderPair(metric, sessions: sessions)
                        }
                        PulseChevron().frame(width: 12)
                    }
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("View race and sprint stats")
            }
        }
        .padding(14)
        .dashboardPanel(WebDashboardStyle.homePanel)
        .sheet(item: $selectedMetric) { metric in
            ResultFittedSheet(maximumHeight: sheetMaxHeight) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(metric.rawValue).font(.headline)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                    ForEach([SeasonResultsMode.race, .sprint], id: \.self) { mode in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(mode.rawValue).font(.subheadline.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                            HStack(spacing: 8) {
                                columnHeading("DRIVER")
                                columnHeading("CONSTRUCTOR")
                            }
                            .accessibilityHidden(true)
                            leaderPair(metric, sessions: mode.types)
                        }
                        .padding(14)
                        .dashboardPanel(WebDashboardStyle.homePanel)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
    }

    private func columnHeading(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(WebDashboardStyle.homeMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func leaderPair(_ metric: Metric, sessions: [SessionType]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            statCell(metric, teams: false, sessions: sessions)
            statCell(metric, teams: true, sessions: sessions)
        }
    }

    var racePreview: some View {
        let leaders = Metric.allCases.map { (metric: $0, record: leader($0, teams: false, sessions: sessions)) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "cellularbars")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(PulseStyle.red)
                    .frame(width: 23, height: 24)
                    .accessibilityHidden(true)
                Text("Season Statistics").font(.subheadline)
                Spacer(minLength: 0)
                Text("Race").font(.caption).foregroundStyle(WebDashboardStyle.homeMuted)
                PulseChevron()
            }
            Divider()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 0) {
                ForEach(leaders, id: \.metric) { metric, best in
                    let count = Text(best?.value.formatted() ?? "—").font(.subheadline.bold().monospacedDigit())
                    VStack(spacing: 6) {
                        Text("\(count) \(metric.rawValue)")
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let best {
                            AssetImage(name: MotorsportAssetName.helmetName(
                                driverID: best.id, name: best.name, season: season
                            ))
                            .frame(width: 42, height: 36)
                            ResultDriverName(name: best.name)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(14)
        .contentShape(.rect)
        .dashboardPanel(WebDashboardStyle.homePanel)
        .accessibilityElement(children: .combine)
        .accessibilityValue(leaders.compactMap { metric, record in
            record.map { "\($0.value.formatted()) \(metric.rawValue), \($0.name)" }
        }.joined(separator: ", "))
    }

    private func statCell(_ metric: Metric, teams: Bool, sessions: [SessionType]) -> some View {
        let best = leader(metric, teams: teams, sessions: sessions)
        return HStack(alignment: .top, spacing: 6) {
            if let best {
                AssetImage(name: teams
                    ? MotorsportAssetName.name(kind: .teamLogo, id: best.team, season: season)
                    : MotorsportAssetName.helmetName(driverID: best.id, name: best.name, season: season))
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                PulseNumber(best?.value.formatted() ?? "—").font(.subheadline.bold()).monospacedDigit()
                if let best {
                    Text(best.name).font(.caption).foregroundStyle(WebDashboardStyle.homeMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(teams ? "Constructor" : "Driver"), \(best?.name ?? "No result"), \(best?.value.formatted() ?? "—")")
    }
}

struct MeetingResultsDashboard: View {
    @ScaledMetric(relativeTo: .caption) private var comparisonValueWidth = 72.0
    let weekend: SeasonResultWeekend
    let initial: Session

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: Session?
    @State private var analysis: WeekendAnalysis?
    @State private var selectedPanel: WeekendResultPanel?
    @State private var driverTrend: DriverTrend?
    @State private var progressViewportHeight: CGFloat = 0
    @State private var excludeProgressOutliers = true
    @State private var progressSessions = Set(SessionType.allCases)
    @State private var progressPointID: String?
    @State private var hoveredProgressPointID: String?

    private enum WeekendAnalysis: Identifiable {
        case grid, progress

        var id: Self { self }
        var title: LocalizedStringKey { self == .grid ? "Grid Position" : "Lap Time Improvement" }
    }

    private var timingSessions: [SessionType] {
        availableSessions.reversed().map(\.sessionType)
    }

    private var availableSessions: [Session] {
        weekend.meeting.sessions
            .filter {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    return $0.id == initial.id || weekend.sessions[$0.sessionType.rawValue] != nil
                }
                return weekend.sessions[$0.sessionType.rawValue]?.rows.isEmpty == false
            }
            .sorted {
                if UIDevice.current.userInterfaceIdiom == .pad { return $0.startTime < $1.startTime }
                return $0.startTime > $1.startTime
            }
    }

    var body: some View {
        let session = selected ?? initial
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        ResultsScreen(session: session, meeting: weekend.meeting, availableSessions: availableSessions,
                      selectSession: { selectedPanel = nil; selected = $0 },
                      selectedPanel: isPad ? selectedPanel : nil, hasStartingGrid: !grid.isEmpty,
                      selectPanel: { selectedPanel = $0 }) {
            if isPad {
                switch selectedPanel {
                case .grid: tabletStartingGrid
                case .progress: tabletProgressChart
                case nil: EmptyView()
                }
            } else {
                analysisEntries
            }
        }
        .id(session.id)
        .transition(.opacity)
        .pulseSwap(session.id)
        .navigationTitle("Race Results")
        .dashboardDetail()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isPad ? .hidden : .visible, for: .navigationBar)
        .sheet(item: Binding(get: { isPad ? driverTrend : nil }, set: { driverTrend = $0 })) { trend in
            if isPad { ResultFittedSheet(maximumHeight: progressViewportHeight) { driverTrendContent(trend) } }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { progressViewportHeight = $0 }
        .sheet(item: $analysis) { tool in
            NavigationStack {
                Group {
                    switch tool {
                    case .grid: startingGrid
                    case .progress: progress
                    }
                }
                .background(WebDashboardStyle.homeBackground)
                .navigationTitle(tool.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark") { analysis = nil }
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder private var analysisEntries: some View {
        let front = grid.filter { (1...3).contains($0.gridPosition ?? 0) }
        let records = trackLaps
        let showGrid = !grid.isEmpty
        let showProgress = !records.isEmpty || !timing.isEmpty
        if showGrid || showProgress {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                if showGrid {
                    analysisEntry(.grid, icon: "flag.checkered") {
                        HStack(spacing: 4) {
                            ForEach(front) { driver in
                                VStack(spacing: 4) {
                                    AssetImage(name: MotorsportAssetName.name(
                                        kind: .driverPhoto, id: driver.driverId, season: weekend.meeting.season
                                    ))
                                    .frame(height: 42)
                                    HStack(spacing: 3) {
                                        AssetImage(name: MotorsportAssetName.name(
                                            kind: .teamLogo, id: driver.constructorId, season: weekend.meeting.season
                                        ))
                                        .frame(width: 12, height: 11)
                                        Text(MotorsportAssetName.abbreviation(driver.driverName))
                                            .font(.caption2.weight(.semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("P\(driver.gridPosition ?? 0), \(driver.driverName), \(driver.team)")
                            }
                        }
                    }
                }
                if showProgress {
                    analysisEntry(.progress, icon: "chart.xyaxis.line") {
                        if records.isEmpty {
                            Text("No Historical Comparison").font(.caption2).foregroundStyle(WebDashboardStyle.homeMuted)
                        } else {
                            trackLapPreview(records)
                        }
                    }
                }
            }
        }
    }

    private func analysisEntry<Preview: View>(
        _ tool: WeekendAnalysis, icon: String, @ViewBuilder preview: () -> Preview
    ) -> some View {
        Button {
            analysis = tool
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(PulseStyle.red).accessibilityHidden(true)
                    Text(tool.title).fontWeight(.semibold)
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                preview()
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .contentShape(.rect)
            .dashboardPanel(WebDashboardStyle.homePanel)
        }
        .buttonStyle(PulsePressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weekend.analysis.\(tool)")
    }

    private func trackLapPreview(_ laps: [TrackLap]) -> some View {
        let scale = LapScale(laps.map { Double($0.record.millis) })
        return VStack(spacing: 4) {
            ForEach(laps) { lap in
                HStack(spacing: 4) {
                    AssetImage(name: recordAsset(lap.record)).frame(width: 17, height: 16)
                    if laps.count > 1 {
                        ResultComparisonBar(fraction: scale.bar(Double(lap.record.millis)),
                                            color: DashboardArt.teamColor(lap.record.team), height: 8)
                            .accessibilityHidden(true)
                    } else {
                        Spacer(minLength: 0)
                    }
                    PulseNumber(lap.record.time).font(.caption2.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(lap.current ? "This Race" : "Historical"), \(lap.record.driverName)")
                .accessibilityValue(lap.record.time)
            }
        }
    }

    private var grid: [SessionResult] {
        (weekend.sessions["race"]?.rows ?? [])
            .filter { $0.gridPosition != nil }
            .sorted { ($0.gridPosition == 0 ? Int.max : $0.gridPosition ?? Int.max) < ($1.gridPosition == 0 ? Int.max : $1.gridPosition ?? Int.max) }
    }

    private var tabletStartingGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("POS.")
                Text("NO.")
                Text("DRIVER")
                Text("TEAM")
                Text("TIME")
            }.font(.caption.bold()).foregroundStyle(WebDashboardStyle.homeMuted)
            Divider()
            ForEach(grid.filter { ($0.gridPosition ?? 0) > 0 }) { row in
                let qualifying = weekend.sessions["qualifying"]?.rows.first { $0.driverId == row.driverId }
                GridRow {
                    Text(row.gridPosition.map(String.init) ?? "—")
                    Text(row.driverNumber ?? "—")
                    Text(row.driverName.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? row.driverName)
                        .accessibilityLabel(row.driverName)
                    HStack(spacing: 7) {
                        AssetImage(name: MotorsportAssetName.name(kind: .teamLogo, id: row.constructorId, season: weekend.meeting.season))
                            .frame(width: 20, height: 16).accessibilityHidden(true)
                        Text(row.team)
                    }
                    Text(qualifying?.q3 ?? qualifying?.q2 ?? qualifying?.q1 ?? "—")
                }.font(.subheadline.monospacedDigit())
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startingGrid: some View {
        let grid = grid
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(grid) { row in
                    if row.id != grid.first?.id { Divider() }
                    HStack(spacing: 10) {
                        Text(row.gridPosition == 0 ? "Pit Lane" : row.gridPosition.map { "P\($0)" } ?? "—")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(PulseStyle.red)
                            .frame(minWidth: 34, alignment: .leading)
                        AssetImage(name: MotorsportAssetName.name(
                            kind: .driverPhoto, id: row.driverId, season: weekend.meeting.season
                        ))
                        .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.driverName).font(.subheadline.weight(.semibold))
                            Text(row.team).font(.caption).foregroundStyle(WebDashboardStyle.homeMuted)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .dashboardPanel(WebDashboardStyle.homePanel)
            .padding(16)
        }
        .foregroundStyle(WebDashboardStyle.homeText)
    }

    private var timing: [Timing] {
        timingSessions.flatMap { session in
            (weekend.sessions[session.rawValue]?.rows ?? []).compactMap { row -> Timing? in
                // Race and sprint time is the total duration. Only archived single laps belong here.
                let candidates = [row.bestLap, row.q1, row.q2, row.q3]
                guard let lap = candidates.compactMap(AnalysisMath.elapsedSeconds).filter({ $0 < 600 }).min()
                else { return nil }
                return Timing(row: row, session: session, lap: lap)
            }
        }
    }

    private var progress: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let records = trackLaps
                if !records.isEmpty {
                    PulseCard { trackRecord(records) }
                }
                progressChart
            }
            .padding(16)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { progressViewportHeight = $0 }
        .sheet(item: $driverTrend) { trend in
            ResultFittedSheet(maximumHeight: progressViewportHeight) {
                driverTrendContent(trend)
            }
        }
    }

    private var tabletProgressChart: some View {
        let sessions: [SessionType] = [.fp1, .fp2, .fp3, .qualifying]
        let available = sessions.filter { weekend.sessions[$0.rawValue] != nil }
        let samples = available.flatMap { session in
            (weekend.sessions[session.rawValue]?.rows ?? []).compactMap { row -> Timing? in
                guard let lap = row.bestLap.flatMap(AnalysisMath.elapsedSeconds), lap.isFinite else { return nil }
                return Timing(row: row, session: session, lap: lap)
            }
        }
        let orderedQualifying = weekend.sessions["qualifying"]?.rows ?? []
        let positions = Dictionary(orderedQualifying.map { ($0.driverId, $0.position ?? 99) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let drivers = samples.filter { seen.insert($0.driver).inserted }.map(\.driver)
        let order = drivers.enumerated().sorted {
            let first = positions[$0.element, default: 99]
            let second = positions[$1.element, default: 99]
            return first == second ? $0.offset < $1.offset : first < second
        }.map(\.element)
        let names = Dictionary(samples.map { ($0.driver, $0.row.driverName) }, uniquingKeysWith: { _, last in last })
        let times = samples.map(\.lap).sorted()
        let limit: Double = {
            guard !times.isEmpty, excludeProgressOutliers else { return .infinity }
            let q1 = times[times.count / 4]
            let q3 = times[times.count * 3 / 4]
            return q3 + 1.5 * (q3 - q1)
        }()
        let low = floor(times.first ?? 0)
        let high = max(low + 1, ceil(times.last { $0 <= limit } ?? low))
        let visible = samples.filter { progressSessions.contains($0.session) && $0.lap <= limit }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ForEach(available, id: \.self) { session in
                    let active = progressSessions.contains(session)
                    Button {
                        if active { progressSessions.remove(session) }
                        else { progressSessions.insert(session) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(tabletProgressColor(session)).frame(width: 8, height: 8)
                            Text(session.webTitle)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .background(WebDashboardStyle.homeBackground, in: .rect(cornerRadius: 6))
                        .opacity(active ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
                Spacer()
                Toggle("Exclude outliers", isOn: $excludeProgressOutliers)
                    .fixedSize()
                    .font(.caption)
            }
            if samples.isEmpty {
                Text("No fastest lap data available.").foregroundStyle(WebDashboardStyle.homeMuted)
            } else {
                Chart(visible) { sample in
                    PointMark(x: .value("Lap time", sample.lap), y: .value("Driver", sample.driver))
                        .symbolSize(44)
                        .foregroundStyle(tabletProgressColor(sample.session))
                        .accessibilityLabel("\(sample.row.driverName), \(sample.session.webTitle)")
                        .accessibilityValue(sample.row.bestLap ?? "")
                }
                .chartXScale(domain: low...high)
                .chartYScale(domain: order)
                .chartXAxis {
                    AxisMarks(values: (0...10).map { low + Double($0) }.filter { $0 <= high }) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: order) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let id = value.as(String.self), let name = names[id] {
                                Text(MotorsportAssetName.abbreviation(name))
                            }
                        }
                    }
                }
                .chartXAxisLabel("Lap time", position: .bottom, alignment: .center)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let anchor = proxy.plotFrame {
                            let frame = geometry[anchor]
                            if let current = visible.first(where: { $0.id == (progressPointID ?? hoveredProgressPointID) }),
                               let y = proxy.position(forY: current.driver) {
                                Rectangle().fill(WebDashboardStyle.homeText.opacity(0.08))
                                    .frame(width: frame.width, height: 24)
                                    .position(x: frame.midX, y: frame.minY + y)
                                    .allowsHitTesting(false)
                            }
                            ForEach(visible) { point in
                                if let x = proxy.position(forX: point.lap), let y = proxy.position(forY: point.driver) {
                                    Button { progressPointID = point.id } label: {
                                        Circle().fill(.clear).frame(width: 14, height: 14).contentShape(.circle)
                                    }
                                    .buttonStyle(.plain)
                                    .onHover { inside in
                                        if inside {
                                            hoveredProgressPointID = point.id
                                        } else if hoveredProgressPointID == point.id {
                                            hoveredProgressPointID = nil
                                        }
                                    }
                                    .accessibilityLabel("\(point.row.driverName), \(point.session.webTitle)")
                                    .accessibilityValue(point.row.bestLap ?? "")
                                    .popover(isPresented: Binding(
                                        get: { progressPointID == point.id },
                                        set: { showing in
                                            if !showing && progressPointID == point.id { progressPointID = nil }
                                        }
                                    ), arrowEdge: .bottom) {
                                        tabletProgressDetails(point, sessions: sessions, samples: samples)
                                            .presentationCompactAdaptation(.popover)
                                    }
                                    .position(x: frame.minX + x, y: frame.minY + y)
                                }
                            }
                            if progressPointID == nil,
                               let hovered = visible.first(where: { $0.id == hoveredProgressPointID }),
                               let x = proxy.position(forX: hovered.lap),
                               let y = proxy.position(forY: hovered.driver) {
                                tabletProgressDetails(hovered, sessions: sessions, samples: samples)
                                    .background(WebDashboardStyle.homePanel, in: .rect(cornerRadius: 10))
                                    .clipShape(.rect(cornerRadius: 10))
                                    .shadow(color: .black.opacity(0.23), radius: 12, y: 4)
                                    .position(
                                        x: min(max(frame.minX + x, 174), max(174, geometry.size.width - 174)),
                                        y: frame.minY + y + (y < 175 ? 98 : -98)
                                    )
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(max(560, order.count * 24 + 80)))
            }
        }
    }

    private func tabletProgressDetails(_ point: Timing, sessions: [SessionType], samples: [Timing]) -> some View {
        let laps = sessions.map { session in
            samples.first { $0.driver == point.driver && $0.session == session }
        }
        let surname = point.row.driverName.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? point.row.driverName
        let text = WebDashboardStyle.adaptive(dark: 0xf7fafc, light: 0x101828)
        let muted = WebDashboardStyle.adaptive(dark: 0xb6c2d4, light: 0x52627a)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text(surname).font(.system(size: 14, weight: .bold))
                Text("(\(MotorsportAssetName.abbreviation(point.row.driverName)))")
                    .font(.system(size: 14)).foregroundStyle(muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            Rectangle().fill(Color(red: 100.0 / 255, green: 116.0 / 255, blue: 139.0 / 255).opacity(0.19))
                .frame(height: 1)
            Grid(alignment: .trailing, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    Text("").frame(width: 42)
                    ForEach(["Lap time", "vs FP1", "vs FP2", "vs FP3"], id: \.self) { heading in
                        Text(heading).lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .fontWeight(.medium).foregroundStyle(muted)
                .padding(.vertical, 8)
                ForEach(Array(sessions.enumerated()), id: \.element) { index, session in
                    GridRow {
                        Text(session == .qualifying ? "Q" : session.resultLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(laps[index]?.row.bestLap ?? "—")
                            .bold().foregroundStyle(tabletProgressColor(session))
                        ForEach(0..<3) { baseline in
                            if index > baseline, let lap = laps[index]?.lap, let reference = laps[baseline]?.lap {
                                let difference = lap - reference
                                Text(String(format: "%+.3fs", difference))
                                    .foregroundStyle(difference < 0
                                                     ? Color(red: 8.0 / 255, green: 163.0 / 255, blue: 68.0 / 255)
                                                     : Color(red: 239.0 / 255, green: 48.0 / 255, blue: 56.0 / 255))
                            } else {
                                Text("—").foregroundStyle(Color(red: 148.0 / 255, green: 163.0 / 255, blue: 184.0 / 255))
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            .font(.system(size: 12).monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .foregroundStyle(text)
        .frame(width: 340)
        .presentationBackground(WebDashboardStyle.homePanel)
    }

    private func tabletProgressColor(_ session: SessionType) -> Color {
        switch session {
        case .fp1: Color(red: 59.0 / 255, green: 130.0 / 255, blue: 246.0 / 255)
        case .fp2: Color(red: 16.0 / 255, green: 185.0 / 255, blue: 129.0 / 255)
        case .fp3: Color(red: 245.0 / 255, green: 158.0 / 255, blue: 11.0 / 255)
        default: Color(red: 239.0 / 255, green: 68.0 / 255, blue: 68.0 / 255)
        }
    }

    private var progressChart: some View {
        let samples = timing
        let timedSessions = Set(samples.map(\.session))
        let selected = samples.filter { progressSessions.contains($0.session) }
        return PulseCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Field Comparison")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button {
                        excludeProgressOutliers.toggle()
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(excludeProgressOutliers ? PulseStyle.red : WebDashboardStyle.homeMuted)
                            .frame(width: 29, height: 29)
                            .background(excludeProgressOutliers ? PulseStyle.red.opacity(0.10) : WebDashboardStyle.homeBackground,
                                        in: Circle())
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide Outlier Laps")
                    .accessibilityAddTraits(excludeProgressOutliers ? .isSelected : [])
                    .accessibilityValue(excludeProgressOutliers ? "On" : "Off")
                }
                ResultSessionOptions(spacing: 2) {
                    ForEach(timingSessions, id: \.self) { session in
                        let available = timedSessions.contains(session)
                        let enabled = available && progressSessions.contains(session)
                        Button {
                            if enabled { progressSessions.remove(session) }
                            else { progressSessions.insert(session) }
                        } label: {
                            let color = progressColor(session)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(enabled ? color : .clear)
                                    .strokeBorder(color.opacity(enabled ? 1 : 0.65), lineWidth: 1)
                                    .frame(width: 7, height: 7)
                                    .accessibilityHidden(true)
                                Text(session.resultLabel)
                                    .foregroundStyle(enabled ? WebDashboardStyle.homeText : WebDashboardStyle.homeMuted)
                            }
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 4)
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .contentShape(.rect)
                            .opacity(available ? 1 : 0.55)
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                        .accessibilityHint(available ? "" : "No Fastest Lap Data")
                        .accessibilityAddTraits(enabled ? .isSelected : [])
                    }
                }
                let missing = timingSessions.filter { !timedSessions.contains($0) }
                if !missing.isEmpty {
                    Text("Fastest lap unavailable: \(missing.map(\.resultLabel).joined(separator: "、"))")
                        .font(.caption)
                        .foregroundStyle(WebDashboardStyle.homeMuted)
                }
                fieldProgress(selected)
            }
        }
    }

    @ViewBuilder private func fieldProgress(_ samples: [Timing]) -> some View {
        let times = samples.map(\.lap).sorted()
        let upperLimit: Double? = {
            guard times.count >= 4 else { return nil }
            let lowerQuartile = times[times.count / 4]
            let upperQuartile = times[times.count * 3 / 4]
            return upperQuartile + (upperQuartile - lowerQuartile) * 1.5
        }()
        let points = samples.filter { !excludeProgressOutliers || $0.lap <= (upperLimit ?? .infinity) }
        let groups = Dictionary(grouping: points, by: \.driver)
        let ranked = groups.values.compactMap { $0.min { $0.lap < $1.lap } }.sorted {
            ($0.lap, $0.driver) < ($1.lap, $1.driver)
        }
        if let fastest = ranked.first?.lap, let slowest = points.map(\.lap).max() {
            let scale = LapScale(points.map(\.lap))
            HStack {
                Text(AnalysisMath.duration(fastest))
                Spacer()
                Text(AnalysisMath.duration(slowest))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(WebDashboardStyle.homeMuted)
            .padding(.leading, 48 + ResultComparisonRow<EmptyView>.codeWidth)
            .padding(.trailing, 8 + min(comparisonValueWidth, 120))
            VStack(spacing: 2) {
                ForEach(ranked) { best in
                    let driverPoints = groups[best.driver, default: []]
                    Button {
                        driverTrend = DriverTrend(driver: best.row, points: driverPoints)
                    } label: {
                        ResultComparisonRow(
                            asset: helmet(best.row, season: weekend.meeting.season),
                            name: best.row.driverName,
                            value: AnalysisMath.duration(best.lap),
                            code: MotorsportAssetName.abbreviation(best.row.driverName)
                        ) {
                            GeometryReader { geometry in
                                let span = max(0, geometry.size.width - 8)
                                Capsule()
                                    .fill(WebDashboardStyle.homeLine)
                                    .frame(height: 2)
                                    .frame(maxHeight: .infinity, alignment: .center)
                                ForEach(driverPoints) { point in
                                    Circle()
                                        .fill(progressColor(point.session))
                                        .frame(width: 8, height: 8)
                                        .position(x: 4 + span * scale.position(point.lap), y: geometry.size.height / 2)
                                }
                            }
                            .frame(height: 18)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("progress.driver.\(best.driver)")
                    .accessibilityHint("Open this driver's lap trend")
                }
            }
            .background {
                GeometryReader { geometry in
                    let span = max(0, geometry.size.width - 8)
                    Path { path in
                        for time in Set([fastest, slowest]) {
                            let x = 4 + span * scale.position(time)
                            path.move(to: CGPoint(x: x, y: -6))
                            path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                        }
                    }
                    .stroke(WebDashboardStyle.homeLine, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .padding(.leading, 48 + ResultComparisonRow<EmptyView>.codeWidth)
                .padding(.trailing, 8 + min(comparisonValueWidth, 120))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            Text("Colors identify sessions. The right column shows each driver's fastest lap for the current filter.")
                .font(.caption)
                .foregroundStyle(WebDashboardStyle.homeMuted)
        } else {
            ContentUnavailableView("No lap times for this filter", systemImage: "stopwatch")
        }
    }

    private func driverTrendContent(_ trend: DriverTrend) -> some View {
        let scale = LapScale(trend.points.map(\.lap))
        return VStack(spacing: 12) {
            HStack {
                Text("Driver Lap Trend")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close", systemImage: "xmark") { driverTrend = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .frame(minWidth: 44, minHeight: 44)
            }
            PulseCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        AssetImage(name: helmet(trend.driver, season: weekend.meeting.season))
                            .frame(width: 44, height: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(trend.driver.driverName)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            Text(trend.driver.team)
                                .font(.caption)
                                .foregroundStyle(WebDashboardStyle.homeMuted)
                        }
                    }
                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(trend.points) { point in
                            GridRow {
                                Label {
                                    Text(point.session.resultLabel).font(.caption)
                                } icon: {
                                    Circle().fill(progressColor(point.session)).frame(width: 7, height: 7)
                                }
                                ResultComparisonBar(fraction: scale.bar(point.lap), color: progressColor(point.session))
                                    .accessibilityHidden(true)
                                Text(AnalysisMath.duration(point.lap))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .gridColumnAlignment(.trailing)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Text("Shorter bars indicate faster laps.")
                        .font(.caption)
                        .foregroundStyle(WebDashboardStyle.homeMuted)
                }
            }
        }
        .padding(16)
    }

    private func progressColor(_ session: SessionType) -> Color {
        switch session {
        case .fp1: .blue
        case .fp2: .teal
        case .fp3: .orange
        case .sprintQualifying: .purple
        case .sprint: .mint
        case .qualifying: .pink
        case .race: PulseStyle.red
        }
    }

    private var trackLaps: [TrackLap] {
        guard let records = weekend.fastestLaps else { return [] }
        let current = TrackLap(current: true, record: records.weekend)
        let history = records.previous.map { [TrackLap(current: false, record: $0)] } ?? []
        return ([current] + history).filter { $0.record.millis > 0 }
    }

    private func trackRecord(_ laps: [TrackLap]) -> some View {
        let scale = LapScale(laps.map { Double($0.record.millis) })
        return VStack(alignment: .leading, spacing: 8) {
            Text("Circuit Fastest Lap Comparison").font(.headline)
            ForEach(laps) { lap in
                let record = lap.record
                ResultComparisonRow(
                    asset: recordAsset(record),
                    name: record.driverName,
                    value: record.time,
                    detail: "\(lap.current ? "This Race" : "Historical") · \(record.year)"
                ) {
                    if laps.count > 1 {
                        ResultComparisonBar(fraction: scale.bar(Double(record.millis)),
                                            color: DashboardArt.teamColor(record.team))
                    }
                }
            }
            if let current = laps.first(where: \.current), let previous = laps.first(where: { !$0.current }) {
                let delta = Double(current.record.millis - previous.record.millis) / 1_000
                Text("vs. historical best \(delta.formatted(.number.sign(strategy: .always()).precision(.fractionLength(3)))) s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(WebDashboardStyle.homeMuted)
            }
        }
    }

    private func recordAsset(_ lap: SeasonResultWeekend.FastestLaps.Record) -> String {
        let rows = weekend.sessions.values.lazy.flatMap(\.rows)
        let driver = rows.first { $0.driverName == lap.driverName }
        let helmet = MotorsportAssetName.helmetName(driverID: driver?.driverId, name: lap.driverName, season: lap.year)
        if DashboardArt.image(named: helmet) != nil { return helmet }

        let team = LiveIslandLogic.assetSlug(lap.team)
        let constructor = rows.first { LiveIslandLogic.assetSlug($0.team) == team }?.constructorId
            ?? team.replacingOccurrences(of: "-", with: "_")
        let logo = MotorsportAssetName.name(kind: .teamLogo, id: constructor, season: lap.year)
        if DashboardArt.image(named: logo) != nil { return logo }
        return MotorsportAssetName.name(kind: .teamLogo, id: constructor, season: weekend.meeting.season)
    }

    private func helmet(_ row: SessionResult, season: Int) -> String {
        MotorsportAssetName.helmetName(driverID: row.driverId, name: row.driverName, season: season)
    }

    private struct TrackLap: Identifiable {
        let current: Bool
        let record: SeasonResultWeekend.FastestLaps.Record
        var id: Bool { current }
    }

    private struct DriverTrend: Identifiable {
        let driver: SessionResult
        let points: [Timing]
        var id: String { driver.driverId }
    }

    private struct Timing: Identifiable {
        let row: SessionResult
        let session: SessionType
        let lap: Double
        var driver: String { row.driverId }
        var id: String { "\(driver)-\(session.rawValue)" }
    }
}

private struct LapScale {
    private let median: Double
    private let lower: Double
    private let upper: Double

    init(_ values: [Double]) {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.isEmpty {
            median = 1
        } else if sorted.count.isMultiple(of: 2) {
            median = (sorted[middle - 1] + sorted[middle]) / 2
        } else {
            median = sorted[middle]
        }
        lower = sorted.first ?? median
        upper = sorted.last ?? median
    }

    func bar(_ value: Double) -> Double {
        0.64 + 0.32 * offset(value)
    }

    func position(_ value: Double) -> Double {
        let start = offset(lower)
        let end = offset(upper)
        return end > start ? (offset(value) - start) / (end - start) : 0.5
    }

    // Keep the ordering and give differences near the median more room than outliers.
    private func offset(_ value: Double) -> Double {
        let delta = value - median
        return delta / (abs(delta) + max(median * 0.04, 0.001))
    }
}
