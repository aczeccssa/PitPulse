import SwiftUI
import UIKit
import SharedComponents
import SharedData

struct WebHomeScreen<Header: View>: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var homeFeatures: EngineeringReport<HomeFeatures>?
    @State private var constructors: APIEnvelope<[ConstructorStanding]>?
    @State private var loadingConstructors = true
    @State private var expandedCountdown: NextSession?
    @Namespace private var countdownTransition
    let header: Header
    @Binding var showCalendar: Bool
    let openResultsSession: (Meeting, Session) -> Void
    let openTab: (DashboardTab) -> Void

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                let isPad = UIDevice.current.userInterfaceIdiom == .pad
                let gap: CGFloat = isPad || viewport.size.width <= 600 ? 12 : 16
                let columns = typeSize.isAccessibilitySize || viewport.size.width < 490
                    ? 1 : viewport.size.width >= 900 ? 4 : 2
                let halfWidth = max(0, (viewport.size.width - 3 * gap) / 2)
                ScrollView {
                    VStack(spacing: gap) {
                        if isPad {
                            tabletOverview(halfWidth: halfWidth, columns: columns, spacing: gap)
                        } else {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let current = schedule(at: context.date)
                                let wide = UIDevice.current.userInterfaceIdiom == .pad
                                    && viewport.size.width >= 760 && !typeSize.isAccessibilitySize
                                    && current.active != nil
                                let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: gap))
                                                  : AnyLayout(VStackLayout(spacing: gap))
                                layout {
                                    Group {
                                        if meetings.isEmpty && model.loadState.isLoading {
                                            PulseSkeleton(rows: 3, label: "Loading race schedule")
                                        } else if let active = current.active, active.session.startTime > context.date {
                                            Button {
                                                expandedCountdown = active
                                            } label: {
                                                countdown(active, now: context.date)
                                            }
                                                .buttonStyle(.plain)
                                                .contentShape(PulseStyle.cardShape)
                                                .accessibilityIdentifier("home.countdown.open")
                                                .accessibilityHint("Opens the full-screen countdown")
                                        } else {
                                            countdown(current.active, now: context.date)
                                        }
                                    }
                                    .matchedTransitionSource(id: "home-countdown", in: countdownTransition)
                                    .frame(maxWidth: .infinity)
                                    if let meeting = current.active?.meeting {
                                        sessionTimes(meeting, active: current.active?.session.id, now: context.date)
                                    }
                                }
                            }
                            if typeSize.isAccessibilitySize {
                                schedulePanel(stretch: false)
                                lovedDriverPanel(stretch: false)
                            } else {
                                Grid(alignment: .topLeading, horizontalSpacing: gap) {
                                    GridRow {
                                        schedulePanel(stretch: true)
                                        lovedDriverPanel(stretch: true)
                                    }
                                }
                            }
                        }
                        let drivers = model.driverRoster.map(StandingEntry.init(driver:))
                        let teams = (constructors?.data ?? []).map(StandingEntry.init(team:))
                        if isPad, columns == 4 {
                            Grid(alignment: .topLeading, horizontalSpacing: gap) {
                                GridRow {
                                    Grid(alignment: .topLeading, horizontalSpacing: gap) {
                                        GridRow {
                                            let standingsWidth = (halfWidth - gap) / 2
                                            homeStandings(drivers, teams: false, stretch: true).frame(width: standingsWidth)
                                            homeStandings(teams, teams: true, stretch: true).frame(width: standingsWidth)
                                        }
                                    }
                                    .frame(width: halfWidth)
                                    homeRecords(stretch: true).frame(width: halfWidth)
                                }
                            }
                        } else {
                            let layout = viewport.size.width > 600 && !typeSize.isAccessibilitySize
                                ? AnyLayout(HStackLayout(alignment: .top, spacing: gap))
                                : AnyLayout(VStackLayout(spacing: gap))
                            layout {
                                homeStandings(drivers, teams: false)
                                homeStandings(teams, teams: true)
                            }
                            homeRecords()
                        }
                    }
                    .padding(gap)
                    .pulseSwap(model.loadState.isLoading)
                    .pulseSwap(model.seasonArchive != nil)
                    .animation(isPad && !reduceMotion ? .snappy(duration: 0.26) : nil, value: columns)
                    .animation(isPad && !reduceMotion ? .snappy(duration: 0.26) : nil,
                               value: viewport.size.width > 600 && !typeSize.isAccessibilitySize)
                }
                .scrollIndicators(.hidden)
            }
            .foregroundStyle(WebDashboardStyle.homeText)
            .background(WebDashboardStyle.homeBackground)
            .dashboardHeader(header)
            .navigationDestination(isPresented: $showCalendar) {
                CalendarScreen()
            }
            .fullScreenCover(isPresented: Binding(
                get: { expandedCountdown != nil },
                set: { if !$0 { expandedCountdown = nil } }
            )) {
                if let target = expandedCountdown {
                    GeometryReader { geometry in
                        let size = geometry.size
                        let portrait = UIDevice.current.userInterfaceIdiom != .pad && size.height > size.width
                        HomeCountdownFullscreen(
                            title: "\(place(target.meeting)): \(target.session.sessionType.webTitle)",
                            start: target.session.startTime,
                            close: { expandedCountdown = nil }
                        )
                        .frame(width: portrait ? size.height : size.width, height: portrait ? size.width : size.height)
                        .rotationEffect(.degrees(portrait ? 90 : 0))
                        .position(x: size.width / 2, y: size.height / 2)
                    }
                    .ignoresSafeArea()
                    .presentationBackground(homeCountdownGradient)
                    .persistentSystemOverlays(.hidden)
                    .statusBarHidden()
                    .environment(\.colorScheme, .dark)
                    .pulseNavigationZoom("home-countdown", in: countdownTransition)
                }
            }
            .task(id: model.dataContext) {
                homeFeatures = nil
                constructors = nil
                loadingConstructors = true
                async let overview: Void = loadHomeFeatures()
                await load()
                await overview
            }
            .refreshable {
                async let calendar: Void = model.loadCalendar(force: true)
                async let roster: Void = model.loadF1Roster(force: true)
                async let overview: Void = loadHomeFeatures()
                await load(force: true)
                await overview
                _ = await (calendar, roster)
            }
        }
    }

    private func loadHomeFeatures() async {
        guard UIDevice.current.userInterfaceIdiom == .pad, let url = model.serverURL else { return }
        let context = model.dataContext
        let report = try? await APIClient(baseURL: url).homeFeatures(season: model.season, token: model.currentToken)
        guard !Task.isCancelled, context == model.dataContext else { return }
        homeFeatures = report
    }

    private func tabletOverview(halfWidth: CGFloat, columns: Int, spacing: CGFloat) -> some View {
        let columnWidth = max(0, (halfWidth - spacing) / 2)
        return Group {
            if columns == 4 {
                HStack(alignment: .top, spacing: spacing) {
                    HStack(alignment: .top, spacing: spacing) {
                        VStack(spacing: spacing) {
                            tabletCountdown
                            tabletSchedule
                        }
                        .frame(width: columnWidth)
                        tabletWeekend(compact: true, minimumHeight: 292)
                            .frame(width: columnWidth)
                    }
                    .frame(width: halfWidth)
                    tabletSeasonMetrics(minimumHeight: 292)
                        .frame(width: halfWidth)
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
                    tabletCountdown
                    tabletSchedule
                }
                tabletSeasonMetrics(minimumHeight: 0)
                tabletWeekend(compact: columns == 1, minimumHeight: 0)
            }
        }
    }

    private var tabletCountdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let current = schedule(at: timeline.date)
            Button {
                if let active = current.active {
                    openResultsSession(active.meeting, active.session)
                } else if let meeting = current.display,
                          let race = meeting.sessions.first(where: { $0.sessionType == .race }) {
                    openResultsSession(meeting, race)
                } else {
                    openTab(.results)
                }
            } label: {
                countdown(current.active, now: timeline.date, minHeight: 140)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.countdown.results")
        }
    }

    private func tabletWeekend(compact: Bool, minimumHeight: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let current = schedule(at: timeline.date)
            if let meeting = current.active?.meeting ?? current.display {
                HomeWeekendSchedule(meeting: meeting, active: current.active?.session.id, now: timeline.date,
                                    compact: compact, minimumHeight: minimumHeight)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weekend Schedule").font(.headline)
                    Text("Schedule unavailable").font(.subheadline).foregroundStyle(.secondary)
                }
                .webHomePanel(minHeight: minimumHeight)
            }
        }
    }

    private var tabletSchedule: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let meeting = schedule(at: timeline.date).display
            let races = meetings.filter { $0.status == .scheduled }
            let completed = Set((model.seasonArchive?.data ?? []).filter {
                $0.sessions["race"]?.rows.isEmpty == false
            }.map(\.id))
            let finished = races.filter { completed.contains($0.id) }.count
            let percent = races.isEmpty ? 0 : Int((100 * Double(finished) / Double(races.count)).rounded())
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(String(model.season)) Schedule")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 6) {
                        if let meeting {
                            FlagBadge(countryCode: meeting.countryCode, width: 24, height: 14)
                                .accessibilityHidden(true)
                        }
                        Text(meeting.map(place) ?? "No schedule")
                            .font(.title3.bold())
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    if !races.isEmpty {
                        HStack(spacing: 6) {
                            HStack(spacing: 1) {
                                ForEach(races) { race in
                                    Capsule().fill(completed.contains(race.id) ? PulseStyle.red : WebDashboardStyle.homeMuted.opacity(0.30))
                                }
                            }
                            .frame(maxWidth: 80)
                            .frame(height: 8)
                            Text("\(percent)%")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(WebDashboardStyle.homeMuted)
                                .fixedSize()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Season progress")
                        .accessibilityValue("\(percent)%")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let meeting {
                    CircuitOutlineView(meetingID: meeting.id, animated: true)
                        .id(meeting.id)
                        .frame(width: 86, height: 90)
                        .accessibilityHidden(true)
                }
            }
            .webHomePanel(inset: 16, minHeight: 140)
        }
    }

    private func tabletSeasonMetrics(minimumHeight: CGFloat) -> some View {
        let data = homeFeatures?.data
        let stops = Array((data?.pitStop ?? []).prefix(3))
        let currency = FloatingPointFormatStyle<Double>.Currency(code: "USD").precision(.fractionLength(0))
        let lastDamage = data?.crashes?.lastRound.map { $0.formatted(currency) }
        let lastUpgrades = data?.tech?.lastRace.map { "\($0.formatted()) new" }
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(String(model.season)) Season Metrics")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            pitStopLeaders(stops)
            Divider()
            VStack(spacing: 0) {
                tabletMetric("Crash Damage", symbol: "exclamationmark.triangle",
                             value: engineeringValue("crashes", data?.crashes?.seasonTotal?.formatted(currency)),
                             note: roundNote(data?.crashes?.latestRound, detail: lastDamage) ?? "Estimated season total")
                Divider()
                tabletMetric("PU Elements Used", symbol: "engine.combustion",
                             value: engineeringValue("pu", data?.pu?.total?.formatted()),
                             note: "Season allocation")
                Divider()
                tabletMetric("Tech Upgrades", symbol: "wrench.and.screwdriver",
                             value: engineeringValue("tech", data?.tech?.total?.formatted()),
                             note: roundNote(data?.tech?.latestRound, detail: lastUpgrades))
            }
        }
        .webHomePanel(minHeight: minimumHeight)
        .accessibilityIdentifier("home.seasonMetrics")
    }

    private func pitStopLeaders(_ stops: [HomeFeatures.PitStop]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Fastest Pit Stops", systemImage: "stopwatch")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                if stops.count > 1 {
                    Text("Best by race").font(.caption2).foregroundStyle(WebDashboardStyle.homeMuted)
                }
            }
            if stops.isEmpty {
                Text("Data unavailable").font(.caption).foregroundStyle(WebDashboardStyle.homeMuted)
            } else {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                layout {
                    ForEach(stops.indices, id: \.self) { index in
                        pitStopEntry(stops[index], rank: index + 1, abbreviated: stops.count > 1 && !typeSize.isAccessibilitySize)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func pitStopEntry(_ stop: HomeFeatures.PitStop, rank: Int, abbreviated: Bool) -> some View {
        let name = stop.driverName ?? "Unknown driver"
        let surname = name.split(separator: " ").last.map(String.init)
        let driverID = model.driverRoster.first { $0.driverName.caseInsensitiveCompare(name) == .orderedSame }?.driverId
        let helmet = MotorsportAssetName.driverAvatarName(driverID: driverID, name: name, season: model.season)
        return HStack(spacing: 6) {
            AssetImage(name: helmet)
                .frame(width: abbreviated ? 29 : 44, height: abbreviated ? 32 : 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(abbreviated ? (surname ?? name).capitalized : name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityLabel(name)
                HStack(spacing: 4) {
                    PulseNumber(stop.time.formatted(.number.precision(.fractionLength(2))) + " s")
                        .font(.caption.weight(.semibold).monospacedDigit())
                    if abbreviated, let round = stop.round {
                        Text("R\(round)").foregroundStyle(WebDashboardStyle.homeMuted)
                    } else if !abbreviated {
                        Text([stop.team, stop.country].compactMap { $0 }.joined(separator: " · "))
                            .foregroundStyle(WebDashboardStyle.homeMuted)
                            .lineLimit(1)
                    }
                }
            }
            if abbreviated {
                Spacer(minLength: 0)
            } else if let round = stop.round {
                Spacer(minLength: 4)
                Text("R\(round)").foregroundStyle(WebDashboardStyle.homeMuted)
            }
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Rank \(rank)")
    }

    private func tabletMetric(_ title: String, symbol: String, value: String?, note: String?) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(WebDashboardStyle.homeMuted)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                if let detail = value == nil ? "Data unavailable" : note {
                    Text(detail).font(.caption2).foregroundStyle(WebDashboardStyle.homeMuted)
                }
            }
            Spacer(minLength: 4)
            PulseNumber(value ?? "—")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
    }

    private func roundNote(_ round: Int?, detail: String?) -> String? {
        guard let detail else { return nil }
        return round.map { "R\($0) · \(detail)" } ?? detail
    }

    private func engineeringValue(_ key: String, _ value: String?) -> String? {
        homeFeatures?.meta?.sections?[key]?.unavailable == true ? nil : value
    }

    private var meetings: [Meeting] {
        model.meetings.filter { $0.round != nil }
            .sorted { ($0.round ?? 0) < ($1.round ?? 0) }
    }

    private func schedule(at now: Date) -> (active: NextSession?, display: Meeting?) {
        let sessions = meetings.filter { $0.status == .scheduled }.flatMap { meeting in
            meeting.sessions.filter {
                ($0.status == .scheduled || $0.status == .live) &&
                    ($0.endTime ?? $0.startTime.addingTimeInterval(7200)) > now
            }.map { NextSession(meeting: meeting, session: $0) }
        }.sorted { $0.session.startTime < $1.session.startTime }
        let nextPublished = meetings.first {
            $0.hasPublishedWeekendDatesOnly && $0.status == .scheduled && $0.endDate >= now
        }
        return (sessions.first, sessions.first?.meeting ?? nextPublished ?? meetings.last)
    }

    private func countdown(_ active: NextSession?, now: Date, minHeight: CGFloat = 126) -> some View {
        VStack(alignment: .leading, spacing: 14) {
                if let active {
                    Text("\(place(active.meeting)): \(active.session.sessionType.webTitle)")
                        .font(.headline)
                    if active.session.startTime <= now {
                        Text("Session underway").font(.system(size: 21, weight: .bold))
                        Text(active.session.startTime, format: .dateTime.day().month().year().hour().minute())
                            .font(.system(size: 12))
                    } else {
                        let units = HomeCountdownTime(start: active.session.startTime, now: now)
                        HStack(spacing: 6) {
                            ForEach(units.fields, id: \.0) { label, value in
                                VStack(spacing: 4) {
                                    PulseNumber(String(format: "%02d", value)).font(.title.bold()).monospacedDigit()
                                        .minimumScaleFactor(0.55).lineLimit(1)
                                    Text(label).font(.caption2).lineLimit(1)
                                }.frame(maxWidth: .infinity)
                            }
                        }.accessibilityLabel(units.accessibilityLabel)
                    }
                } else {
                    Text("\(String(model.season)) Season").font(.headline)
                    Text(meetings.isEmpty ? "Schedule unavailable" : meetings.contains(where: \.hasPublishedWeekendDatesOnly) ? "Session times pending" : "Season complete")
                        .font(.system(size: 21, weight: .bold))
                    Text(meetings.isEmpty || meetings.contains(where: \.hasPublishedWeekendDatesOnly) ? "No sessions have been published." : "Explore this season’s results and records.")
                        .font(.system(size: 12))
                }
            }.foregroundStyle(.white)
                .webHomePanel(fill: homeCountdownGradient, line: Color(red: 0.81, green: 0.61, blue: 0.61), minHeight: minHeight)
    }

    private func sessionTimes(_ meeting: Meeting, active: Session.ID?, now: Date) -> some View {
        HomeWeekendSchedule(meeting: meeting, active: active, now: now)
            .id(model.dataContext + meeting.id)
    }

    private func schedulePanel(stretch: Bool) -> some View {
        Button { showCalendar = true } label: {
            scheduleSummary(stretch: stretch)
        }
        .buttonStyle(PulsePressStyle())
        .accessibilityHint("Opens the race calendar")
        .accessibilityIdentifier("home.schedule.open")
    }

    private func scheduleSummary(stretch: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let display = schedule(at: context.date).display
            VStack(alignment: .leading, spacing: 12) {
                Text("\(String(model.season)) Schedule").font(.headline)
                HStack(spacing: 6) {
                    if let display {
                        FlagBadge(countryCode: display.countryCode, width: 34, height: 18).accessibilityHidden(true)
                    }
                    Text(display.map(place) ?? "No schedule").font(.system(size: 20, weight: .bold))
                }
                if let display {
                    CircuitOutlineView(meetingID: display.id, animated: true)
                        .id(display.id)
                        .frame(width: 96, height: 74)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            .webHomePanel(stretch: stretch)
        }
    }

    private func lovedDriverPanel(stretch: Bool) -> some View {
        NavigationLink {
            FavoriteDriverScreen()
                .dashboardDetail()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("My Driver").font(.headline)
                    Spacer(minLength: 0)
                    Image(systemName: "heart.fill")
                        .font(.caption).foregroundStyle(PulseStyle.red).accessibilityHidden(true)
                }
                if let driver = model.favoriteStanding {
                    HStack(spacing: 7) {
                        AssetImage(name: MotorsportAssetName.driverAvatarName(driverID: driver.id, name: driver.driverName, season: driver.season))
                            .frame(width: 36, height: 36).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            let abbreviation = MotorsportAssetName.abbreviation(driver.driverName)
                            Text(driver.driverNumber.map { "#\($0) \(abbreviation)" } ?? abbreviation)
                                .font(.subheadline.bold())
                                .monospacedDigit()
                                .lineLimit(1)
                                .accessibilityLabel(driver.driverName)
                            Text(driver.constructor).font(.caption2).foregroundStyle(WebDashboardStyle.homeMuted).lineLimit(2)
                        }
                    }
                    if stretch { Spacer(minLength: 0) }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        PulseNumber(driver.points.formatted(.number.precision(.fractionLength(0...2))))
                            .font(.system(.title, design: .rounded).bold()).monospacedDigit()
                            .foregroundStyle(PulseStyle.red)
                        Text("pts").font(.caption).foregroundStyle(WebDashboardStyle.homeMuted)
                    }
                    HStack(spacing: 4) {
                        Text(driver.position == 1 ? "Lead over P2" : "Gap to leader")
                            .foregroundStyle(WebDashboardStyle.homeMuted)
                        Spacer(minLength: 0)
                        PulseNumber(lovedDriverGap(driver)).fontWeight(.bold).monospacedDigit()
                    }.font(.caption2)
                } else {
                    Text(model.favoriteDriverID == nil ? "Choose a driver" : "Standings unavailable")
                        .font(.subheadline).foregroundStyle(WebDashboardStyle.homeMuted)
                }
            }
            .webHomePanel(stretch: stretch)
            .contentShape(PulseStyle.cardShape)
        }.buttonStyle(PulsePressStyle()).accessibilityIdentifier("home.lovedDriver")
    }

    private func lovedDriverGap(_ driver: DriverStanding) -> String {
        let leads = driver.position == 1
        guard let rival = model.driverRoster.first(where: { $0.position == (leads ? 2 : 1) }) else { return "—" }
        let gap = max(0, leads ? driver.points - rival.points : rival.points - driver.points)
        let amount = gap.formatted(.number.precision(.fractionLength(0...2)))
        return gap == 0 ? amount : (leads ? "+" : "−") + amount
    }

    @ViewBuilder private func homeRecords(stretch: Bool = false) -> some View {
        if model.seasonArchive == nil && model.seasonArchiveError == nil {
            PulseSkeleton(rows: 3, label: "Loading race highlights")
        } else {
            WebHomeRecords(weekends: model.seasonArchive?.data ?? [], season: model.season, stretch: stretch) {
                openTab(.results)
            }
        }
    }

    private func homeStandings(_ entries: [StandingEntry], teams: Bool, stretch: Bool = false) -> some View {
        let loading = entries.isEmpty && (teams ? loadingConstructors : model.serverURL != nil && model.rosterLoadError == nil)
        return Group {
            if loading {
                PulseSkeleton(label: teams ? "Loading constructor standings…" : "Loading driver standings…")
            } else {
                standings(entries, teams: teams, stretch: stretch)
            }
        }
        .pulseSwap(loading)
    }

    private func standings(_ entries: [StandingEntry], teams: Bool, stretch: Bool) -> some View {
        let name = teams ? "Constructor" : "Driver"
        let limit = UIDevice.current.userInterfaceIdiom == .pad ? 6 : 3
        let sorted = Array(entries.sorted { $0.position < $1.position }.prefix(limit))
        return Button { openTab(teams ? .constructors : .drivers) } label: {
          VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(String(model.season)) \(name) Standings")
                        .font(.headline)
                    Spacer(minLength: 8)
                }.padding(16).contentShape(.rect)
            Grid(horizontalSpacing: 10, verticalSpacing: 0) {
                GridRow {
                    Text("POS.")
                    Text(name.uppercased()).frame(maxWidth: .infinity, alignment: .leading)
                    Text("POINTS").gridColumnAlignment(.trailing)
                }.font(.system(size: 11, weight: .semibold)).foregroundStyle(WebDashboardStyle.homeMuted).frame(height: 36)
                ForEach(sorted, id: \.id) { row in
                    Rectangle().fill(WebDashboardStyle.homeLine).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        PulseNumber(row.position.formatted())
                        HStack(spacing: 8) {
                            AssetImage(name: teams ? MotorsportAssetName.name(kind: .teamLogo, id: row.colorID, season: row.season) : row.asset)
                                .frame(width: 26, height: 24)
                            Text(row.name).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        PulseNumber(row.points.formatted()).fontWeight(.bold)
                    }.font(.system(size: 14)).frame(minHeight: 42)
                }
            }.padding(.horizontal, 12)
            if sorted.isEmpty {
                Text("No standings available for this season.").font(.system(size: 13))
                    .foregroundStyle(WebDashboardStyle.homeMuted).padding(16)
            }
            Color.clear.frame(height: 8).accessibilityHidden(true)
          }.webHomePanel(inset: 0, minHeight: 0, stretch: stretch).contentShape(PulseStyle.cardShape)
        }.buttonStyle(PulsePressStyle()).accessibilityIdentifier(teams ? "home.constructors" : "home.drivers")
    }

    private func place(_ meeting: Meeting) -> String { meeting.location.isEmpty ? meeting.country : meeting.location }

    private func load(force: Bool = false) async {
        let context = model.dataContext
        defer {
            if !Task.isCancelled, context == model.dataContext { loadingConstructors = false }
        }
        async let archive: Void = model.loadSeasonArchive(force: force)
        if let address = model.serverURL {
            let client = APIClient(baseURL: address)
            let newTeams = try? await client.constructorStandings(season: model.season, token: model.currentToken)
            if !Task.isCancelled, context == model.dataContext {
                constructors = newTeams ?? constructors
            }
        }
        await archive
    }
}

private extension View {
    func webHomePanel<Fill: ShapeStyle>(fill: Fill, line: Color = WebDashboardStyle.homeLine,
                                       inset: CGFloat = 14, minHeight: CGFloat = 126, stretch: Bool = false) -> some View {
        padding(inset).frame(maxWidth: .infinity, minHeight: minHeight,
                             maxHeight: stretch ? .infinity : nil, alignment: stretch ? .topLeading : .leading)
            .dashboardPanel(fill, line: line)
    }

    func webHomePanel(inset: CGFloat = 14, minHeight: CGFloat = 126, stretch: Bool = false) -> some View {
        webHomePanel(fill: WebDashboardStyle.homePanel, inset: inset, minHeight: minHeight, stretch: stretch)
    }
}

private var homeCountdownGradient: LinearGradient {
    LinearGradient(colors: [Color(red: 0.81, green: 0.03, blue: 0.02),
                            Color(red: 0.65, green: 0.12, blue: 0.11)],
                   startPoint: .leading, endPoint: .trailing)
}

private func englishCountdown(until start: Date, now: Date) -> String {
    let minutes = max(0, Int(start.timeIntervalSince(now) / 60))
    if minutes == 0 { return "<1 min" }
    if minutes < 60 { return "\(minutes) min" }
    if minutes < 1440 { return "\(minutes / 60)h \(minutes % 60)m" }
    return "\(minutes / 1440)d \((minutes % 1440) / 60)h"
}

private struct HomeCountdownTime {
    let remaining: Int

    init(start: Date, now: Date) {
        remaining = max(0, Int(ceil(start.timeIntervalSince(now))))
    }

    var fields: [(String, Int)] {
        [("DAYS", remaining / 86400), ("HRS", remaining / 3600 % 24),
         ("MINS", remaining / 60 % 60), ("SEC", remaining % 60)]
    }

    var accessibilityLabel: String {
        "\(remaining / 86400) days, \(remaining / 3600 % 24) hours, \(remaining / 60 % 60) minutes, \(remaining % 60) seconds"
    }
}

private struct HomeCountdownFullscreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var pull: CGFloat = 0
    let title: String
    let start: Date
    let close: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(title).font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let time = HomeCountdownTime(start: start, now: context.date)
                if context.date >= start {
                    Text("Session underway").font(.largeTitle.bold())
                } else {
                    let previous = HomeCountdownTime(start: start, now: context.date.addingTimeInterval(-1))
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(time.fields.indices, id: \.self) { index in
                            let (label, value) = time.fields[index]
                            VStack(spacing: 12) {
                                CountdownFlipTile(value: value, previous: previous.fields[index].1)
                                Text(label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }.frame(maxWidth: .infinity)
                            if index < time.fields.count - 1 {
                                VStack(spacing: 8) {
                                    Circle().frame(width: 5, height: 5)
                                    Circle().frame(width: 5, height: 5)
                                }
                                .foregroundStyle(.white.opacity(0.65))
                                .frame(height: 120)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(time.accessibilityLabel)
                }
            }
        }
        .frame(maxWidth: 740)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .offset(y: reduceMotion ? 0 : pull)
        .animation(.snappy(duration: 0.24), value: pull == 0)
        .contentShape(Rectangle())
        .gesture(pullToDismiss)
        .overlay(alignment: .topTrailing) {
            Button("Close Countdown", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .tint(.white)
                .padding(.top, 18)
                .padding(.trailing, 62)
        }
        .accessibilityAction(.escape, close)
    }

    private var pullToDismiss: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($pull) { drag, offset, _ in
                guard drag.translation.height > abs(drag.translation.width) else { return }
                offset = drag.translation.height * 0.55
            }
            .onEnded { drag in
                let distance = drag.translation.height
                guard distance > abs(drag.translation.width),
                      distance > 72 || (distance > 24 && drag.predictedEndTranslation.height > 140) else { return }
                close()
            }
    }
}

private struct CountdownFlipTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Int
    let previous: Int

    var body: some View {
        let animatesFlips = !reduceMotion && previous != value
        GeometryReader { geometry in
            let size = geometry.size
            Color.clear.keyframeAnimator(initialValue: 1.0, trigger: value) { _, phase in
                ZStack {
                    VStack(spacing: 0) {
                        face(value, top: true, size: size)
                        face(animatesFlips && phase < 0.5 ? previous : value, top: false, size: size)
                    }
                    if animatesFlips && phase < 0.5 {
                        face(previous, top: true, size: size)
                            .rotation3DEffect(.degrees(-phase * 180), axis: (1, 0, 0), anchor: .bottom)
                            .frame(maxHeight: .infinity, alignment: .top)
                    } else if animatesFlips && phase < 1 {
                        face(previous, top: false, size: size)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        face(value, top: false, size: size)
                            .rotation3DEffect(.degrees((1 - phase) * 180), axis: (1, 0, 0), anchor: .top)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    Rectangle().fill(.black.opacity(0.4)).frame(height: 1)
                }
            } keyframes: { _ in
                MoveKeyframe(0)
                CubicKeyframe(1, duration: 0.34)
            }
            .clipShape(.rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.16)) }
        }
        .frame(height: 120)
    }

    private nonisolated func face(_ number: Int, top: Bool, size: CGSize) -> some View {
        Text(String(format: "%02d", number))
            .font(.system(size: 96, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.25)
            .frame(width: max(0, size.width - 10), height: size.height)
            .frame(width: size.width, height: size.height / 2, alignment: top ? .top : .bottom)
            .background(top ? Color(red: 0.18, green: 0.07, blue: 0.08)
                            : Color(red: 0.24, green: 0.09, blue: 0.10))
            .clipped()
    }
}

private struct WebHomeRecords: View {
    let weekends: [SeasonResultWeekend]
    let season: Int
    var stretch = false
    let openResults: () -> Void

    private enum Category: String, CaseIterable {
        case team = "Team", driver = "Driver", rookie = "Rookie", race = "Race", track = "Track"

        var tint: Color {
            switch self {
            case .team: Color(red: 0.09, green: 0.54, blue: 0.24)
            case .driver: Color(red: 0.15, green: 0.39, blue: 0.92)
            case .rookie: Color(red: 0.66, green: 0.39, blue: 0.03)
            case .race: Color(red: 0.82, green: 0.15, blue: 0.31)
            case .track: Color(red: 0.57, green: 0.25, blue: 0.81)
            }
        }
    }

    private struct Record: Identifiable {
        let category: Category
        let weekend: SeasonResultWeekend
        let session: Session
        let title: String
        let description: String
        var id: String { "\(session.id):\(category.rawValue):\(title)" }
    }

    var body: some View {
        let visible = Array(records.prefix(3))
        if !visible.isEmpty {
            Button(action: openResults) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(String(season)) Stats & Records").font(.headline)
                        Spacer(minLength: 8)
                        PulseChevron()
                    }
                    ForEach(visible) { record in
                        tile(record)
                    }
                }.webHomePanel(inset: 16, minHeight: 0, stretch: stretch).contentShape(PulseStyle.cardShape)
            }.buttonStyle(PulsePressStyle()).accessibilityIdentifier("home.results")
        }
    }

    private func tile(_ record: Record) -> some View {
        let meeting = record.weekend.meeting
        return VStack(alignment: .leading, spacing: 4) {
            Text(record.category.rawValue.uppercased()).font(.system(size: 10, weight: .bold))
                .foregroundStyle(record.category.tint)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(record.category.tint.opacity(0.09), in: Capsule())
            Text(record.title).font(.system(size: 15, weight: .semibold))
            Text(record.description).font(.system(size: 14)).foregroundStyle(WebDashboardStyle.homeMuted)
            HStack {
                FlagBadge(countryCode: meeting.countryCode).accessibilityHidden(true)
                Text(meeting.location.isEmpty ? meeting.country : meeting.location)
                Spacer(minLength: 4)
                Text(record.session.startTime, format: .dateTime.day().month(.abbreviated))
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .background(WebDashboardStyle.homeLine, in: Capsule())
            }.font(.system(size: 12)).foregroundStyle(WebDashboardStyle.homeMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var records: [Record] {
        weekends.sorted { ($0.meeting.round ?? 0) > ($1.meeting.round ?? 0) }.flatMap { weekend -> [Record] in
            let meeting = weekend.meeting
            let place = meeting.location.isEmpty ? meeting.country : meeting.location
            let rows = (weekend.sessions["race"]?.rows ?? []).filter { ($0.position ?? 0) > 0 }
            guard let race = meeting.sessions.first(where: { $0.sessionType == .race }),
                  let winner = rows.first(where: { $0.position == 1 }) else { return [] }
            var output: [Record] = []
            func add(_ category: Category, _ title: String, _ description: String, session: Session? = nil) {
                output.append(Record(category: category, weekend: weekend, session: session ?? race, title: title, description: description))
            }
            add(.race, "\(winner.driverName) wins in \(place)",
                "\(winner.driverName) took first place for \(winner.team)\(winner.laps.map { " after \($0) laps" } ?? "").")
            let podiums = Dictionary(grouping: rows.filter { ($0.position ?? 0) <= 3 }, by: \.constructorId)
            for key in podiums.keys.sorted() {
                guard let podium = podiums[key], podium.count > 1, let team = podium.first?.team else { continue }
                let names = podium.map { "\($0.driverName) (P\($0.position ?? 0))" }.joined(separator: " and ")
                add(.team, "\(team) takes a double podium", "\(names) finished on the podium in \(place).")
            }
            let gains = rows.compactMap { row -> (row: SessionResult, start: Int, finish: Int, gain: Int)? in
                guard row.classification.uppercased() == "CLASSIFIED", let start = row.gridPosition,
                      let finish = row.position, start > finish else { return nil }
                return (row, start, finish, start - finish)
            }
            if let gain = gains.max(by: { $0.gain < $1.gain }) {
                add(.driver, "\(gain.row.driverName) gains \(gain.gain) places in \(place)",
                    "\(gain.row.driverName) started P\(gain.start) and finished P\(gain.finish) for \(gain.row.team).")
            }
            if let qualifying = meeting.sessions.first(where: { $0.sessionType == .qualifying }) {
                let laps = (weekend.sessions["qualifying"]?.rows ?? []).flatMap { row in
                    [row.q1, row.q2, row.q3, row.bestLap].compactMap { time -> (name: String, seconds: Double)? in
                        AnalysisMath.elapsedSeconds(time).map { (row.driverName, $0) }
                    }
                }
                if let lap = laps.min(by: { $0.seconds < $1.seconds }) {
                    add(.track, "\(lap.name) sets the fastest qualifying lap",
                        "\(AnalysisMath.duration(lap.seconds)) at \(meeting.circuit?.name ?? place), the quickest time in the available qualifying results.", session: qualifying)
                }
            }
            return output
        }
    }
}

extension SessionType {
    var webTitle: String {
        switch self {
        case .fp1: "Practice 1"
        case .fp2: "Practice 2"
        case .fp3: "Practice 3"
        case .qualifying: "Qualifying"
        case .race: "Race"
        case .sprint: "Sprint"
        case .sprintQualifying: "Sprint Qualifying"
        }
    }
}

struct OverviewScreen: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openTab: (DashboardTab) -> Void
    @State private var constructors: APIEnvelope<[ConstructorStanding]>?
    @Namespace private var featureTransition

    var body: some View {
        NavigationStack {
            ScrollView {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let latest = model.recentRaceSources.first
                    let recapFirst = latest.map {
                        Calendar.current.isDate($0.session.startTime, inSameDayAs: context.date)
                    } ?? false
                    VStack(alignment: .leading, spacing: 16) {
                        if recapFirst, let latest { recap(latest) }
                        if let next = CalendarLogic.nextSession(in: model.meetings, now: context.date) {
                            hero(next)
                            weekend(next, now: context.date)
                        } else if model.loadState.isLoading {
                            PulseSkeleton(label: "Loading schedule…")
                        } else if latest == nil {
                            ContentUnavailableView("No Upcoming Race", systemImage: "flag.checkered",
                                description: Text(model.loadState.errorText?.pulseEnglishError ?? "There are no upcoming sessions this season."))
                        }
                        if !recapFirst, let latest { recap(latest) }
                        if let archive = model.seasonArchive {
                            HomeSeasonRecords(weekends: archive.data, stale: archive.meta.stale, openResults: { openTab(.results) })
                        }
                        standingsPreview
                    }.padding(16)
                }
            }
            .background(PulseStyle.background)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { PulseSettingsButton() } }
            .task(id: model.dataContext) {
                constructors = nil
                async let standings: Void = loadConstructors()
                async let archive: Void = model.loadSeasonArchive()
                _ = await (standings, archive)
            }
            .refreshable {
                async let roster: Void = model.loadF1Roster(force: true)
                async let standings: Void = loadConstructors()
                async let archive: Void = model.loadSeasonArchive(force: true)
                await model.loadCalendar(force: true)
                await model.loadWidgetHighlights(force: true)
                _ = await (roster, standings, archive)
            }
        }
    }

    private func hero(_ next: NextSession) -> some View {
        NavigationLink {
            WeekendScreen(meeting: next.meeting)
                .pulseNavigationZoom("next-race", in: featureTransition)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(next.session.sessionType.resultLabel, systemImage: "flag.checkered")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption.bold()).accessibilityHidden(true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        raceIdentity(next)
                        Spacer(minLength: 0)
                        raceMap(next).frame(width: 122, height: 76)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        raceIdentity(next)
                        raceMap(next).frame(height: 66)
                    }
                }
            }
            .padding(16)
            .background {
                PulseStyle.cardShape.fill(PulseStyle.surface)
                    .overlay {
                        PulseStyle.cardShape.fill(
                            LinearGradient(colors: [PulseStyle.red.opacity(0.20), .clear], startPoint: .trailing, endPoint: .leading)
                        )
                    }
            }
            .matchedTransitionSource(id: "next-race", in: featureTransition)
        }.buttonStyle(PulsePressStyle())
    }

    private func raceIdentity(_ next: NextSession) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(next.meeting.name).font(.headline).fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                PulseNumber(englishCountdown(until: next.session.startTime, now: context.date))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(PulseStyle.red)
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
            Text(next.session.startTime, format: .dateTime.weekday().hour().minute())
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func raceMap(_ next: NextSession) -> some View {
        CircuitOutlineView(meetingID: next.meeting.id)
            .foregroundStyle(PulseStyle.red)
            .padding(7)
            .accessibilityHidden(true)
    }

    private func weekend(_ next: NextSession, now: Date) -> some View {
        let upcoming = next.meeting.sessions.filter { $0.status == .scheduled && $0.startTime >= now }
            .sorted { $0.startTime < $1.startTime }
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Weekend Schedule").font(.subheadline.weight(.semibold))
                Spacer()
                Text("Local Time").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(upcoming) { session in
                let isNext = session.id == next.session.id
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        weekendLabel(session, isNext: isNext).fixedSize()
                        Spacer(minLength: 8)
                        weekendTime(session).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        weekendLabel(session, isNext: isNext)
                        weekendTime(session)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }.padding(.horizontal, 4)
    }

    private func weekendLabel(_ session: Session, isNext: Bool) -> some View {
        Label(session.sessionType.resultLabel, systemImage: isNext ? "circle.fill" : "circle")
            .font(.subheadline.weight(isNext ? .semibold : .regular))
            .foregroundStyle(isNext ? PulseStyle.red : .primary)
    }

    private func weekendTime(_ session: Session) -> some View {
        Text(session.startTime, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
    }

    private func recap(_ latest: FavoriteRaceSource) -> some View {
        let winner = latest.results.first { $0.position == 1 && $0.driverId != model.favoriteDriverID }
        return Button {
            openTab(.results)
        } label: {
            PulseCardDestination {
                HStack(spacing: 12) {
                    CircuitOutlineView(meetingID: latest.meeting.id)
                        .frame(width: 54, height: 38).foregroundStyle(PulseStyle.red).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(latest.savedAt == .distantPast ? "Last Race · Cached" : "Last Race")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(latest.meeting.name).font(.headline)
                        if let winner {
                            Text("P1 · \(winner.driverName)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.buttonStyle(PulsePressStyle())
    }

    @ViewBuilder private var standingsPreview: some View {
        let drivers = model.driverRoster.sorted { $0.position < $1.position }.prefix(3).map(StandingEntry.init(driver:))
        let teams = (constructors?.data ?? []).sorted { $0.position < $1.position }.prefix(3).map(StandingEntry.init(team:))
        if !drivers.isEmpty {
            standingsCard("Driver Standings", entries: drivers, showTeams: false, stale: model.rosterSavedAt == .distantPast)
        }
        if !teams.isEmpty {
            standingsCard("Constructor Standings", entries: teams, showTeams: true, stale: constructors?.meta.stale == true)
        }
    }

    private func standingsCard(_ title: String, entries: [StandingEntry], showTeams: Bool, stale: Bool) -> some View {
        Button { openTab(showTeams ? .constructors : .drivers) } label: {
            PulseCardDestination {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(title, systemImage: "trophy").font(.headline)
                    Spacer()
                    if stale { Text("Cached").font(.caption).foregroundStyle(.secondary) }
                }
                ForEach(entries, id: \.id) { entry in
                        HStack(spacing: 9) {
                            Text(String(entry.position)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            AssetImage(name: entry.asset).frame(width: 27, height: 26)
                            if !showTeams && entry.id == model.favoriteDriverID {
                                Label(entry.name, systemImage: "star.fill")
                                    .font(.subheadline.weight(.medium))
                            } else {
                                Text(entry.name).font(.subheadline.weight(.medium))
                            }
                            Spacer(minLength: 7)
                            PulseNumber(entry.points.formatted()).font(.subheadline.bold().monospacedDigit())
                        }.frame(minHeight: 28)
                }
            }
            }
        }.buttonStyle(PulsePressStyle())
            .accessibilityIdentifier(showTeams ? "home.constructors" : "home.drivers")
    }

    private func loadConstructors() async {
        guard let url = model.serverURL else { return }
        let context = model.dataContext
        do {
            let result = try await APIClient(baseURL: url).constructorStandings(season: model.season, token: model.currentToken)
            guard !Task.isCancelled, model.dataContext == context else { return }
            constructors = result
        } catch {
            // This preview can remain on the last successful response while the full tab shows retry controls.
        }
    }

}

private struct HomeSeasonRecords: View {
    let weekends: [SeasonResultWeekend]
    let stale: Bool
    let openResults: () -> Void
    @State private var category: Category?
    @Namespace private var recordTransition

    private enum Category: String, CaseIterable, Identifiable {
        case race = "Race Win", team = "Double Podium", driver = "Places Gained", track = "Circuit Record"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .race: "trophy.fill"
            case .team: "flag.checkered.2.crossed"
            case .driver: "arrow.up.right"
            case .track: "stopwatch"
            }
        }
    }

    private struct Record: Identifiable {
        let category: Category
        let weekend: SeasonResultWeekend
        let session: Session
        let row: SessionResult
        let value: String
        let note: String
        var id: String { "\(weekend.id)-\(category.rawValue)-\(row.id)" }
    }

    private var records: [Record] {
        weekends.sorted { $0.meeting.startDate > $1.meeting.startDate }.flatMap { weekend -> [Record] in
            guard let race = weekend.meeting.sessions.first(where: { $0.sessionType == .race }),
                  let raceRows = weekend.sessions[SessionType.race.rawValue]?.rows else { return [] }
            let confirmed = raceRows.filter { $0.classification.uppercased() == "CLASSIFIED" }
            var highlights: [Record] = []
            if let leader = confirmed.first(where: { $0.position == 1 }) {
                highlights.append(Record(category: .race, weekend: weekend, session: race, row: leader,
                                         value: "P1", note: leader.driverName))
            }
            let podium = confirmed.filter { (1...3).contains($0.position ?? 0) }
            let groups = Dictionary(grouping: podium, by: \.constructorId)
            for id in groups.keys.sorted() {
                guard let rows = groups[id], rows.count >= 2, let lead = rows.first else { continue }
                highlights.append(Record(category: .team, weekend: weekend, session: race, row: lead,
                                         value: lead.team, note: rows.map(\.driverName).joined(separator: " / ")))
            }
            let gains = confirmed.compactMap { row -> (SessionResult, Int)? in
                guard let grid = row.gridPosition, grid > 0,
                      let finish = row.position, finish > 0, grid > finish else { return nil }
                return (row, grid - finish)
            }
            if let (driver, gain) = gains.max(by: { $0.1 < $1.1 }) {
                highlights.append(Record(category: .driver, weekend: weekend, session: race, row: driver,
                                         value: "+\(gain) places", note: driver.driverName))
            }
            if let quali = weekend.meeting.sessions.first(where: { $0.sessionType == .qualifying }) {
                let times = (weekend.sessions[SessionType.qualifying.rawValue]?.rows ?? []).flatMap { row in
                    [row.q1, row.q2, row.q3, row.bestLap].compactMap { raw -> (SessionResult, Double)? in
                        AnalysisMath.elapsedSeconds(raw).map { (row, $0) }
                    }
                }
                if let (driver, lap) = times.min(by: { $0.1 < $1.1 }) {
                    highlights.append(Record(category: .track, weekend: weekend, session: quali, row: driver,
                                             value: AnalysisMath.duration(lap), note: driver.driverName))
                }
            }
            return highlights
        }
    }

    var body: some View {
        let all = records
        let visible = all.filter { category == nil || $0.category == category }
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Season Records").font(.headline)
                    Spacer()
                    if stale { Text("Cached").font(.caption).foregroundStyle(.secondary) }
                    Menu {
                        Picker("Type", selection: $category) {
                            Text("All").tag(Category?.none)
                            ForEach(Category.allCases.filter { value in all.contains { $0.category == value } }) { item in
                                Text(item.rawValue).tag(Category?.some(item))
                            }
                        }
                    } label: {
                        Label(category?.rawValue ?? "All", systemImage: "line.3.horizontal.decrease")
                    }.buttonStyle(.glass)
                }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 9) {
                        ForEach(visible) { record in
                            Button(action: openResults) {
                                recordTile(record)
                            }.buttonStyle(PulsePressStyle())
                        }
                    }.scrollTargetLayout()
                }.scrollTargetBehavior(.viewAligned).scrollIndicators(.hidden)
            }
        }
    }

    private func recordTile(_ record: Record) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(record.category.rawValue, systemImage: record.category.symbol)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    AssetImage(name: MotorsportAssetName.driverAvatarName(driverID: record.row.id,
                        name: record.row.driverName, season: record.weekend.meeting.season))
                        .frame(width: 28, height: 26)
                }
                Text(record.value).font(.headline.monospacedDigit())
                Text(record.note).font(.caption).lineLimit(2, reservesSpace: true)
                Text(record.weekend.meeting.location).font(.caption2).foregroundStyle(.secondary)
            }
        }.frame(width: 170)
    }
}

private enum RaceCalendarFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case upcoming = "Upcoming"
    case completed = "Completed"

    var id: Self { self }

    func includes(upcoming: Bool) -> Bool {
        self == .all || (self == .upcoming ? upcoming : !upcoming)
    }
}

private func isUpcomingRace(_ meeting: Meeting, at now: Date, archive: APIEnvelope<[SeasonResultWeekend]>?) -> Bool {
    meeting.status == .scheduled && !calendarRaceFinished(meeting, at: now, archive: archive)
}

private func calendarRaceFinished(_ meeting: Meeting, at now: Date, archive: APIEnvelope<[SeasonResultWeekend]>?) -> Bool {
    guard let race = meeting.sessions.first(where: { $0.sessionType == .race }) else {
        return meeting.endDate < now
    }
    guard race.status != .live, race.status != .cancelled, race.status != .postponed else { return false }
    return race.status == .finished
        || archive?.data.first { $0.id == meeting.id }?.sessions["race"]?.rows.isEmpty == false
        || (race.endTime ?? meeting.endDate) < now
}

struct TabletRaceCalendar: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var month = 0
    @State private var selectedMeetingID: Meeting.ID?
    @State private var sessionResult: (meeting: Meeting, session: Session)?
    @State private var resultAfterSheetDismisses: (meeting: Meeting, session: Session)?
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var filter = RaceCalendarFilter.all

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar
    }

    private var filteredMeetings: [Meeting] {
        let now = Date.now
        return model.meetings.filter { meeting in
            filter.includes(upcoming: isUpcomingRace(meeting, at: now, archive: model.seasonArchive))
        }
    }

    private var openingRace: Meeting? {
        model.meetings.first { $0.round != nil && $0.hasPublishedWeekendDatesOnly }
    }

    private var displayedMonth: Int {
        if month != 0 { return month }
        return calendar.component(.month, from: openingRace?.calendarDateRange(in: calendar).lowerBound ?? .now)
    }
    private var selectedMeeting: Meeting? { model.meetings.first { $0.id == selectedMeetingID } }

    var body: some View {
        GeometryReader { viewport in
            let wide = viewport.size.width >= 800 && !typeSize.isAccessibilitySize
            HStack(spacing: 0) {
                grid(height: viewport.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if wide, let selectedMeeting {
                    Divider()
                    details(selectedMeeting) { session in
                        sessionResult = (selectedMeeting, session)
                    }
                    .frame(width: min(390, viewport.size.width * 0.36))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .sheet(isPresented: Binding(
                get: { !wide && selectedMeeting != nil },
                set: { if !$0 && !wide { selectedMeetingID = nil } }
            ), onDismiss: {
                if let resultAfterSheetDismisses {
                    sessionResult = resultAfterSheetDismisses
                    self.resultAfterSheetDismisses = nil
                }
            }) {
                if let selectedMeeting {
                    details(selectedMeeting) { session in
                        resultAfterSheetDismisses = (selectedMeeting, session)
                        selectedMeetingID = nil
                    }
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: wide && selectedMeeting != nil)
        }
        .background(WebDashboardStyle.homeBackground)
        .foregroundStyle(WebDashboardStyle.homeText)
        .onChange(of: model.season) { _, _ in
            month = 0
            selectedMeetingID = nil
        }
        .navigationDestination(isPresented: Binding(
            get: { sessionResult != nil },
            set: { if !$0 { sessionResult = nil } }
        )) {
            if let sessionResult {
                TabletWeekendSessionResults(meeting: sessionResult.meeting, session: sessionResult.session)
            }
        }
    }

    private func grid(height: CGFloat) -> some View {
        let firstDay = calendar.date(from: DateComponents(year: model.season, month: displayedMonth, day: 1)) ?? .now
        let offset = (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 0
        let weekCount = (offset + dayCount + 6) / 7
        let weeks = (0..<weekCount).map { week in
            (0..<7).compactMap { calendar.date(byAdding: .day, value: week * 7 + $0 - offset, to: firstDay) }
        }
        let meetings = filteredMeetings.sorted { $0.startDate < $1.startDate }
        let monthMeetings = meetings.filter { meeting in
            guard let lastDay = calendar.date(byAdding: .day, value: dayCount - 1, to: firstDay) else { return false }
            return raceDays(meeting).overlaps(firstDay...lastDay)
        }
        let now = Date.now
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                monthHeader(firstDay)
                searchBar
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    monthGrid(weeks, month: firstDay, meetings: monthMeetings, now: now,
                              rowHeight: min(84, max(74, (height - 190) / CGFloat(max(1, weekCount)))))
                    if model.meetings.isEmpty, model.loadState.isLoading {
                        PulseSkeleton(label: "Loading schedule…")
                    } else if model.meetings.isEmpty {
                        Text(model.loadState.errorText?.pulseEnglishError ?? "No schedule available.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if monthMeetings.isEmpty {
                        Text(filter == .all ? "No race weekends this month." : "No matching race weekends this month.")
                            .font(.subheadline)
                            .foregroundStyle(WebDashboardStyle.homeMuted)
                            .padding(.horizontal, 4)
                    } else {
                        raceList(monthMeetings, now: now)
                    }
                } else {
                    searchResults(meetings, now: now)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.loadCalendar(force: true) }
    }

    private func monthHeader(_ date: Date) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                monthTitle(date).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                monthNavigation
            }
            VStack(alignment: .leading, spacing: 8) {
                monthTitle(date)
                monthNavigation
            }
        }
    }

    private func monthTitle(_ date: Date) -> some View {
        Text(date, format: .dateTime.month(.wide).year().locale(locale))
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
    }

    private var monthNavigation: some View {
        HStack(spacing: 0) {
            monthButton("Previous month", symbol: "chevron.left", change: -1)
            Button(openingRace == nil ? "Today" : "First Race") { showMonth(0) }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
            monthButton("Next month", symbol: "chevron.right", change: 1)
        }
        .buttonStyle(.plain)
        .background(WebDashboardStyle.homePanel, in: .capsule)
        .overlay { Capsule().strokeBorder(WebDashboardStyle.homeLine).allowsHitTesting(false) }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").accessibilityHidden(true)
                TextField("Search races or locations", text: $query,
                          prompt: Text("Search races or locations").foregroundStyle(WebDashboardStyle.homeMuted))
                    .foregroundStyle(WebDashboardStyle.homeText)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                    .accessibilityIdentifier("calendar.search")
                if !query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 32, minHeight: 44)
                }
            }
            .foregroundStyle(WebDashboardStyle.homeMuted)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(WebDashboardStyle.homePanel, in: .capsule)
            .overlay { Capsule().strokeBorder(WebDashboardStyle.homeLine).allowsHitTesting(false) }
            Menu {
                Picker("Calendar Range", selection: $filter) {
                    ForEach(RaceCalendarFilter.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                    if filter != .all { Text(filter.rawValue).lineLimit(1) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(filter == .all ? WebDashboardStyle.homeText : PulseStyle.red)
                .padding(.horizontal, 12)
                .frame(minWidth: 44, minHeight: 44)
                .background(WebDashboardStyle.homePanel, in: .capsule)
                .overlay { Capsule().strokeBorder(WebDashboardStyle.homeLine).allowsHitTesting(false) }
            }
            .accessibilityLabel("Filter races")
            .accessibilityValue(filter.rawValue)
        }
        .buttonStyle(.plain)
    }

    private func showMonth(_ month: Int, meeting: Meeting.ID? = nil) {
        self.month = month
        query = ""
        searchFocused = false
        selectedMeetingID = meeting
    }

    private func monthButton(_ title: String, symbol: String, change: Int) -> some View {
        let enabled = (1...12).contains(displayedMonth + change)
        return Button(title, systemImage: symbol) { showMonth(displayedMonth + change) }
            .labelStyle(.iconOnly)
            .font(.subheadline.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .opacity(enabled ? 1 : 0.35)
            .disabled(!enabled)
    }

    private func monthGrid(_ weeks: [[Date]], month: Date, meetings: [Meeting], now: Date, rowHeight: CGFloat) -> some View {
        let weekdays = calendar.shortStandaloneWeekdaySymbols
        return VStack(spacing: 1) {
            HStack(spacing: 1) {
                ForEach(0..<7, id: \.self) { column in
                    Text(weekdays[(column + calendar.firstWeekday - 1) % 7])
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .foregroundStyle(WebDashboardStyle.homeMuted)
                }
            }
            .background(WebDashboardStyle.homePanel)
            ForEach(weeks.indices, id: \.self) { week in
                weekRow(weeks[week], month: month, meetings: meetings, now: now, rowHeight: rowHeight)
            }
        }
        .background(WebDashboardStyle.homeLine)
        .clipShape(PulseStyle.cardShape)
        .overlay { PulseStyle.cardShape.strokeBorder(WebDashboardStyle.homeLine).allowsHitTesting(false) }
    }

    private struct RaceSpan: Identifiable {
        let meeting: Meeting
        let columns: ClosedRange<Int>
        let lane: Int
        var id: Meeting.ID { meeting.id }
    }

    private func raceDays(_ meeting: Meeting) -> ClosedRange<Date> {
        let dates = meeting.calendarDateRange(in: calendar)
        let start = calendar.startOfDay(for: dates.lowerBound)
        return start...max(start, calendar.startOfDay(for: dates.upperBound))
    }

    private func weekSpans(_ dates: [Date], month: Date, meetings: [Meeting]) -> [RaceSpan] {
        var lastColumns: [Int] = []
        var spans: [RaceSpan] = []
        for meeting in meetings {
            let days = raceDays(meeting)
            let columns = dates.indices.filter {
                calendar.isDate(dates[$0], equalTo: month, toGranularity: .month) && days.contains(dates[$0])
            }
            guard let start = columns.first, let end = columns.last else { continue }
            let lane = lastColumns.firstIndex { $0 < start } ?? lastColumns.count
            if lane == lastColumns.count {
                lastColumns.append(end)
            } else {
                lastColumns[lane] = end
            }
            spans.append(RaceSpan(meeting: meeting, columns: start...end, lane: lane))
        }
        return spans
    }

    private func weekRow(_ dates: [Date], month: Date, meetings: [Meeting], now: Date, rowHeight: CGFloat) -> some View {
        let spans = weekSpans(dates, month: month, meetings: meetings)
        let laneCount = (spans.map(\.lane).max() ?? -1) + 1
        let height = max(rowHeight, 32 + CGFloat(laneCount) * 44)
        return HStack(spacing: 1) {
            ForEach(dates, id: \.self) { date in
                dayCell(date, inMonth: calendar.isDate(date, equalTo: month, toGranularity: .month), now: now)
                    .frame(height: height, alignment: .top)
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                let stride = (geometry.size.width + 1) / 7
                let direction: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
                ZStack(alignment: .topLeading) {
                    ForEach(spans) { span in
                        raceBand(span.meeting, now: now)
                            .frame(width: max(0, stride * CGFloat(span.columns.count) - 8))
                            .offset(x: direction * (stride * CGFloat(span.columns.lowerBound) + 4),
                                    y: 30 + CGFloat(span.lane) * 44)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func dayCell(_ date: Date, inMonth: Bool, now: Date) -> some View {
        let today = calendar.isDate(date, inSameDayAs: now)
        return Text(date, format: .dateTime.day())
            .font(.caption.weight(today ? .bold : .medium).monospacedDigit())
            .foregroundStyle(today ? .white : inMonth ? WebDashboardStyle.homeText : WebDashboardStyle.homeMuted)
            .frame(minWidth: 24, minHeight: 24)
            .background(today ? PulseStyle.red : .clear, in: .circle)
            .padding(.top, 4)
            .frame(maxWidth: .infinity)
            .opacity(inMonth ? 1 : 0.56)
            .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month().day()))
            .accessibilityAddTraits(today ? .isSelected : [])
            .frame(maxHeight: .infinity, alignment: .top)
            .background {
                (inMonth ? WebDashboardStyle.homePanel : WebDashboardStyle.homeBackground)
                    .overlay { if today { PulseStyle.red.opacity(0.07) } }
            }
    }

    private func raceBand(_ meeting: Meeting, now: Date) -> some View {
        let upcoming = isUpcomingRace(meeting, at: now, archive: model.seasonArchive)
        let selected = selectedMeetingID == meeting.id
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button {
            selectedMeetingID = meeting.id
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    FlagBadge(countryCode: meeting.countryCode, width: 16, height: 10)
                    Text(meeting.name).fixedSize()
                }
                Text(meeting.location.isEmpty ? meeting.country : meeting.location)
                    .fixedSize()
                Text(meeting.round.map { "R\($0)" } ?? meeting.countryCode ?? "GP")
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .foregroundStyle(upcoming || selected ? PulseStyle.red : WebDashboardStyle.homeText)
            .background(upcoming || selected ? PulseStyle.red.opacity(selected ? 0.20 : 0.12)
                        : WebDashboardStyle.homeMuted.opacity(0.12), in: shape)
            .overlay { shape.strokeBorder(selected ? PulseStyle.red : .clear).allowsHitTesting(false) }
            .frame(height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(meeting.name)
        .accessibilityValue(raceDateLabel(meeting))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("calendar.race.\(meeting.id)")
    }

    private func raceDateLabel(_ meeting: Meeting) -> String {
        let days = raceDays(meeting)
        if days.lowerBound == days.upperBound {
            return days.lowerBound.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        }
        return (days.lowerBound..<days.upperBound).formatted(.interval.month(.abbreviated).day().locale(locale))
    }

    private func searchResults(_ meetings: [Meeting], now: Date) -> some View {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = meetings.filter { meeting in
            [meeting.name, meeting.location, meeting.country].contains { $0.localizedStandardContains(text) }
        }
        return Group {
            if matches.isEmpty {
                ContentUnavailableView.search(text: text)
            } else {
                raceList(matches, now: now, searching: true)
            }
        }
    }

    private func raceList(_ meetings: [Meeting], now: Date, searching: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !searching {
                Text("Race Weekends")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 6)
            }
            ForEach(meetings) { meeting in
                if meeting.id != meetings.first?.id { Divider() }
                Button {
                    if searching {
                        showMonth(calendar.component(.month, from: raceDays(meeting).lowerBound), meeting: meeting.id)
                    } else {
                        selectedMeetingID = meeting.id
                    }
                } label: {
                    HStack(spacing: 10) {
                        FlagBadge(countryCode: meeting.countryCode, width: 23, height: 15)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(meeting.name).font(.subheadline.weight(.semibold))
                            Text(raceDateLabel(meeting)).font(.caption).foregroundStyle(WebDashboardStyle.homeMuted)
                        }
                        Spacer(minLength: 0)
                        Text(raceStatus(meeting, at: now))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(isUpcomingRace(meeting, at: now, archive: model.seasonArchive)
                                             ? PulseStyle.red : WebDashboardStyle.homeMuted)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WebDashboardStyle.homeMuted)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 7)
                    .frame(minHeight: 48)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedMeetingID == meeting.id ? .isSelected : [])
            }
        }
        .webHomePanel(inset: 14, minHeight: 0)
    }

    private func raceStatus(_ meeting: Meeting, at now: Date) -> String {
        switch meeting.status {
        case .cancelled: "Cancelled"
        case .postponed: "Postponed"
        case .scheduled:
            calendarRaceFinished(meeting, at: now, archive: model.seasonArchive) ? "Completed" : "Upcoming"
        }
    }

    private func details(_ meeting: Meeting, openResults: @escaping (Session) -> Void) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Race Weekend").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Close race details", systemImage: "xmark") { selectedMeetingID = nil }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, 16)
            Divider()
            WeekendScreen(meeting: meeting, embedded: true, openSessionResults: openResults)
                .id(meeting.id)
        }
        .background(WebDashboardStyle.homeBackground)
    }
}

struct CalendarScreen: View {
    @EnvironmentObject private var model: MobileModel
    @State private var filter = RaceCalendarFilter.all
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var position = ScrollPosition(idType: Meeting.ID.self)
    @State private var positionedCalendar = false

    private func filteredMeetings(at now: Date) -> [Meeting] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.meetings.filter { meeting in
            let matchesSearch = query.isEmpty || [meeting.name, meeting.location, meeting.country].contains {
                $0.localizedCaseInsensitiveContains(query)
            }
            return matchesSearch && filter.includes(upcoming: isUpcomingRace(meeting, at: now, archive: model.seasonArchive))
        }
    }

    var body: some View {
        calendar
            .background(PulseStyle.background)
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Calendar Range", selection: $filter) {
                            ForEach(RaceCalendarFilter.allCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                    } label: {
                        Label("Filter Races", systemImage: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .dashboardDetail()
            .safeAreaInset(edge: .bottom, spacing: 0) { searchBar }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
            TextField("Search races or locations", text: $search)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("calendar.search")
            if !search.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") { search = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: 48)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: 640)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private var calendar: some View {
        let now = Date()
        let meetings = filteredMeetings(at: now)
        let nextIndex = meetings.firstIndex { isUpcomingRace($0, at: now, archive: model.seasonArchive) }
        let nextID = nextIndex.map { meetings[$0].id }
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                    VStack(spacing: 0) {
                        if filter == .all, index > 0, meeting.id == nextID {
                            calendarDivider
                        } else if index > 0 {
                            Divider()
                        }
                        row(meeting, finished: calendarRaceFinished(meeting, at: now, archive: model.seasonArchive))
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .id(meeting.id)
                }
                if meetings.isEmpty {
                    if model.loadState.isLoading { PulseSkeleton(label: "Loading schedule…") }
                    else if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                    else { ContentUnavailableView("No Schedule Available", systemImage: "calendar", description: model.loadState.errorText.map { Text($0.pulseEnglishError) }) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition($position)
        .onChange(of: nextID ?? meetings.last?.id, initial: true) { _, target in
            guard !positionedCalendar, filter == .all, search.isEmpty, let target else { return }
            position.scrollTo(id: target, anchor: .center)
            positionedCalendar = true
        }
        .refreshable { await model.loadCalendar(force: true) }
    }

    private var calendarDivider: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Completed", systemImage: "arrowtriangle.up.fill")
            Rectangle().fill(PulseStyle.red).frame(height: 1).accessibilityHidden(true)
            Label("Upcoming", systemImage: "arrowtriangle.down.fill")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(PulseStyle.red)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ meeting: Meeting, finished: Bool) -> some View {
        NavigationLink {
            if finished, meeting.status == .scheduled,
               let race = meeting.sessions.first(where: { $0.sessionType == .race }) {
                if let archive = model.seasonArchive?.data.first(where: { $0.id == meeting.id }) {
                    MeetingResultsDashboard(weekend: archive, initial: race)
                } else {
                    ResultsScreen(session: race, meeting: meeting)
                        .navigationTitle("Race Results")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(.visible, for: .navigationBar)
                        .dashboardDetail()
                }
            } else {
                WeekendScreen(meeting: meeting)
            }
        } label: {
            meetingLabel(meeting)
        }
        .navigationLinkIndicatorVisibility(.hidden)
        .buttonStyle(PulsePressStyle())
        .accessibilityIdentifier("meeting.\(meeting.id)")
    }

    private func meetingLabel(_ meeting: Meeting) -> some View {
        HStack(spacing: 14) {
            Text(meeting.round.map(String.init) ?? "—")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .frame(width: 42, alignment: .leading)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    FlagBadge(countryCode: meeting.countryCode).accessibilityHidden(true)
                    Text(meeting.location).font(.caption.weight(.semibold))
                }
                Text(meeting.name).font(.headline).lineLimit(2)
                Group {
                    if meeting.hasPublishedWeekendDatesOnly {
                        let dates = meeting.calendarDateRange()
                        Text(dates.lowerBound..<dates.upperBound, format: .interval.month().day())
                    } else {
                        Text(meeting.startDate, format: .dateTime.month().day())
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            CircuitOutlineView(meetingID: meeting.id)
                .frame(width: 77, height: 42)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

private struct CircuitEnvelope: Decodable {
    struct DataValue: Decodable {
        struct Feature: Decodable {
            struct Geometry: Decodable { let coordinates: [[Double]] }
            let geometry: Geometry
        }
        let geometry: Feature?
    }
    let data: DataValue
}

struct CircuitOutlineView: View {
    @EnvironmentObject private var model: MobileModel
    let meetingID: String
    var animated = false
    var lineWidth: CGFloat = 2.5
    var showsPlaceholder = true
    @State private var points: [[Double]] = []
    @State private var loadedContext: String?

    var body: some View {
        ZStack {
            if points.count >= 2 {
                if animated { ScheduleCircuitTrace(points: points) }
                else {
                    CircuitPath(points: points)
                        .stroke(.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        .padding(4)
                }
            } else if showsPlaceholder {
                Image(systemName: "map").font(.title2).foregroundStyle(.tertiary)
            } else {
                Color.clear
            }
        }
        .accessibilityLabel(points.count >= 2 ? "Circuit Outline" : "Circuit outline unavailable")
        .task(id: model.dataContext + meetingID) {
            let context = model.dataContext + meetingID
            guard loadedContext != context, let url = model.serverURL else { return }
            points = []
            do {
                let data = try await APIClient(baseURL: url).mapData(path: "/api/v1/meetings/\(meetingID)/geometry", token: model.currentToken)
                let geometry = try JSONDecoder().decode(CircuitEnvelope.self, from: data).data.geometry
                guard !Task.isCancelled, context == model.dataContext + meetingID else { return }
                points = geometry?.geometry.coordinates.filter { $0.count >= 2 && $0.allSatisfy(\.isFinite) } ?? []
                loadedContext = context
            } catch {
                // Keep the placeholder so a transient request failure can retry on re-entry.
            }
        }
    }
}

private struct ScheduleCircuitTrace: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    let points: [[Double]]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(start))
            let circuit = CircuitPath(points: points)
            ZStack {
                circuit.stroke(WebDashboardStyle.adaptive(dark: 0xffffff, light: 0x1d2430),
                               style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                circuit.trim(from: 0, to: reduceMotion ? 1 : traceAmount(at: elapsed))
                    .stroke(.linearGradient(colors: [Color(red: 29 / 255, green: 214 / 255, blue: 178 / 255), PulseStyle.red],
                                            startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 78, height: 78)
            .rotationEffect(.degrees(-11 + (reduceMotion ? 0 : elapsed.truncatingRemainder(dividingBy: 24) * 15)))
            .rotation3DEffect(.degrees(52), axis: (x: 1, y: 0, z: 0), perspective: 0.22)
        }
    }

    private func traceAmount(at elapsed: TimeInterval) -> CGFloat {
        let phase = elapsed.truncatingRemainder(dividingBy: 8) / 8
        let ramp = min(1, max(0, min((phase - 0.08) / 0.34, (0.92 - phase) / 0.34)))
        return (1 - cos(ramp * .pi)) / 2
    }
}

private struct CircuitPath: Shape {
    let points: [[Double]]
    func path(in rect: CGRect) -> Path {
        guard let first = points.first else { return Path() }
        let cosine = cos(first[1] * .pi / 180)
        var projected = points.map { CGPoint(x: $0[0] * cosine, y: -$0[1]) }
        let width = (projected.map(\.x).max() ?? 0) - (projected.map(\.x).min() ?? 0)
        let height = (projected.map(\.y).max() ?? 0) - (projected.map(\.y).min() ?? 0)
        if rect.width > rect.height && height > width { projected = projected.map { CGPoint(x: $0.y, y: -$0.x) } }
        let xs = projected.map(\.x), ys = projected.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(), maxX > minX, maxY > minY else { return Path() }
        let scale = min(rect.width / (maxX - minX), rect.height / (maxY - minY))
        let dx = rect.midX - (maxX + minX) * scale / 2, dy = rect.midY - (maxY + minY) * scale / 2
        return Path { path in
            for (index, point) in projected.enumerated() {
                let p = CGPoint(x: point.x * scale + dx, y: point.y * scale + dy)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
    }
}

struct WeekendScreen: View {
    @EnvironmentObject private var model: MobileModel
    let meeting: Meeting
    var embedded = false
    var openSessionResults: ((Session) -> Void)?
    @State private var weather: [Int: WeekendForecast.Forecast.Hour] = [:]

    private var sessions: [Session] { meeting.sessions.sorted { $0.startTime < $1.startTime } }
    private var archivedSessions: [String: SeasonResultSession] {
        model.seasonArchive?.data.first { $0.id == meeting.id }?.sessions ?? [:]
    }

    var body: some View {
        if embedded {
            weekendContent
        } else {
            weekendContent
                .navigationTitle("Race Weekend")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .dashboardDetail()
        }
    }

    private var weekendContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: embedded ? 10 : 12) {
                overview
                if meeting.status == .scheduled {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let live = sessions.first(where: { $0.status == .live }) {
                            sessionHighlight(live, live: true, now: context.date)
                        } else if let next = sessions.first(where: { $0.status == .scheduled && $0.startTime > context.date }) {
                            sessionHighlight(next, live: false, now: context.date)
                        }
                    }
                }
                schedule
            }
            .frame(maxWidth: 640)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(WebDashboardStyle.homeText)
        .background(WebDashboardStyle.homeBackground)
        .task(id: model.dataContext + meeting.id) {
            if meeting.startDate <= .now, meeting.season == model.season {
                await model.loadSeasonArchive()
            }
        }
        .task(id: model.dataContext + meeting.id) {
            weather = [:]
            weather = await WeekendForecast.sessionHours(for: meeting.id, model: model)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                FlagBadge(countryCode: meeting.countryCode).accessibilityHidden(true)
                Text(meeting.location.isEmpty ? meeting.country : meeting.location)
                Spacer(minLength: 4)
                if let round = meeting.round {
                    Text("Round \(round)").monospacedDigit()
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(WebDashboardStyle.homeMuted)

            HStack(alignment: .center, spacing: 12) {
                Text(meeting.name)
                    .font(embedded ? .headline : .title2.bold())
                    .accessibilityAddTraits(.isHeader)
                if embedded {
                    Spacer(minLength: 0)
                    weekendCircuit.frame(width: 94)
                }
            }

            let dates = meeting.calendarDateRange()
            Text(dates.lowerBound..<dates.upperBound,
                 format: Date.IntervalFormatStyle().month(.abbreviated).day().locale(.pulseEnglish))
                .font(.subheadline)
                .foregroundStyle(WebDashboardStyle.homeMuted)

            if meeting.status != .scheduled {
                Text(meeting.status.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PulseStyle.red)
            }

            if !embedded {
                weekendCircuit
                    .frame(maxWidth: .infinity)
            }

            if let circuit = meeting.circuit, circuit.name != nil || circuit.lengthKm != nil {
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack { circuitDetails }
                    VStack(alignment: .leading, spacing: 4) { circuitDetails }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(WebDashboardStyle.homeMuted)
            }
        }
        .webHomePanel(minHeight: 0)
    }

    private var weekendCircuit: some View {
        CircuitOutlineView(meetingID: meeting.id, lineWidth: 3)
            .frame(maxWidth: 230)
            .frame(height: embedded ? 65 : 96)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var circuitDetails: some View {
        if let name = meeting.circuit?.name, !name.isEmpty {
            Text(name)
        }
        if let length = meeting.circuit?.lengthKm {
            Text("\(length.formatted(.number.precision(.fractionLength(0...3)))) km")
                .monospacedDigit()
        }
    }

    private func sessionHighlight(_ session: Session, live: Bool, now: Date) -> some View {
        let forecast = weather[WeekendForecast.hourKey(session.startTime)]
        return VStack(alignment: .leading, spacing: 7) {
            Label(live ? "In Progress" : "Next Session", systemImage: live ? "dot.radiowaves.left.and.right" : "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PulseStyle.red)
            Text(session.sessionType.resultLabel).font(.headline)
            Text(session.startTime, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                .font(.subheadline)
                .foregroundStyle(WebDashboardStyle.homeMuted)
            if !live {
                let remaining = HomeCountdownTime(start: session.startTime, now: now)
                HStack(spacing: 12) {
                    ForEach(remaining.fields, id: \.0) { unit, value in
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            PulseNumber(String(format: "%02d", value)).font(.title3.bold().monospacedDigit())
                            Text(unit).font(.caption2).foregroundStyle(WebDashboardStyle.homeMuted)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(remaining.accessibilityLabel)
            }
            if let forecast {
                HStack(spacing: 12) {
                    if let rain = forecast.precipitationProbability {
                        Label("\(rain.formatted(.number.precision(.fractionLength(0))))%", systemImage: "umbrella")
                            .accessibilityLabel("Chance of rain \(rain.formatted(.number.precision(.fractionLength(0)))) percent")
                    }
                    if let temperature = forecast.airTemp {
                        Label("\(temperature.formatted(.number.precision(.fractionLength(0))))°C", systemImage: "thermometer.medium")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(WebDashboardStyle.homeMuted)
            }
        }
        .webHomePanel(minHeight: 0)
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Weekend Schedule")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 8)
            if sessions.isEmpty {
                Text("Schedule to be confirmed.").font(.subheadline).foregroundStyle(WebDashboardStyle.homeMuted)
            }
            ForEach(sessions) { session in
                Divider()
                if hasEnded(session), let openSessionResults {
                    Button {
                        openSessionResults(session)
                    } label: {
                        sessionRow(session, showsResult: true)
                    }
                    .buttonStyle(PulsePressStyle())
                    .accessibilityIdentifier("session.\(session.id)")
                } else if hasEnded(session) {
                    NavigationLink {
                        ResultsScreen(session: session, meeting: meeting)
                            .navigationTitle("Results")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar(.visible, for: .navigationBar)
                            .dashboardDetail()
                    } label: {
                        sessionRow(session, showsResult: true)
                    }
                    .buttonStyle(PulsePressStyle())
                    .navigationLinkIndicatorVisibility(.hidden)
                    .accessibilityIdentifier("session.\(session.id)")
                } else {
                    sessionRow(session, showsResult: false)
                }
            }
        }
        .webHomePanel(minHeight: 0)
    }

    private func sessionRow(_ session: Session, showsResult: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.sessionType.resultLabel).font(.subheadline.weight(.semibold))
                if showsResult || session.status != .scheduled {
                    Text(showsResult ? "Results" : session.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(showsResult ? WebDashboardStyle.homeMuted : PulseStyle.red)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(session.startTime, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(WebDashboardStyle.homeMuted)
                Text(session.startTime, format: .dateTime.hour().minute())
                    .font(.subheadline.monospacedDigit())
            }
            if showsResult { PulseChevron() }
        }
        .padding(.vertical, embedded ? 4 : 8)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func hasEnded(_ session: Session) -> Bool {
        guard meeting.status == .scheduled,
              session.status != .cancelled, session.status != .postponed, session.status != .live else { return false }
        return session.status == .finished
            || archivedSessions[session.sessionType.rawValue]?.rows.isEmpty == false
            || (session.endTime ?? meeting.endDate) <= .now
    }
}

private struct TabletWeekendSessionResults: View {
    @EnvironmentObject private var model: MobileModel
    let meeting: Meeting
    let session: Session

    var body: some View {
        let archived = model.seasonArchive?.data.first { $0.id == meeting.id }
        let weekend = SeasonResultWeekend(meeting: meeting, sessions: archived?.sessions ?? [:],
                                          fastestLaps: archived?.fastestLaps)
        MeetingResultsDashboard(weekend: weekend, initial: session)
            .task(id: model.dataContext) { await model.loadSeasonArchive() }
    }
}

private struct HomeWeekendSchedule: View {
    @EnvironmentObject private var model: MobileModel
    @ScaledMetric(relativeTo: .footnote) private var compactMarkerLift = 8.0
    @State private var weather: [Int: WeekendForecast.Forecast.Hour] = [:]
    let meeting: Meeting
    let active: Session.ID?
    let now: Date
    var compact = false
    var minimumHeight: CGFloat = 0

    var body: some View {
        let sessions = meeting.sessions.sorted { $0.startTime < $1.startTime }
        let reached = sessions.firstIndex { $0.id == active }
        let showTemperature = sessions.contains { weather[WeekendForecast.hourKey($0.startTime)]?.airTemp != nil }
        let raceWeather = sessions.first { $0.sessionType == .race }.flatMap { weather[WeekendForecast.hourKey($0.startTime)] }
        let showVisibility = raceWeather?.visibilityMeters != nil
        VStack(alignment: .leading, spacing: 9) {
            Text("Weekend Schedule").font(.headline).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    let available = session.status != .cancelled && session.status != .postponed
                    let running = available && (session.status == .live || (session.id == active && session.startTime <= now))
                    let finished = available && (session.status == .finished || (!running && (session.endTime ?? session.startTime.addingTimeInterval(7200)) <= now))
                    let forecast = weather[WeekendForecast.hourKey(session.startTime)]
                    NavigationLink {
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            TabletWeekendSessionResults(meeting: meeting, session: session)
                        } else {
                            ResultsScreen(session: session, meeting: meeting)
                                .navigationTitle("Results")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar(.visible, for: .navigationBar)
                                .dashboardDetail()
                        }
                    } label: {
                        Group {
                            if compact {
                                compactSessionRow(session, forecast: forecast, showTemperature: showTemperature)
                            } else {
                                sessionRow(session, forecast: forecast, showVisibility: showVisibility,
                                           showTemperature: showTemperature)
                            }
                        }
                            .padding(.leading, 18)
                            .overlay(alignment: .leading) {
                                marker(filled: running || finished, reached: index == reached,
                                       above: index > 0 && index <= (reached ?? -1), below: index < (reached ?? -1))
                                    .offset(y: compact ? -compactMarkerLift : 0)
                            }
                            .contentShape(.rect)
                    }
                    .buttonStyle(PulsePressStyle())
                    .accessibilityAddTraits(running ? .isSelected : [])
                    .accessibilityIdentifier("home.session.\(session.id)")
                }
            }
        }
        .webHomePanel(minHeight: minimumHeight)
        .task(id: meeting.id) {
            weather = [:]
            weather = await WeekendForecast.sessionHours(for: meeting.id, model: model)
        }
    }

    private func compactSessionRow(_ session: Session, forecast: WeekendForecast.Forecast.Hour?,
                                   showTemperature: Bool) -> some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.sessionType.resultLabel).font(.footnote.weight(.semibold)).lineLimit(2)
                Text(relativeTime(session.startTime))
                    .font(.caption2)
                    .foregroundStyle(WebDashboardStyle.homeMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                if let forecast {
                    detail(forecast.precipitationProbability.map { "\($0.formatted(.number.precision(.fractionLength(0))))%" } ?? "—",
                           symbol: forecast.precipitationIcon, symbolAfter: true, label: "Chance of Rain", width: 38)
                    if showTemperature {
                        detail(forecast.airTemp.map { "\($0.formatted(.number.precision(.fractionLength(0))))°C" },
                               symbol: "thermometer.medium", label: "Air Temperature", width: 38)
                    }
                } else {
                    detail("—", width: 38)
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func sessionRow(_ session: Session, forecast: WeekendForecast.Forecast.Hour?,
                            showVisibility: Bool, showTemperature: Bool) -> some View {
        HStack(spacing: 5) {
            Text(session.sessionType.resultLabel)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            detail(forecast?.rainText ?? "—",
                   symbol: forecast?.rainIcon, symbolAfter: true,
                   label: forecast?.rainLabel ?? "Chance of Rain", width: 49)
//            if showVisibility {
//                detail(session.sessionType == .race ? forecast?.visibilityMeters.map { "\(($0 / 1000).formatted(.number.precision(.fractionLength(0...1)))) km" } : nil,
//                       symbol: "eye", label: "Visibility", width: 57)
//            }
            if showTemperature {
                detail(forecast?.airTemp.map { "\($0.formatted(.number.precision(.fractionLength(0))))°C" },
                       symbol: "thermometer.medium", label: "Air Temperature", width: 44)
            }
            detail(relativeTime(session.startTime), width: 104)
        }
        .padding(.vertical, 2)
        .frame(minHeight: 28.8)
        .accessibilityElement(children: .combine)
    }

    private func relativeTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day
        let day: String
        switch days {
        case -1: day = "Yesterday"
        case 0: day = "Today"
        case 1: day = "Tomorrow"
        case let offset? where abs(offset) < 7:
            day = date.formatted(.dateTime.weekday(.abbreviated).locale(.pulseEnglish))
        default:
            day = date.formatted(.dateTime.month(.abbreviated).day().locale(.pulseEnglish))
        }
        return "\(day) \(date.formatted(.dateTime.hour().minute().locale(.pulseEnglish)))"
    }

    private func marker(filled: Bool, reached: Bool, above: Bool, below: Bool) -> some View {
        let color = filled || reached ? PulseStyle.red : WebDashboardStyle.homeMuted
        return Color.clear.frame(width: 10)
            .overlay {
                VStack(spacing: 0) {
                    Rectangle().fill(above ? PulseStyle.red : .clear).frame(width: 1.5)
                    Circle().strokeBorder(color, lineWidth: 1.5)
                        .background(filled ? color : .clear, in: .circle).frame(width: 9, height: 9)
                    Rectangle().fill(below ? PulseStyle.red : .clear).frame(width: 1.5)
                }
            }
            .accessibilityHidden(true)
    }

    private func detail(_ value: String?, symbol: String? = nil, symbolAfter: Bool = false, label: String? = nil, width: CGFloat) -> some View {
        HStack(spacing: 2) {
            if let value {
                if let symbol, !symbolAfter { Image(systemName: symbol) }
                Text(value).lineLimit(1).minimumScaleFactor(0.75)
                if let symbol, symbolAfter { Image(systemName: symbol) }
            }
        }
            .font(.caption2.monospacedDigit()).foregroundStyle(WebDashboardStyle.homeMuted)
            .frame(width: width, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([label, value].compactMap { $0 }.joined(separator: " "))
            .accessibilityHidden(value == nil)
    }
}

private struct WeekendForecast: Decodable {
    struct Forecast: Decodable {
        struct Hour: Decodable {
            let utc: String
            let airTemp: Double?
            let precipitationProbability: Double?
            let visibilityMeters: Double?
            let precipitation: Double?
            let weatherCode: Int?
            let windSpeed: Double?
            let rainfall: Double?

            /// Finished sessions return measured observations, which carry
            /// rainfall instead of an Open-Meteo probability.
            var rainText: String? {
                if let rainfall { return rainfall > 0 ? "Rain" : "Dry" }
                return precipitationProbability.map { "\($0.formatted(.number.precision(.fractionLength(0))))%" }
            }

            var rainIcon: String? {
                if let rainfall { return rainfall > 0 ? "cloud.rain" : "sun.max" }
                return precipitationIcon
            }

            var rainLabel: String {
                rainfall == nil ? "Chance of Rain" : "Rain"
            }

            var precipitationIcon: String? {
                guard let precipitation, precipitation >= 0 else { return nil }
                switch precipitation {
                case 0:
                    switch weatherCode {
                    case 0: return "sun.max"
                    case 1, 2: return "cloud.sun"
                    case 45, 48: return "cloud.fog"
                    default: return "cloud"
                    }
                case ..<1: return "cloud.drizzle"
                case ..<4: return "cloud.rain"
                default: return "cloud.heavyrain"
                }
            }
        }
        let status: String
        let hours: [Hour]
    }
    struct Meta: Decodable { let stale: Bool }
    let data: Forecast
    let meta: Meta

    static func hourKey(_ date: Date) -> Int {
        Int(floor(date.timeIntervalSince1970 / 3600))
    }

    @MainActor
    static func sessionHours(for meetingID: Meeting.ID, model: MobileModel) async -> [Int: Forecast.Hour] {
        guard let url = model.serverURL else { return [:] }
        let context = model.dataContext
        let client = APIClient(baseURL: url)
        guard let bytes = try? await client.mapData(path: "/api/v1/meetings/\(meetingID)/weather", token: model.currentToken),
              let forecast = try? JSONDecoder().decode(Self.self, from: bytes),
              !forecast.meta.stale, !Task.isCancelled, model.dataContext == context else { return [:] }
        let parser = ISO8601DateFormatter()
        var hours: [Int: Forecast.Hour] = [:]
        for hour in forecast.data.hours {
            if let date = parser.date(from: hour.utc) {
                hours[hourKey(date)] = hour
            }
        }
        return hours
    }
}
