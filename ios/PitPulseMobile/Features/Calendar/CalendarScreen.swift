import SwiftUI
import SharedComponents
import SharedData

struct WebHomeScreen<Header: View>: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var constructors: APIEnvelope<[ConstructorStanding]>?
    @State private var loadingConstructors = true
    @State private var expandedCountdown: NextSession?
    @Namespace private var countdownTransition
    let header: Header
    let openTab: (DashboardTab) -> Void

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                let gap: CGFloat = viewport.size.width <= 600 ? 12 : 16
                ScrollView {
                    VStack(spacing: gap) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let current = schedule(at: context.date)
                            VStack(spacing: gap) {
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
                        let drivers = model.driverRoster.map(StandingEntry.init(driver:))
                        let teams = (constructors?.data ?? []).map(StandingEntry.init(team:))
                        if viewport.size.width > 600 && !typeSize.isAccessibilitySize {
                            HStack(alignment: .top, spacing: gap) {
                                homeStandings(drivers, teams: false)
                                homeStandings(teams, teams: true)
                            }
                        } else {
                            homeStandings(drivers, teams: false)
                            homeStandings(teams, teams: true)
                        }
                        if model.seasonArchive == nil && model.seasonArchiveError == nil {
                            PulseSkeleton(rows: 3, label: "Loading race highlights")
                        } else {
                            WebHomeRecords(weekends: model.seasonArchive?.data ?? [], season: model.season) {
                                openTab(.results)
                            }
                        }
                    }
                    .padding(gap)
                    .pulseSwap(model.loadState.isLoading)
                    .pulseSwap(model.seasonArchive != nil)
                }
                .scrollIndicators(.hidden)
            }
            .foregroundStyle(WebDashboardStyle.homeText)
            .background(WebDashboardStyle.homeBackground)
            .dashboardHeader(header)
            .fullScreenCover(isPresented: Binding(
                get: { expandedCountdown != nil },
                set: { if !$0 { expandedCountdown = nil } }
            )) {
                if let target = expandedCountdown {
                    LandscapeCover(background: homeCountdownGradient) { close in
                        HomeCountdownFullscreen(title: "\(place(target.meeting)): \(target.session.sessionType.webTitle)",
                                                start: target.session.startTime, close: close)
                    }
                    .pulseNavigationZoom("home-countdown", in: countdownTransition)
                }
            }
            .task(id: model.dataContext) {
                constructors = nil
                loadingConstructors = true
                await load()
            }
            .refreshable {
                async let calendar: Void = model.loadCalendar(force: true)
                async let roster: Void = model.loadF1Roster(force: true)
                await load(force: true)
                _ = await (calendar, roster)
            }
        }
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
        return (sessions.first, sessions.first?.meeting ?? meetings.last)
    }

    private func countdown(_ active: NextSession?, now: Date) -> some View {
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
                    Text(meetings.isEmpty ? "Schedule unavailable" : "Season complete")
                        .font(.system(size: 21, weight: .bold))
                    Text(meetings.isEmpty ? "No sessions have been published." : "Explore this season’s results and records.")
                        .font(.system(size: 12))
                }
            }.foregroundStyle(.white)
                .webHomePanel(fill: homeCountdownGradient, line: Color(red: 0.81, green: 0.61, blue: 0.61))
    }

    private func sessionTimes(_ meeting: Meeting, active: Session.ID?, now: Date) -> some View {
        HomeWeekendSchedule(meeting: meeting, active: active, now: now)
            .id(model.dataContext + meeting.id)
    }

    private func schedulePanel(stretch: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let display = schedule(at: context.date).display
            let finished = Set((model.seasonArchive?.data ?? []).filter { $0.sessions["race"]?.rows.isEmpty == false }.map(\.id))
            let total = meetings.count
            let completed = meetings.count { finished.contains($0.id) }
            VStack(alignment: .leading, spacing: 12) {
                Text("\(String(model.season)) Schedule").font(.headline)
                HStack(spacing: 6) {
                    if let display {
                        FlagBadge(countryCode: display.countryCode, width: 34, height: 18).accessibilityHidden(true)
                    }
                    Text(display.map(place) ?? "No schedule").font(.system(size: 20, weight: .bold))
                }
                HStack(spacing: 6) {
                    HStack(spacing: 1) {
                        ForEach(0..<total, id: \.self) { index in
                            Rectangle().fill(index < completed ? Color(red: 0.08, green: 0.50, blue: 0.24) : Color.gray.opacity(0.40))
                                .frame(maxWidth: 2, maxHeight: 10)
                        }
                    }
                    PulseNumber("\(total == 0 ? 0 : Int((Double(completed) / Double(total) * 100).rounded()))%")
                        .font(.system(size: 10)).monospacedDigit().fixedSize()
                }
                .accessibilityLabel("\(completed) of \(total) races with results")
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
                        AssetImage(name: MotorsportAssetName.helmetName(driverID: driver.id, name: driver.driverName, season: driver.season))
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

    private var repositoryURL: URL { URL(string: "https://github.com/aczeccssa/PitPulse")! }

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Support PitPulse and help us build a better racing companion.")
                .font(.system(size: 12)).foregroundStyle(WebDashboardStyle.homeMuted)
            Link(destination: repositoryURL) {
                Label("Support Us on GitHub", systemImage: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .padding(8).background(Color(red: 0.84, green: 0.13, blue: 0.16), in: .rect(cornerRadius: 6))
            }.buttonStyle(.plain)
        }.webHomePanel()
    }

    private var promoCard: some View {
        Link(destination: repositoryURL) {
            HStack(spacing: 9) {
                MotorsportImages.image(named: MotorsportAssetName.brandLogoName).resizable().scaledToFit()
                    .frame(width: 34, height: 42).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("macOS · iOS").font(.system(size: 10, weight: .semibold))
                    Text("PitPulse").font(.system(size: 17, weight: .bold))
                    Text("Your race. Always in reach.").font(.system(size: 11))
                    Text("Explore the App ↗").font(.system(size: 11, weight: .semibold))
                }
            }.webHomePanel()
        }.buttonStyle(.plain)
    }

    private func homeStandings(_ entries: [StandingEntry], teams: Bool) -> some View {
        let loading = entries.isEmpty && (teams ? loadingConstructors : model.serverURL != nil && model.rosterLoadError == nil)
        return Group {
            if loading {
                PulseSkeleton(label: teams ? "Loading constructor standings…" : "Loading driver standings…")
            } else {
                standings(entries, teams: teams)
            }
        }
        .pulseSwap(loading)
    }

    private func standings(_ entries: [StandingEntry], teams: Bool) -> some View {
        let name = teams ? "Constructor" : "Driver"
        let sorted = Array(entries.sorted { $0.position < $1.position }.prefix(3))
        return Button { openTab(teams ? .constructors : .drivers) } label: {
          VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(String(model.season)) \(name) Standings")
                        .font(.headline)
                    Spacer(minLength: 8)
                    PulseChevron()
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
            Spacer(minLength: 8)
          }.webHomePanel(inset: 0, minHeight: 0).contentShape(PulseStyle.cardShape)
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
        GeometryReader { geometry in
            let size = geometry.size
            Color.clear.keyframeAnimator(initialValue: 1.0, trigger: value) { _, phase in
                let animating = !reduceMotion && previous != value
                ZStack {
                    VStack(spacing: 0) {
                        face(value, top: true, size: size)
                        face(animating && phase < 0.5 ? previous : value, top: false, size: size)
                    }
                    if animating && phase < 0.5 {
                        face(previous, top: true, size: size)
                            .rotation3DEffect(.degrees(-phase * 180), axis: (1, 0, 0), anchor: .bottom)
                            .frame(maxHeight: .infinity, alignment: .top)
                    } else if animating && phase < 1 {
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
                }.webHomePanel(inset: 16, minHeight: 0).contentShape(PulseStyle.cardShape)
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
                    AssetImage(name: MotorsportAssetName.helmetName(driverID: record.row.id,
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

struct CalendarScreen: View {
    @EnvironmentObject private var model: MobileModel
    @State private var mode = 0
    @State private var filter = 0
    @State private var search = ""

    private var filteredMeetings: [Meeting] {
        model.meetings.filter { meeting in
            let matchesSearch = search.isEmpty || [meeting.name, meeting.location, meeting.country].contains {
                $0.localizedCaseInsensitiveContains(search)
            }
            let upcoming = meeting.endDate >= .now && meeting.status != .cancelled
            return matchesSearch && (filter == 0 || (filter == 1 ? upcoming : !upcoming))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                PulseSectionPicker(sections: [(0, "Calendar"), (1, "Results")], selection: $mode)
                    .padding(.horizontal, 20)
                if mode == 0 { calendar } else { SeasonResultsIndex() }
            }
            .background(PulseStyle.background)
            .navigationTitle("Race")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { PulseSettingsButton() }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if mode == 0 {
                        Menu {
                            Picker("Calendar Range", selection: $filter) {
                                Text("All").tag(0)
                                Text("Upcoming").tag(1)
                                Text("Completed").tag(2)
                            }
                        } label: {
                            Label("Filter Races", systemImage: filter == 0 ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                        }
                    }
                }
            }
        }
    }

    private var calendar: some View {
        ScrollViewReader { reader in
            List {
                ForEach(filteredMeetings) { meeting in row(meeting).id(meeting.id) }
                if filteredMeetings.isEmpty {
                    if model.loadState.isLoading { PulseSkeleton(label: "Loading schedule…") }
                    else { ContentUnavailableView("No Schedule Available", systemImage: "calendar", description: model.loadState.errorText.map { Text($0.pulseEnglishError) }) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .searchable(text: $search, prompt: "Search races or locations")
            .onChange(of: model.meetings.map(\.id), initial: true) { _, _ in
                if filter == 0, search.isEmpty, let next = CalendarLogic.featuredMeeting(in: model.meetings, now: .now) {
                    reader.scrollTo(next.id, anchor: .center)
                }
            }
        }
        .refreshable { await model.loadCalendar(force: true) }
    }

    private func row(_ meeting: Meeting) -> some View {
        NavigationLink { WeekendScreen(meeting: meeting) } label: {
            HStack(spacing: 14) {
                Text(meeting.round.map(String.init) ?? "—").font(.system(size: 30, weight: .heavy, design: .rounded)).frame(width: 42, alignment: .leading)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        FlagBadge(countryCode: meeting.countryCode).accessibilityHidden(true)
                        Text(meeting.location).font(.caption.weight(.semibold))
                    }
                    Text(meeting.name).font(.headline).lineLimit(2)
                    Text(meeting.startDate, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                CircuitOutlineView(meetingID: meeting.id).frame(width: 77, height: 42).accessibilityHidden(true)
            }.padding(.vertical, 10)
        }.accessibilityIdentifier("meeting.\(meeting.id)").listRowBackground(PulseStyle.background).listRowSeparator(.hidden)
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
    @State private var section = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var weekendResults: [String: SeasonResultSession] {
        model.seasonArchive?.data.first { $0.id == meeting.id }?.sessions ?? [:]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(meeting.name).font(.largeTitle.bold())
                Text("\(meeting.location), \(meeting.country)").foregroundStyle(.secondary)
                Picker("Race Weekend", selection: $section) {
                    Text("Overview").tag(0)
                    Text("Schedule").tag(1)
                    Text("Weather").tag(2)
                    Text("Results").tag(3)
                }.pickerStyle(.segmented)
                switch section {
                case 0:
                    CircuitOutlineView(meetingID: meeting.id).frame(height: 120)
                    LabeledContent("Circuit", value: meeting.circuit?.name ?? meeting.location)
                    LabeledContent("Dates", value: meeting.startDate.formatted(.dateTime.year().month(.abbreviated).day().locale(.pulseEnglish)))
                    if meeting.status != .scheduled { LabeledContent("Status", value: meeting.status.rawValue.capitalized) }
                case 2:
                    WeekendWeather(meetingID: meeting.id)
                case 3:
                    results
                default:
                    schedule
                }
            }.padding(20)
        }
        .background(PulseStyle.background)
        .navigationTitle("Race Weekend")
        .navigationBarTitleDisplayMode(.inline)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: section)
        .task(id: model.dataContext) {
            if meeting.startDate <= .now, meeting.season == model.season { await model.loadSeasonArchive() }
        }
    }

    private var schedule: some View {
        VStack(spacing: 16) {
            ForEach(meeting.sessions.sorted { $0.startTime < $1.startTime }) { session in
                if canOpenResults(session) {
                    resultsLink(session) {
                        timing(session)
                    }
                } else {
                    timing(session)
                }
            }
        }
    }

    @ViewBuilder private var results: some View {
        let finished = meeting.sessions.filter { canOpenResults($0) && result($0) != nil }
            .sorted { $0.startTime > $1.startTime }
        if !finished.isEmpty {
            ForEach(finished) { session in
                resultsLink(session) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.sessionType.resultLabel).font(.headline)
                        if let leader = result(session)?.rows.first(where: { $0.position == 1 }) {
                            Text("P1  \(leader.driverName)").font(.subheadline)
                        }
                        Text(statusLabel(session)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } else if let error = model.seasonArchiveError {
            Text(error.pulseEnglishError).foregroundStyle(.secondary)
            Button("Retry") { Task { await model.loadSeasonArchive(force: true) } }
        } else if meeting.startDate <= .now && model.seasonArchive == nil {
            PulseSkeleton(label: "Loading weekend results…")
        } else {
            ContentUnavailableView("No Weekend Results", systemImage: "flag.checkered")
        }
    }

    private func timing(_ session: Session) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(session.sessionType.resultLabel).font(.headline)
                Text(statusLabel(session)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(session.startTime, format: .dateTime.weekday().hour().minute())
                .font(.subheadline.monospacedDigit())
        }
    }

    private func resultsLink<Label: View>(_ session: Session, @ViewBuilder label: () -> Label) -> some View {
        NavigationLink {
            ResultsScreen(session: session, meeting: meeting)
                .navigationTitle("Results")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack {
                label()
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(PulsePressStyle()).accessibilityIdentifier("session.\(session.id)")
    }

    private func result(_ session: Session) -> SeasonResultSession? {
        guard let data = weekendResults[session.sessionType.rawValue], !data.rows.isEmpty else { return nil }
        return data
    }

    private func canOpenResults(_ session: Session) -> Bool {
        guard session.status != .cancelled, session.status != .postponed, session.status != .live else { return false }
        return session.status == .finished || result(session) != nil || (session.endTime ?? meeting.endDate) <= .now
    }

    private func statusLabel(_ session: Session) -> String {
        if session.status == .cancelled || session.status == .postponed || session.status == .live {
            return session.status.rawValue.capitalized
        }
        if let report = result(session) {
            return report.meta.stale ? "Results are stale" : "Results · \(report.meta.quality.rawValue.capitalized)"
        }
        if canOpenResults(session) { return "Awaiting Results" }
        return session.startTime <= .now ? "To Be Confirmed" : "Not Started"
    }
}

private struct HomeWeekendSchedule: View {
    @EnvironmentObject private var model: MobileModel
    @State private var weather: [Int: WeekendForecast.Forecast.Hour] = [:]
    let meeting: Meeting
    let active: Session.ID?
    let now: Date

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd hh:mm a"
        return formatter
    }()

    var body: some View {
        let sessions = meeting.sessions.sorted { $0.startTime < $1.startTime }
        let reached = sessions.firstIndex { $0.id == active }
        let showTemperature = sessions.contains { weather[hourKey($0.startTime)]?.airTemp != nil }
        let raceWeather = sessions.first { $0.sessionType == .race }.flatMap { weather[hourKey($0.startTime)] }
        let showVisibility = raceWeather?.visibilityMeters != nil
        let showRain = raceWeather?.precipitationProbability != nil
        VStack(alignment: .leading, spacing: 9) {
            Text("Weekend Schedule").font(.headline).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    let available = session.status != .cancelled && session.status != .postponed
                    let running = available && (session.status == .live || (session.id == active && session.startTime <= now))
                    let finished = available && (session.status == .finished || (!running && (session.endTime ?? session.startTime.addingTimeInterval(7200)) <= now))
                    let forecast = weather[hourKey(session.startTime)]
                    HStack(spacing: 5) {
                        Text(session.sessionType.resultLabel)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                        if showRain {
                            detail(session.sessionType == .race ? forecast?.precipitationProbability.map { "\($0.formatted(.number.precision(.fractionLength(0))))%" } : nil,
                                   symbol: "umbrella", label: "Chance of Rain", width: 41)
                        }
                        if showVisibility {
                            detail(session.sessionType == .race ? forecast?.visibilityMeters.map { "\(($0 / 1000).formatted(.number.precision(.fractionLength(0...1)))) km" } : nil,
                                   symbol: "eye", label: "Visibility", width: 57)
                        }
                        if showTemperature {
                            detail(forecast?.airTemp.map { "\($0.formatted(.number.precision(.fractionLength(0))))°C" }, label: "Air Temperature", width: 29)
                        }
                        detail(Self.clock.string(from: session.startTime), width: 91)
                    }
                    .padding(.vertical, 5)
                    .frame(minHeight: 33)
                    .padding(.leading, 18)
                    .overlay(alignment: .leading) {
                        marker(filled: running || finished, reached: index == reached,
                               above: index > 0 && index <= (reached ?? -1), below: index < (reached ?? -1))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(running ? .isSelected : [])
                }
            }
        }
        .webHomePanel(minHeight: 0)
        .task {
            guard let url = model.serverURL else { return }
            do {
                let data = try await APIClient(baseURL: url).mapData(path: "/api/v1/meetings/\(meeting.id)/weather", token: model.currentToken)
                let forecast = try JSONDecoder().decode(WeekendForecast.self, from: data)
                guard !forecast.meta.stale else { return }
                let parser = ISO8601DateFormatter()
                for hour in forecast.data.hours {
                    if let date = parser.date(from: hour.utc) { weather[hourKey(date)] = hour }
                }
            } catch { weather = [:] }
        }
    }

    private func hourKey(_ date: Date) -> Int { Int(floor(date.timeIntervalSince1970 / 3600)) }

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

    private func detail(_ value: String?, symbol: String? = nil, label: String? = nil, width: CGFloat) -> some View {
        HStack(spacing: 2) {
            if let value {
                if let symbol { Image(systemName: symbol) }
                Text(value).lineLimit(1).minimumScaleFactor(0.75)
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
            let rainfall: Double?
            let windSpeed: Double?
        }
        let status: String
        let hours: [Hour]
    }
    struct Meta: Decodable { let stale: Bool }
    let data: Forecast
    let meta: Meta
}

private struct WeekendWeather: View {
    @EnvironmentObject private var model: MobileModel
    let meetingID: String
    @State private var forecast: WeekendForecast?
    @State private var error: String?
    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("Track Weather", systemImage: "cloud.sun").font(.headline)
                if let forecast {
                    if forecast.data.status == "historical" {
                        Text("Archived Observations").font(.caption).foregroundStyle(.secondary)
                    }
                    if forecast.meta.stale { Text("Cached Weather Is Stale").font(.caption).foregroundStyle(.orange) }
                    if forecast.data.hours.isEmpty {
                        Text(["past_event", "history_pending"].contains(forecast.data.status) ? "Historical weather is not available yet." : "This session is outside the forecast window.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(Array(forecast.data.hours.enumerated()), id: \.offset) { _, hour in
                        HStack {
                            Text(ISO8601DateFormatter().date(from: hour.utc)?.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(.pulseEnglish)) ?? hour.utc).font(.caption2)
                            Spacer()
                            Text(hour.airTemp.map { "\($0.formatted())°C" } ?? "—")
                            Text(hour.rainfall.map { $0 > 0 ? "Rain" : "Dry" } ?? hour.precipitationProbability.map { "\($0.formatted())%" } ?? "—").foregroundStyle(.secondary)
                        }.font(.caption.monospacedDigit())
                    }
                } else if let error { Text(error.pulseEnglishError).font(.caption).foregroundStyle(.orange) }
                else { PulseSkeleton(label: "Loading weather…") }
            }
        }
        .task(id: meetingID) {
            guard let url = model.serverURL else { error = "Invalid server address"; return }
            do {
                let data = try await APIClient(baseURL: url).mapData(path: "/api/v1/meetings/\(meetingID)/weather", token: model.currentToken)
                forecast = try JSONDecoder().decode(WeekendForecast.self, from: data)
            } catch { self.error = MobileModel.message(for: error).pulseEnglishError }
        }
    }
}
