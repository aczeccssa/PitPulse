import SharedComponents
import SharedData
import SwiftUI
import UIKit

enum WeekendResultPanel: Equatable { case grid, progress }

struct ResultsScreen<WeekendTools: View>: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.openDashboardDriverProfile) private var openDashboardDriverProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let session: Session
    let meeting: Meeting
    var availableSessions: [Session] = []
    var selectSession: ((Session) -> Void)?
    var selectedPanel: WeekendResultPanel? = nil
    var hasStartingGrid = false
    var selectPanel: ((WeekendResultPanel) -> Void)? = nil
    @ViewBuilder var weekendTools: () -> WeekendTools
    @State private var response: APIEnvelope<[SessionResult]>?
    @State private var error: String?
    @State private var showFinishGaps = false
    @State private var viewportHeight: CGFloat = 0
    @State private var sideBySide = false
    @State private var selectedDriverID: String?
    @State private var showsCompactAnalysis = false
    @State private var shownProfile: String?
    @State private var profileDestination: DriverProfileDestination?

    private var selectedDriver: SessionResult? {
        rows.first { $0.driverId == selectedDriverID }
    }

    private var tabletArchive: Bool { UIDevice.current.userInterfaceIdiom == .pad && selectSession != nil }
    private var isRace: Bool { session.sessionType == .race || session.sessionType == .sprint }
    private var isQualifying: Bool { session.sessionType == .qualifying || session.sessionType == .sprintQualifying }
    private var rows: [SessionResult] {
        let archived = model.seasonArchive?.data.first { $0.id == meeting.id }?
            .sessions[session.sessionType.rawValue]?.rows ?? []
        let archiveNumbers = Dictionary(
            archived.compactMap { row in row.resultNumber.map { (row.driverId, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        return (response?.data ?? [])
            .map { row in
                guard row.resultNumber == nil, let number = archiveNumbers[row.driverId] else { return row }
                var result = row
                result.driverNumber = String(number.dropFirst())
                return result
            }
            .sorted { ($0.position ?? Int.max, $0.id) < ($1.position ?? Int.max, $1.id) }
    }

    var body: some View {
        GeometryReader { viewport in
            HStack(spacing: 0) {
                resultsList(workspaceWidth: viewport.size.width)
                    .frame(width: sideBySide ? min(460, viewport.size.width * 0.46) : viewport.size.width)
                if sideBySide {
                    Divider()
                    Group {
                        if let selectedDriver {
                            driverAnalysis(selectedDriver, embedded: true)
                                .id(selectedDriver.driverId)
                        } else {
                            ContentUnavailableView("Select a Driver", systemImage: "chart.xyaxis.line",
                                                   description: Text("Choose a driver from the results to view lap pace, sectors, and stints."))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if tabletArchive { tabletMeetingHeader }
        }
        .background(WebDashboardStyle.homeBackground)
        .onGeometryChange(for: Bool.self) { geometry in
            UIDevice.current.userInterfaceIdiom == .pad && selectSession == nil && geometry.size.width >= 820 && !typeSize.isAccessibilitySize
        } action: { wide in
            sideBySide = wide
            showsCompactAnalysis = !wide && selectedDriver != nil
        }
        .navigationDestination(item: $profileDestination) { target in
            switch target {
            case .stats(let entry):
                StandingProfile(entry: entry, driversDesign: true)
            case .comparison(let driver, let teammate):
                TeammateComparisonBoard(initialDriver: driver, teammate: teammate)
                    .navigationTitle("Head to Head")
            }
        }
        .navigationDestination(isPresented: $showsCompactAnalysis) {
            if let selectedDriver { driverAnalysis(selectedDriver) }
        }
    }

    private func driverAnalysis(_ row: SessionResult, embedded: Bool = false) -> some View {
        DriverAnalysisScreen(sessionID: session.id, driver: row, season: meeting.season,
                             sessionLabel: session.sessionType.resultLabel, embedded: embedded)
    }

    private func resultsList(workspaceWidth: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !tabletArchive { meetingHeader }
                if tabletArchive && selectedPanel != .progress { meetingStats }
                if tabletArchive {
                    VStack(alignment: .leading, spacing: 14) {
                        sessionHeader
                        resultContent(workspaceWidth: workspaceWidth)
                    }
                    .padding(16)
                    .dashboardPanel(WebDashboardStyle.homePanel, line: resultTableLine)
                } else {
                    weekendTools()
                    sessionHeader
                    resultContent(workspaceWidth: workspaceWidth)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .foregroundStyle(WebDashboardStyle.homeText)
        .background(WebDashboardStyle.homeBackground)
        .pulseSwap(response != nil)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .sheet(isPresented: $showFinishGaps) {
            ResultFittedSheet(maximumHeight: viewportHeight) {
                RaceFinishGaps(rows: rows, season: meeting.season)
            }
        }
        .task(id: model.dataContext) {
            error = nil
            if let archived = model.seasonArchive?.data.first(where: { $0.id == meeting.id })?
                .sessions[session.sessionType.rawValue], !archived.rows.isEmpty {
                response = APIEnvelope(data: archived.rows, meta: archived.meta)
            } else {
                response = nil
            }
            await load()
        }
        .refreshable { await load() }
    }

    @ViewBuilder private func resultContent(workspaceWidth: CGFloat) -> some View {
        if selectedPanel != nil {
            weekendTools()
        } else if tabletArchive && response != nil {
            tabletClassification(workspaceWidth: workspaceWidth)
        } else if !rows.isEmpty {
            if isRace { podium }
            classification
        } else if response != nil {
            ContentUnavailableView("No Results Yet", systemImage: "flag.checkered",
                                   description: Text("Results appear once the session ends and the server syncs them."))
        } else if error == nil {
            PulseSkeleton(label: "Loading session results…")
                .frame(maxWidth: .infinity)
                .padding(16)
        }

        if selectedPanel == nil, let error {
            VStack(alignment: .leading, spacing: 8) {
                Text(error).foregroundStyle(WebDashboardStyle.homeMuted)
                Button("Retry") { Task { await load() } }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardPanel(WebDashboardStyle.homePanel)
        }
    }

    private var tabletMeetingHeader: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("results.archive.back")

            FlagBadge(countryCode: meeting.countryCode, width: 20).accessibilityHidden(true)
            Text("\(meeting.name) Result")
                .font(.headline)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(WebDashboardStyle.homeText)
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .background(WebDashboardStyle.homePanel)
    }

    private var meetingHeader: some View {
        let round = meeting.round.map { "R\($0) · \(meeting.season)" } ?? String(meeting.season)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FlagBadge(countryCode: meeting.countryCode).accessibilityHidden(true)
                Text(round).font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PulseStyle.red)
            }
            Text(meeting.name).font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if let name = meeting.circuit?.name, !name.isEmpty {
                Text(name).font(.subheadline).foregroundStyle(WebDashboardStyle.homeMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .dashboardPanel(WebDashboardStyle.homePanel)
    }

    private var meetingStats: some View {
        let archive = model.seasonArchive?.data.first { $0.id == meeting.id }
        let race = archive?.sessions["race"]?.rows ?? []
        let winner = race.first { $0.position == 1 }
        let pole = archive?.sessions["qualifying"]?.rows.first { $0.position == 1 }
        let fastest = race.compactMap { row -> (row: SessionResult, seconds: Double)? in
            guard let lap = row.bestLap, let seconds = resultTimeSeconds(lap) else { return nil }
            return (row, seconds)
        }.min { $0.seconds < $1.seconds }?.row
        return HStack(alignment: .top, spacing: 16) {
            meetingStat("Race Winner", icon: "web-result-race-winner", driver: winner, value: winner?.raceTime ?? winner?.time)
            meetingStat("Pole Position", icon: "web-result-pole-position", driver: pole, value: pole?.q3 ?? pole?.time)
            meetingStat("Fastest Lap", icon: "web-result-fastest-lap", driver: fastest, value: fastest?.bestLap)
        }
    }

    private func resultTimeSeconds(_ time: String) -> Double? {
        let pieces = time.split(separator: ":", omittingEmptySubsequences: false)
        let values = pieces.compactMap { Double($0) }
        guard !values.isEmpty, pieces.count == values.count else { return nil }
        return values.reduce(0) { $0 * 60 + $1 }
    }

    private func meetingStat(_ title: String, icon: String, driver: SessionResult?, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 7) {
                if let driver {
                    AssetImage(name: MotorsportAssetName.name(kind: .teamLogo, id: driver.constructorId, season: meeting.season))
                        .frame(width: 23, height: 20).accessibilityHidden(true)
                    Text(driver.driverName.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? driver.driverName)
                } else {
                    Text("—")
                }
            }.font(.system(size: 18, weight: .semibold))
            Text(value ?? "—").font(.system(size: 15).monospacedDigit())
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .dashboardPanel(WebDashboardStyle.homePanel, line: resultTableLine)
        .overlay(alignment: .topTrailing) {
            Image(icon).resizable().frame(width: 18, height: 18)
                .frame(width: 28, height: 28)
                .foregroundStyle(WebDashboardStyle.homeMuted)
                .background(WebDashboardStyle.adaptive(dark: 0x121822, light: 0xf6f6f6), in: .circle)
                .padding(14)
                .accessibilityHidden(true)
        }
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if tabletArchive, let selectSession, let selectPanel {
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        ForEach(availableSessions) { choice in
                            if choice.sessionType == .race && hasStartingGrid {
                                tabletResultTab("Starting Grid", active: selectedPanel == .grid) { selectPanel(.grid) }
                            }
                            tabletResultTab(choice.sessionType.webTitle, active: selectedPanel == nil && choice.id == session.id) {
                                selectSession(choice)
                            }
                        }
                        if hasStartingGrid && !availableSessions.contains(where: { $0.sessionType == .race }) {
                            tabletResultTab("Starting Grid", active: selectedPanel == .grid) { selectPanel(.grid) }
                        }
                        Rectangle().fill(resultTableLine).frame(width: 1, height: 20)
                            .padding(.leading, 3)
                        tabletResultTab("↗  Progress", active: selectedPanel == .progress) { selectPanel(.progress) }
                    }
                    .padding(4)
                    .background(WebDashboardStyle.adaptive(dark: 0x1c2027, light: 0xf1f1f1), in: .rect(cornerRadius: 6))
                }
                .scrollIndicators(.hidden)
            } else if let selectSession, availableSessions.count > 1 {
                let columns = typeSize.isAccessibilitySize ? 2 : (availableSessions.count > 5
                                                                  ? (availableSessions.count + 1) / 2 : availableSessions.count)
                VStack(spacing: 2) {
                    ForEach(Array(stride(from: 0, to: availableSessions.count, by: columns)), id: \.self) { start in
                        let end = min(start + columns, availableSessions.count)
                        SessionChoiceRow {
                            ForEach(availableSessions[start..<end]) { choice in
                                let active = choice.id == session.id
                                Button {
                                    if !active { selectSession(choice) }
                                } label: {
                                    Text(choice.sessionType.resultLabel)
                                        .modifier(ResultSessionStyle(active: active))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(active ? .isSelected : [])
                            }
                        }
                    }
                }
            } else {
                Text(session.sessionType.resultLabel).font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }

            if !tabletArchive {
                Text(session.startTime, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(WebDashboardStyle.homeMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabletResultTab(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(active ? PulseStyle.red.opacity(0.14) : .clear, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? PulseStyle.red : WebDashboardStyle.homeMuted)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder private var podium: some View {
        let finishers = rows.filter { (1...3).contains($0.position ?? 0) && $0.classification.uppercased() == "CLASSIFIED" }
        if !finishers.isEmpty {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            VStack(alignment: .leading, spacing: 10) {
                Text("Podium").font(.headline).accessibilityAddTraits(.isHeader)
                layout {
                    ForEach(finishers) { row in
                        VStack(spacing: 6) {
                            helmet(row).frame(width: 52, height: 43)
                            ResultDriverName(name: row.driverName)
                            HStack(spacing: 5) {
                                AssetImage(name: MotorsportAssetName.name(
                                    kind: .teamLogo, id: row.constructorId, season: meeting.season
                                ))
                                .frame(width: 20, height: 14)
                                if let number = row.resultNumber {
                                    Text(number).font(.caption.monospacedDigit())
                                        .foregroundStyle(WebDashboardStyle.homeMuted)
                                }
                            }
                            .frame(minHeight: 17)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel([row.team, row.resultNumber].compactMap { $0 }.joined(separator: ", "))
                            if let position = row.position {
                                Text("P\(position)")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(PulseStyle.red)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .background(DashboardArt.teamColor(row.constructorId).opacity(0.12),
                                    in: .rect(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(14)
            .dashboardPanel(WebDashboardStyle.homePanel)
        }
    }

    private var showsPhaseColumns: Bool {
        isQualifying && rows.contains { $0.q1 != nil || $0.q2 != nil || $0.q3 != nil }
    }

    private func tabletClassification(workspaceWidth: CGFloat) -> some View {
        let ordered = rows.sorted {
            if $0.position != $1.position { return ($0.position ?? Int.max) < ($1.position ?? Int.max) }
            if $0.laps != $1.laps { return ($0.laps ?? 0) > ($1.laps ?? 0) }
            return $0.driverId < $1.driverId
        }
        let fields = isQualifying ? ["Q1", "Q2", "Q3"] : isRace
            ? ["TIME", "GAP TO LEADER", "INTERVAL", "POINTS", "LAPS"] : ["TIME", "GAP", "LAPS"]
        return ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(["POS.", "NO.", "DRIVER", "TEAM"] + fields, id: \.self) { title in
                        Text(title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WebDashboardStyle.homeMuted)
                            .padding(.top, 8)
                            .padding(.bottom, 10)
                            .padding(.horizontal, 6)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: .infinity, alignment: fields.contains(title) ? .trailing : .leading)
                            .gridColumnAlignment(fields.contains(title) ? .trailing : .leading)
                    }
                }
                .accessibilityAddTraits(.isHeader)
                Rectangle().fill(resultTableLine).frame(height: 1)
                if ordered.isEmpty {
                    Text("No results available for this session.")
                        .foregroundStyle(WebDashboardStyle.homeMuted)
                        .padding(.vertical, 16)
                        .gridCellColumns(4 + fields.count)
                }
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, row in
                    tabletClassificationRow(row, leader: ordered.first, previous: index > 0 ? ordered[index - 1] : nil)
                    Rectangle().fill(resultTableLine).frame(height: 1)
                }
            }
            .frame(minWidth: max(isRace ? 690 : 550, workspaceWidth - 64))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabletClassificationRow(_ row: SessionResult, leader: SessionResult?, previous: SessionResult?) -> some View {
        let classified = row.classification.uppercased() == "CLASSIFIED"
        let elapsed = row.raceTime ?? row.time ?? row.bestLap
        let result = isRace && !classified
            ? (row.laps == 0 ? "DNS" : row.classification.uppercased()) : (elapsed ?? "—")
        let lapsBehind = (leader?.laps ?? 0) - (row.laps ?? 0)
        let gap = previous == nil ? "" : isRace && lapsBehind > 0
            ? "+\(lapsBehind) lap\(lapsBehind == 1 ? "" : "s")"
            : classified ? resultDelta(elapsed, from: isRace ? leader?.raceTime ?? leader?.time : leader?.bestLap ?? leader?.time, suffix: isRace ? "s" : "") : ""
        let interval = classified && previous != nil && row.laps == previous?.laps
            ? resultDelta(elapsed, from: previous?.raceTime ?? previous?.time ?? previous?.bestLap, suffix: "s") : ""
        return GridRow {
            Text(row.position.map(String.init) ?? "NC").modifier(ResultWebCell())
            Text(row.driverNumber ?? "—")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(DashboardArt.teamColor(row.constructorId))
                .modifier(ResultWebCell())
            Button { shownProfile = row.driverId } label: {
                Text(row.driverName.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? row.driverName)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.driverName)
            .popover(isPresented: Binding(
                get: { shownProfile == row.driverId },
                set: { if !$0 && shownProfile == row.driverId { shownProfile = nil } }
            )) {
                resultDriverProfile(row)
                    .presentationCompactAdaptation(.popover)
            }
            .modifier(ResultWebCell())
            HStack(spacing: 7) {
                AssetImage(name: MotorsportAssetName.name(kind: .teamLogo, id: row.constructorId, season: meeting.season))
                    .frame(width: 23, height: 20).accessibilityHidden(true)
                Text(row.team.replacingOccurrences(of: " F1 Team", with: ""))
            }
            .padding(.leading, 6)
            .background(alignment: .leading) {
                Rectangle().fill(DashboardArt.teamColor(row.constructorId)).frame(width: 5)
            }
            .modifier(ResultWebCell())
            if isQualifying {
                Text(row.q1 ?? "—").modifier(ResultWebCell())
                Text(row.q2 ?? "—").modifier(ResultWebCell())
                Text(row.q3 ?? "—").modifier(ResultWebCell())
            } else {
                Text(result).foregroundStyle(isRace && !classified ? PulseStyle.red : .primary).modifier(ResultWebCell())
                Text(gap).modifier(ResultWebCell())
                if isRace {
                    Text(interval).modifier(ResultWebCell())
                    Text((row.points ?? 0).formatted()).modifier(ResultWebCell())
                }
                Text(row.laps.map(String.init) ?? "—").modifier(ResultWebCell())
            }
        }
        .font(.system(size: 13).monospacedDigit())
    }

    private func resultDriverProfile(_ row: SessionResult) -> some View {
        let standing = model.driverRoster.first { $0.id == row.driverId && $0.season == meeting.season }
        let teammate = standing.flatMap { driver in
            model.driverRoster.first { $0.id != driver.id && $0.season == driver.season && $0.constructor == driver.constructor }
        }
        let names = row.driverName.split(whereSeparator: \.isWhitespace)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Text(standing?.driverNumber ?? row.driverNumber ?? "")
                        .font(.system(size: 34, weight: .heavy))
                    VStack(alignment: .leading, spacing: 5) {
                        (Text(names.dropLast().joined(separator: " ") + " ") + Text(names.last.map(String.init) ?? "").bold())
                            .font(.system(size: 18))
                        Text(row.team).font(.system(size: 13)).foregroundStyle(WebDashboardStyle.homeMuted)
                    }
                    .frame(maxWidth: 190, alignment: .leading)
                }
                HStack(spacing: 18) {
                    resultProfileMetric("RANK", value: standing.map { "P\($0.position)" } ?? "—")
                    Rectangle().fill(resultTableLine).frame(width: 1, height: 34)
                    resultProfileMetric("POINTS", value: standing?.points.formatted() ?? "—")
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
            .background(alignment: .bottomTrailing) {
                AssetImage(name: MotorsportAssetName.name(kind: .driverPhoto, id: row.driverId, season: meeting.season))
                    .frame(width: 145, height: 155).accessibilityHidden(true)
            }
            .background {
                LinearGradient(colors: [DashboardArt.teamColor(row.constructorId).opacity(0.22), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Rectangle().fill(resultTableLine).frame(height: 1)
            HStack(spacing: 8) {
                resultProfileAction("Stats", symbol: "chart.bar") {
                    guard let standing else { return }
                    shownProfile = nil
                    openResultProfile(.stats(StandingEntry(driver: standing)))
                }.disabled(standing == nil)
                resultProfileAction("Head-to-head", symbol: "arrow.left.arrow.right") {
                    shownProfile = nil
                    openResultProfile(.comparison(row.driverId, teammate?.id))
                }
            }.padding(9)
        }
        .frame(width: 360)
        .foregroundStyle(WebDashboardStyle.homeText)
        .presentationBackground(WebDashboardStyle.homePanel)
    }

    private func openResultProfile(_ target: DriverProfileDestination) {
        if let openDashboardDriverProfile {
            openDashboardDriverProfile(target)
        } else {
            profileDestination = target
        }
    }

    private func resultProfileMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(WebDashboardStyle.homeMuted)
            Text(value).font(.system(size: 23, weight: .bold)).monospacedDigit()
        }
    }

    private func resultProfileAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, minHeight: 34)
                .contentShape(.rect)
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(resultTableLine, lineWidth: 1) }
        }.buttonStyle(.plain)
    }

    private var resultTableLine: Color {
        WebDashboardStyle.adaptive(dark: 0x1b2230, light: 0xe7e7e9)
    }

    private struct ResultWebCell: ViewModifier {
        func body(content: Content) -> some View {
            content.fixedSize(horizontal: true, vertical: false).padding(.horizontal, 6).frame(minHeight: 36)
        }
    }

    private func resultDelta(_ value: String?, from reference: String?, suffix: String) -> String {
        guard let value, let reference,
              let current = resultTimeSeconds(value), let baseline = resultTimeSeconds(reference),
              current >= baseline else { return "" }
        return String(format: "+%.3f", current - baseline) + suffix
    }

    private var classification: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    classificationTitle
                    Spacer(minLength: 8)
                    analysisLink
                }
                VStack(alignment: .leading, spacing: 2) {
                    classificationTitle
                    analysisLink
                }
            }
            .padding(.bottom, 4)
            if sideBySide {
                denseResultColumns {
                    Text("POS")
                    Text("DRIVER")
                    if showsPhaseColumns {
                        let prefix = session.sessionType == .sprintQualifying ? "SQ" : "Q"
                        Text(prefix + "1")
                        Text(prefix + "2")
                        Text(prefix + "3")
                    } else {
                        Text(isRace ? "TIME / GAP" : isQualifying ? "BEST" : "TIME")
                        Text("LAPS")
                        if isRace { Text("PTS") }
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .accessibilityAddTraits(.isHeader)
            }
            ForEach(rows) { row in
                Divider()
                Group {
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Button {
                            selectedDriverID = row.driverId
                            showsCompactAnalysis = !sideBySide
                        } label: {
                            Group {
                                if sideBySide { denseResultRow(row) } else { resultRow(row) }
                            }
                                .background(sideBySide && selectedDriverID == row.driverId ? PulseStyle.red.opacity(0.10) : .clear)
                        }
                    } else {
                        NavigationLink {
                            driverAnalysis(row)
                        } label: {
                            resultRow(row)
                        }
                        .navigationLinkIndicatorVisibility(.hidden)
                    }
                }
                .buttonStyle(PulsePressStyle())
                .accessibilityAddTraits(sideBySide && selectedDriverID == row.driverId ? .isSelected : [])
                .accessibilityIdentifier("result.\(row.driverId)")
            }
        }
        .padding(14)
        .dashboardPanel(WebDashboardStyle.homePanel)
    }

    private var classificationTitle: some View {
        Text(isQualifying ? "Qualifying Results" : "Session Results")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var analysisLink: some View {
        if isRace {
            Button("Finishing Gaps", systemImage: "chart.bar.xaxis") {
                showFinishGaps = true
            }
            .labelStyle(.iconOnly)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PulseStyle.red)
            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            .contentShape(.rect)
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ScrollView {
                    SessionPaceChart(rows: rows, session: session, season: meeting.season)
                        .padding(16)
                }
                .background(WebDashboardStyle.homeBackground)
                .navigationTitle("Lap Time Comparison")
                .navigationBarTitleDisplayMode(.inline)
                .dashboardDetail()
            } label: {
                Label("Lap Time Comparison", systemImage: "chart.bar.xaxis")
                    .font(.subheadline)
                    .foregroundStyle(PulseStyle.red)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private func denseResultRow(_ row: SessionResult) -> some View {
        denseResultColumns {
            PulseNumber(row.position.map(String.init) ?? "—").bold()
            HStack(spacing: 6) {
                AssetImage(name: MotorsportAssetName.name(kind: .teamLogo, id: row.constructorId, season: meeting.season))
                    .frame(width: 18, height: 16)
                    .accessibilityHidden(true)
                Text(row.driverName).fontWeight(.semibold).lineLimit(1)
            }
            if showsPhaseColumns {
                PulseNumber(row.q1 ?? (row.classification.uppercased() == "CLASSIFIED" ? "—" : row.classification.uppercased()))
                PulseNumber(row.q2 ?? "—")
                PulseNumber(row.q3 ?? "—")
            } else {
                PulseNumber(mainValue(row))
                PulseNumber(row.laps.map(String.init) ?? "—")
                if isRace { PulseNumber(row.points?.formatted() ?? "—") }
            }
        }
        .font(.caption.monospacedDigit())
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func denseResultColumns(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 6) {
            Group(subviews: content()) { columns in
                columns[0].frame(width: 26, alignment: .leading)
                columns[1].frame(maxWidth: .infinity, alignment: .leading)
                ForEach(2..<columns.count, id: \.self) { index in
                    columns[index]
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(width: showsPhaseColumns ? 55 : index == 2 ? 81 : 34, alignment: .trailing)
                }
            }
        }
    }

    private func resultRow(_ row: SessionResult) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return VStack(alignment: .leading, spacing: 8) {
            layout {
                HStack(spacing: 8) {
                    PulseNumber(row.position.map(String.init) ?? "—")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 20, alignment: .leading)
                    helmet(row).frame(width: 30, height: 27)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if let number = row.resultNumber {
                                Text(number)
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .fixedSize()
                            }
                            Text(row.driverName).font(.subheadline.weight(.semibold))
                        }
                        HStack(spacing: 5) {
                            AssetImage(name: MotorsportAssetName.name(
                                kind: .teamLogo, id: row.constructorId, season: meeting.season
                            ))
                            .frame(width: 15, height: 12)
                            Text(row.team).font(.caption).foregroundStyle(WebDashboardStyle.homeMuted)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                    Text(mainValue(row))
                        .font(.subheadline.weight(.medium).monospacedDigit())
                    let detail = [row.laps.map { "\($0) laps" }, isRace ? row.points.map { "\($0.formatted()) pts" } : nil]
                        .compactMap { $0 }.joined(separator: " · ")
                    if !detail.isEmpty {
                        PulseNumber(detail).font(.caption.monospacedDigit())
                            .foregroundStyle(WebDashboardStyle.homeMuted)
                    }
                }
            }
            if isQualifying {
                let phases = [row.q1, row.q2, row.q3].enumerated().compactMap { index, value in
                    value.map { (index, $0) }
                }
                if !phases.isEmpty {
                    let phaseLayout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                    phaseLayout {
                        ForEach(phases, id: \.0) { index, time in
                            let prefix = session.sessionType == .sprintQualifying ? "SQ" : "Q"
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(prefix)\(index + 1)").foregroundStyle(WebDashboardStyle.homeMuted)
                                Text(time)
                            }
                            .font(.caption2.monospacedDigit())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                    .background(WebDashboardStyle.homeBackground, in: .rect(cornerRadius: 8))
                }
            }
        }
        .padding(.vertical, 9)
        .frame(minHeight: 48)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func helmet(_ row: SessionResult) -> some View {
        AssetImage(name: MotorsportAssetName.driverAvatarName(driverID: row.driverId, name: row.driverName, season: meeting.season))
    }

    private func mainValue(_ row: SessionResult) -> String {
        if row.classification.uppercased() != "CLASSIFIED" { return row.classification.uppercased() }
        if isRace {
            if row.position == 1 { return row.raceTime ?? row.time ?? "—" }
            if let gap = row.gap { return gap }
            if let leader = rows.first(where: { $0.position == 1 }), let leaderLaps = leader.laps, let laps = row.laps {
                if laps < leaderLaps { return "+\(leaderLaps - laps) laps" }
                if laps == leaderLaps,
                   let leadTime = AnalysisMath.elapsedSeconds(leader.raceTime ?? leader.time),
                   let finishTime = AnalysisMath.elapsedSeconds(row.raceTime ?? row.time), finishTime >= leadTime {
                    return "+\((finishTime - leadTime).formatted(.number.precision(.fractionLength(3)))) s"
                }
            }
            return row.raceTime ?? row.time ?? "—"
        }
        return row.bestLap ?? row.q3 ?? row.q2 ?? row.q1 ?? row.time ?? "—"
    }

    private func load() async {
        guard let url = model.serverURL else { error = "Check the server address"; return }
        let context = model.dataContext
        do {
            let result = try await APIClient(baseURL: url).sessionResults(sessionId: session.id, token: model.currentToken)
            guard context == model.dataContext, !Task.isCancelled else { return }
            response = result
            error = nil
        } catch {
            guard context == model.dataContext, !Task.isCancelled else { return }
            self.error = MobileModel.message(for: error).pulseEnglishError
        }
    }
}

extension ResultsScreen where WeekendTools == EmptyView {
    init(session: Session, meeting: Meeting) {
        self.init(session: session, meeting: meeting, weekendTools: { EmptyView() })
    }
}

extension SessionResult {
    var resultNumber: String? {
        guard let value = driverNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value.hasPrefix("#") ? value : "#" + value
    }
}

struct ResultDriverName: View {
    let name: String

    private var shortName: String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        guard let surname = parts.last else { return name }
        if let prefix = parts.dropLast().last, ["de", "van", "von", "da"].contains(prefix.lowercased()) {
            return "\(prefix) \(surname)"
        }
        return String(surname)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(name).fixedSize(horizontal: true, vertical: false)
            Text(shortName).lineLimit(1).minimumScaleFactor(0.65)
        }
        .font(.caption.weight(.semibold))
        .accessibilityLabel(name)
    }
}

struct ResultFittedSheet<Content: View>: View {
    let maximumHeight: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content()
                .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { contentHeight = $0 }
        }
        .foregroundStyle(WebDashboardStyle.homeText)
        .presentationDetents([contentHeight > 0 && maximumHeight > 0
                              ? .height(min(contentHeight, maximumHeight)) : .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(WebDashboardStyle.homeBackground)
    }
}

extension SessionType {
    var resultLabel: String {
        switch self {
        case .fp1, .fp2, .fp3: displayName
        default: webTitle
        }
    }
}

struct ResultSessionOptions: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(in: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(in: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(in width: CGFloat, subviews: Subviews) -> [CGRect] {
        var position = CGPoint.zero
        var rowHeight: CGFloat = 0
        return subviews.map { subview in
            let ideal = subview.sizeThatFits(.unspecified)
            let size = ideal.width > width
                ? subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
                : ideal
            if position.x > 0 && position.x + size.width > width {
                position.x = 0
                position.y += rowHeight
                rowHeight = 0
            }
            let frame = CGRect(origin: position, size: size)
            rowHeight = max(rowHeight, size.height)
            position.x += size.width + spacing
            return frame
        }
    }
}

private struct SessionChoiceRow: Layout {
    let spacing: CGFloat = 6

    private func widths(_ proposedWidth: CGFloat?, _ subviews: Subviews) -> [CGFloat] {
        let ideal = subviews.map { max(44, $0.sizeThatFits(.unspecified).width + 8) }
        let total = ideal.reduce(0, +)
        guard let proposedWidth, total > 0 else { return ideal }
        let available = max(0, proposedWidth - spacing * CGFloat(max(0, ideal.count - 1)))
        return ideal.map { available * $0 / total }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = widths(proposal.width, subviews)
        let height = zip(subviews, widths).map { view, width in
            view.sizeThatFits(.init(width: width, height: nil)).height
        }.max() ?? 0
        return CGSize(width: proposal.width ?? widths.reduce(0, +) + spacing * CGFloat(max(0, widths.count - 1)),
                      height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (view, width) in zip(subviews, widths(bounds.width, subviews)) {
            view.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                       proposal: .init(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

struct ResultSessionStyle: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(active ? PulseStyle.red : WebDashboardStyle.homeText)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(active ? PulseStyle.red.opacity(0.12) : WebDashboardStyle.homeLine,
                        in: .rect(cornerRadius: 9))
            .frame(minHeight: 44)
            .contentShape(.rect)
    }
}

struct ResultComparisonRow<Plot: View>: View {
    let asset: String
    let name: String
    let value: String
    var detail: String?
    var code: String?
    @ViewBuilder var plot: Plot
    @ScaledMetric(relativeTo: .caption) private var numberWidth = 72.0

    static var codeWidth: CGFloat { 30 }

    var body: some View {
        HStack(spacing: 8) {
            AssetImage(name: asset).frame(width: 32, height: 28)
            if let code {
                Text(code)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: Self.codeWidth, alignment: .leading)
            }
            plot.frame(maxWidth: .infinity)
                .pulseChart()
                .accessibilityHidden(true)
            VStack(alignment: .trailing, spacing: 2) {
                PulseNumber(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let detail {
                    PulseNumber(detail).font(.caption2)
                        .foregroundStyle(WebDashboardStyle.homeMuted)
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(width: min(numberWidth, 120), alignment: .trailing)
        }
        .frame(minHeight: 38)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\(name), \($0)" } ?? name)
        .accessibilityValue(value)
    }
}

struct ResultComparisonBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 5)
                .fill(color)
                .frame(width: max(2, geometry.size.width * min(1, max(0, fraction))))
        }
        .frame(height: height)
    }
}

private struct RaceFinishGaps: View {
    let rows: [SessionResult]
    let season: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var showsInterval = false
    @ScaledMetric(relativeTo: .caption) private var gapValueWidth: CGFloat = 75
    @ScaledMetric(relativeTo: .caption) private var numberWidth: CGFloat = 27
    @ScaledMetric(relativeTo: .callout) private var positionWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 39

    private struct Gap: Identifiable {
        let row: SessionResult
        let seconds: Double
        var id: String { row.id }
    }

    private var gaps: [Gap] {
        guard let leader = rows.first, leader.position == 1 else { return [] }
        return rows.enumerated().compactMap { index, row in
            let reference = showsInterval ? rows[max(0, index - 1)] : leader
            guard row.classification.uppercased() == "CLASSIFIED",
                  reference.classification.uppercased() == "CLASSIFIED",
                  let laps = row.laps, laps == reference.laps else { return nil }
            if index == 0 { return showsInterval ? nil : Gap(row: row, seconds: 0) }
            if let seconds = AnalysisMath.elapsedSeconds(row.raceTime ?? row.time),
               let prior = AnalysisMath.elapsedSeconds(reference.raceTime ?? reference.time),
               seconds >= prior {
                return Gap(row: row, seconds: seconds - prior)
            }
            if !showsInterval, let raw = row.gap {
                let elapsed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard elapsed.hasPrefix("+") else { return nil }
                let number = elapsed.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: " sS"))
                if let seconds = Double(number), seconds.isFinite, seconds >= 0 {
                    return Gap(row: row, seconds: seconds)
                }
            }
            return nil
        }
    }

    var body: some View {
        let gaps = gaps
        let scale = max(0.001, gaps.map(\.seconds).max() ?? 0)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                        showsInterval.toggle()
                    }
                } label: {
                    headerIcon("arrow.left.arrow.right", color: PulseStyle.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change gap reference")
                .accessibilityValue(showsInterval ? "To previous car" : "To leader")

                VStack(spacing: 3) {
                    Text("Finishing Gaps")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(showsInterval ? "To previous car" : "To leader")
                        .font(.caption)
                        .foregroundStyle(WebDashboardStyle.homeMuted)
                        .contentTransition(.opacity)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                Button {
                    dismiss()
                } label: {
                    headerIcon("xmark", color: WebDashboardStyle.homeText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 2)

            PulseCard {
                VStack(alignment: .leading, spacing: 8) {
                    if gaps.isEmpty {
                        ContentUnavailableView("No Comparable Gaps", systemImage: "timer")
                    } else {
                        VStack(spacing: 2) {
                            ForEach(gaps) { gap in
                                gapRow(gap, fraction: gap.seconds / scale)
                                    .transition(.opacity)
                            }
                        }
                        Text("Only drivers on the same lap with a verified time gap are shown.")
                            .font(.caption).foregroundStyle(WebDashboardStyle.homeMuted)
                    }
                }
            }
        }
        .padding(16)
    }

    private func headerIcon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
    }

    private func gapRow(_ gap: Gap, fraction: Double) -> some View {
        let row = gap.row
        let position = row.position.map { "P\($0)" } ?? "—"
        return HStack(spacing: 6) {
            Text(row.resultNumber ?? "")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(WebDashboardStyle.homeMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: min(numberWidth, 46), alignment: .leading)
            AssetImage(name: MotorsportAssetName.driverAvatarName(driverID: row.driverId, name: row.driverName, season: season))
                .frame(width: 31, height: 27)
            GeometryReader { geometry in
                let reserved = min(gapValueWidth, geometry.size.width * 0.55)
                let track = max(0, geometry.size.width - reserved - 6)
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(DashboardArt.teamColor(row.constructorId))
                        .frame(width: max(2, track * fraction), height: 18)
                    PulseNumber(format(gap.seconds))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .contentTransition(.numericText(value: gap.seconds))
                        .frame(width: reserved, alignment: .leading)
                }
                .frame(height: geometry.size.height, alignment: .leading)
            }
            Text(position)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(WebDashboardStyle.homeText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: min(positionWidth, 54), height: rowHeight, alignment: .trailing)
        }
        .frame(height: rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([row.resultNumber, row.driverName, position].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue(format(gap.seconds))
    }

    private func format(_ seconds: Double) -> String {
        let value = seconds.formatted(.number.precision(.fractionLength(3)))
        return seconds == 0 ? "\(value) s" : "+\(value) s"
    }
}

private struct SessionPaceChart: View {
    let rows: [SessionResult]
    let session: Session
    let season: Int
    @State private var selectedPhase: QualifyingPhase?

    private enum QualifyingPhase: Int, CaseIterable, Identifiable {
        case first = 1, second, third
        var id: Self { self }

        func seconds(in row: SessionResult) -> Double? {
            switch self {
            case .first: AnalysisMath.elapsedSeconds(row.q1)
            case .second: AnalysisMath.elapsedSeconds(row.q2)
            case .third: AnalysisMath.elapsedSeconds(row.q3)
            }
        }
    }

    private struct PacePoint: Identifiable {
        let row: SessionResult
        let gap: Double
        var id: String { row.driverId }
    }

    private var isQualifying: Bool { session.sessionType == .qualifying || session.sessionType == .sprintQualifying }

    private func points(phase: QualifyingPhase?) -> [PacePoint] {
        let timed = rows.compactMap { row -> (SessionResult, Double)? in
            let seconds: Double?
            if let phase {
                seconds = phase.seconds(in: row)
            } else {
                seconds = AnalysisMath.elapsedSeconds(row.bestLap) ?? AnalysisMath.elapsedSeconds(row.time)
            }
            guard let seconds else { return nil }
            return (row, seconds)
        }
        guard let fastest = timed.map(\.1).min() else { return [] }
        return timed
            .sorted { ($0.1, $0.0.driverId) < ($1.1, $1.0.driverId) }
            .map { row, seconds in
                PacePoint(row: row, gap: max(0, seconds - fastest))
            }
    }

    var body: some View {
        let phases = isQualifying ? QualifyingPhase.allCases.filter { phase in
            rows.contains { phase.seconds(in: $0) != nil }
        } : []
        let phase = selectedPhase.flatMap { phases.contains($0) ? $0 : nil } ?? phases.last
        let points = points(phase: phase)
        PulseCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label(isQualifying ? "Qualifying Pace" : "Fastest Practice Laps", systemImage: "speedometer")
                        .font(.headline)
                    Spacer()
                    Text("Gap to Fastest Lap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let phase {
                    let prefix = session.sessionType == .sprintQualifying ? "SQ" : "Q"
                    PulseSectionPicker(
                        sections: phases.map { ($0, "\(prefix)\($0.rawValue)") },
                        selection: Binding(get: { phase }, set: { selectedPhase = $0 })
                    )
                } else if isQualifying && !points.isEmpty {
                    Text("Using archived lap times. Sector timing is unavailable for this session.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if points.isEmpty {
                    ContentUnavailableView("No comparable lap times", systemImage: "speedometer")
                } else {
                    let scale = max(0.001, points.map(\.gap).max() ?? 0)
                    ForEach(points) { point in
                        ResultComparisonRow(
                            asset: MotorsportAssetName.driverAvatarName(
                                driverID: point.row.driverId, name: point.row.driverName, season: season
                            ),
                            name: point.row.driverName,
                            value: point.gap == 0 ? "Fastest" : "+\(point.gap.formatted(.number.precision(.fractionLength(3)))) s"
                        ) {
                            ResultComparisonBar(fraction: point.gap / scale, color: DashboardArt.teamColor(point.row.constructorId))
                        }
                    }
                }
            }
        }
    }
}
