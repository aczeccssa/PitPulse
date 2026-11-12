import AppKit
import Charts
import SwiftUI
import PitPulseData

struct StandingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedID: String?
    @State private var detail: StandingDetailTarget?

    private var isConstructor: Bool { model.showingConstructorStandings }

    private var sortedDrivers: [DriverStanding] {
        model.driverStandings.sorted { $0.position < $1.position }
    }

    private var sortedConstructors: [ConstructorStanding] {
        model.constructorStandings.sorted { $0.position < $1.position }
    }

    private var effectiveSelection: String? {
        if let selectedID,
           (isConstructor ? sortedConstructors.contains { $0.constructorId == selectedID }
                          : sortedDrivers.contains { $0.driverId == selectedID }) {
            return selectedID
        }
        if !isConstructor, let favorite = model.favoriteDriverId(for: .f1),
           sortedDrivers.contains(where: { $0.driverId == favorite }) {
            return favorite
        }
        return isConstructor ? sortedConstructors.first?.constructorId : sortedDrivers.first?.driverId
    }

    var body: some View {
        Group {
            if let detail {
                StandingDetailView(model: model, target: detail) { self.detail = nil }
            } else {
                standingsPage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.selectedSeason) { _, _ in
            selectedID = nil
            detail = nil
        }
        .onChange(of: model.serverAddress) { _, _ in
            selectedID = nil
            detail = nil
        }
        .onChange(of: model.showingConstructorStandings) { _, _ in
            selectedID = nil
            detail = nil
        }
        .task(id: "\(model.selectedSeason)-\(model.showingConstructorStandings)") { await model.refreshStandings() }
    }

    private var standingsPage: some View {
        VStack(spacing: 0) {
            toolbar
            ScrollView {
                VStack(alignment: .leading, spacing: PitPulseTheme.cardSpacing) {
                    if let error = model.standingsError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 2)
                    }

                    if isConstructor ? sortedConstructors.isEmpty : sortedDrivers.isEmpty {
                        emptyStandings
                    } else {
                        hero
                        table
                        if let selection = effectiveSelection {
                            StandingTrendCard(
                                model: model,
                                kind: isConstructor ? "constructors" : "drivers",
                                id: selection,
                                season: model.selectedSeason,
                                officialPoints: selectedPoints(selection),
                                title: selectedTitle(selection),
                                openDetail: { openDetail(selection) }
                            )
                        }
                    }
                }
                .padding(.horizontal, PitPulseTheme.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .background(CalendarScrollAppearance())
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Button { model.selectSeason(model.selectedSeason - 1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11.5, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上一年")
                Text(String(model.selectedSeason))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 34)
                Button { model.selectSeason(model.selectedSeason + 1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11.5, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下一年")
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: Capsule())

            Spacer(minLength: 6)

            if model.isRefreshing { ProgressView().controlSize(.mini) }

            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 4) {
                    modeButton("车手", active: !isConstructor) { model.selectStandings(isConstructor: false) }
                    modeButton("车队", active: isConstructor) { model.selectStandings(isConstructor: true) }
                }
            }
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func modeButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(active ? PitPulseTheme.accent : Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            active
                ? .regular.tint(PitPulseTheme.accent.opacity(0.18)).interactive()
                : .regular.interactive(),
            in: Capsule()
        )
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var emptyStandings: some View {
        EmptyStateCard(
            symbol: "trophy",
            title: model.standingsError == nil ? "暂无积分" : "无法读取积分榜",
            message: model.standingsError == nil ? "该赛季还没有可用的积分数据。" : "稍后重试，或检查服务器连接。"
        )
    }

    // MARK: Hero — top three entries

    private struct HeroEntry: Identifiable {
        let id: String
        let rank: Int
        let name: String
        let detail: String
        let points: Double
        let image: NSImage?
    }

    private var heroEntries: [HeroEntry] {
        if isConstructor {
            return sortedConstructors.prefix(3).map { row in
                HeroEntry(
                    id: row.constructorId,
                    rank: row.position,
                    name: row.constructorName,
                    detail: "\(row.wins) 胜",
                    points: row.points,
                    image: MotorsportAsset.image(kind: .teamLogo, id: row.constructorId, season: model.selectedSeason)
                )
            }
        }
        return sortedDrivers.prefix(3).map { row in
            HeroEntry(
                id: row.driverId,
                rank: row.position,
                name: row.driverName,
                detail: "\(row.wins) 胜",
                points: row.points,
                image: MotorsportAsset.f1HelmetImage(id: row.driverId, season: model.selectedSeason)
            )
        }
    }

    // MARK: Hero — the top three in plain 1 · 2 · 3 order

    private var hero: some View {
        GlassCard(padding: 12) {
            VStack(spacing: 8) {
                CardHeader(title: "前三名")
                HStack(spacing: 6) {
                    ForEach(heroEntries) { entry in
                        heroCard(entry)
                    }
                }
            }
        }
    }

    private func heroCard(_ entry: HeroEntry) -> some View {
        Button { selectedID = entry.id } label: {
            VStack(spacing: 4) {
                heroImage(entry, size: 46)

                Text(entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 4) {
                    Text("\(entry.points.formatted()) 分")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("·")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("P\(entry.rank)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PitPulseTheme.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(entry.rank) 名 \(entry.name)，\(entry.points.formatted()) 分，\(entry.detail)")
    }

    @ViewBuilder
    private func heroImage(_ entry: HeroEntry, size: CGFloat) -> some View {
        if isConstructor {
            Group {
                if let image = entry.image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Circle().fill(.primary.opacity(0.07))
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else {
            DriverHelmetAvatar(
                driverID: entry.id,
                name: entry.name,
                season: model.selectedSeason,
                size: size
            )
        }
    }

    // MARK: Table

    private var table: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("POS").frame(width: 26, alignment: .leading)
                    Text(isConstructor ? "车队" : "车手")
                    Spacer()
                    Text("胜").frame(width: 22, alignment: .trailing)
                    Text("积分").frame(width: 44, alignment: .trailing)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

                if isConstructor {
                    ForEach(Array(sortedConstructors.enumerated()), id: \.element.id) { index, row in
                        tableRow(
                            rank: row.position,
                            title: row.constructorName,
                            subtitle: "\(row.wins) 场胜利",
                            wins: row.wins,
                            points: row.points,
                            selected: effectiveSelection == row.constructorId,
                            image: MotorsportAsset.image(kind: .teamLogo, id: row.constructorId, season: model.selectedSeason),
                            isLast: index == sortedConstructors.count - 1
                        ) {
                            selectedID = row.constructorId
                            openDetail(row.constructorId)
                        }
                    }
                } else {
                    ForEach(Array(sortedDrivers.enumerated()), id: \.element.id) { index, row in
                        tableRow(
                            rank: row.position,
                            title: row.driverName,
                            subtitle: row.constructor,
                            wins: row.wins,
                            points: row.points,
                            selected: effectiveSelection == row.driverId,
                            image: MotorsportAsset.f1HelmetImage(id: row.driverId, season: model.selectedSeason),
                            isLast: index == sortedDrivers.count - 1
                        ) {
                            selectedID = row.driverId
                            openDetail(row.driverId)
                        }
                    }
                }
            }
        }
    }

    private func tableRow(
        rank: Int,
        title: String,
        subtitle: String,
        wins: Int,
        points: Double,
        selected: Bool,
        image: NSImage?,
        isLast: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Text(String(rank))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(rank == 1 ? PitPulseTheme.accent : .secondary)
                        .frame(width: 26, alignment: .leading)

                    if let image {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                    } else if isConstructor {
                        Text(MotorsportAsset.abbreviation(title))
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 24, height: 24)
                            .background(.primary.opacity(0.06), in: Circle())
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "helmet.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(.primary.opacity(0.06), in: Circle())
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Text(String(wins))
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)

                    Text(points.formatted())
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(PitPulseTheme.accentSoft)
                            .padding(.horizontal, 6)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("第 \(rank) 名 \(title)，\(points.formatted()) 分，\(wins) 胜")
            .accessibilityHint("查看赛季分析")
            .accessibilityIdentifier("standings.row.\(rank)")

            if !isLast {
                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 1)
                    .padding(.leading, 52)
            }
        }
    }

    private func openDetail(_ id: String) {
        if isConstructor, let row = sortedConstructors.first(where: { $0.constructorId == id }) {
            detail = StandingDetailTarget(
                kind: "constructors",
                id: row.constructorId,
                title: row.constructorName,
                season: row.season,
                position: row.position,
                points: row.points,
                wins: row.wins,
                team: nil
            )
        } else if let row = sortedDrivers.first(where: { $0.driverId == id }) {
            detail = StandingDetailTarget(
                kind: "drivers",
                id: row.driverId,
                title: row.driverName,
                season: row.season,
                position: row.position,
                points: row.points,
                wins: row.wins,
                team: row.constructor
            )
        }
    }

    private func selectedTitle(_ id: String) -> String {
        isConstructor
            ? sortedConstructors.first { $0.constructorId == id }?.constructorName ?? id
            : sortedDrivers.first { $0.driverId == id }?.driverName ?? id
    }

    private func selectedPoints(_ id: String) -> Double {
        isConstructor
            ? sortedConstructors.first { $0.constructorId == id }?.points ?? 0
            : sortedDrivers.first { $0.driverId == id }?.points ?? 0
    }
}

// MARK: - Trend card

private struct StandingTrendCard: View {
    @ObservedObject var model: AppModel
    let kind: String
    let id: String
    let season: Int
    let officialPoints: Double
    let title: String
    let openDetail: () -> Void

    @State private var response: APIEnvelope<SeasonAnalysis>?
    @State private var loading = true
    @State private var error: String?

    private var rounds: [AnalysisRound] { response?.data.rounds ?? [] }

    private var cumulative: [(index: Int, points: Double)] {
        var sum = 0.0
        return rounds.enumerated().compactMap { index, round in
            guard let points = round.points else { return nil }
            sum += points
            return (index, sum)
        }
    }

    private var recent: [AnalysisRound] { Array(rounds.suffix(5)) }

    var body: some View {
        GlassCard(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                CardHeader(title: "\(title) · 赛季走势", actionTitle: "完整分析", actionSymbol: "arrow.up.right", action: openDetail)

                if loading, response == nil {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text("读取赛季明细…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else if let error, cumulative.isEmpty {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if cumulative.isEmpty {
                    Text("逐站积分明细未提供。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(cumulative.last?.points.formatted() ?? "—")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("明细累计")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("积分榜 \(officialPoints.formatted())")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Chart(cumulative, id: \.index) { row in
                        AreaMark(
                            x: .value("场次", row.index + 1),
                            y: .value("累计积分", row.points)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [PitPulseTheme.accent.opacity(0.28), PitPulseTheme.accent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("场次", row.index + 1),
                            y: .value("累计积分", row.points)
                        )
                        .foregroundStyle(PitPulseTheme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                            AxisValueLabel().font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(height: 104)
                    .accessibilityLabel("\(title) 赛季累计积分折线，\(cumulative.count) 场")

                    if !recent.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(Array(recent.enumerated()), id: \.offset) { _, round in
                                VStack(spacing: 2) {
                                    Text("R\(round.round.map(String.init) ?? "—")")
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                    Text(round.points.map { String(format: "%g", $0) } ?? "—")
                                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }

                    Text("Sprint 与正赛分别统计；累计仅包含后端已提供的场次，可能低于积分榜总分。")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: "\(kind)-\(id)-\(season)") {
            loading = true
            error = nil
            do {
                let value = try await model.seasonAnalysis(kind: kind, id: id, season: season)
                try Task.checkCancellation()
                response = value
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

// MARK: - Detail

struct StandingDetailTarget: Identifiable {
    let kind: String
    let id: String
    let title: String
    let season: Int
    let position: Int
    let points: Double
    let wins: Int
    let team: String?

    var identity: String { "\(kind)-\(id)" }
}

private struct StandingDetailView: View {
    @ObservedObject var model: AppModel
    let target: StandingDetailTarget
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    SeasonAnalysisView(
                        model: model,
                        kind: target.kind,
                        id: target.id,
                        season: target.season,
                        officialPoints: target.points
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PitPulseTheme.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(CalendarScrollAppearance())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12.5, weight: .bold))
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("返回积分榜")
            .accessibilityLabel("返回积分榜")
            .accessibilityIdentifier("standings.back")
            .keyboardShortcut(.cancelAction)

            if target.kind == "constructors" {
                if let image = MotorsportAsset.image(kind: .teamLogo, id: target.id, season: target.season) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 34, height: 34)
                        .accessibilityHidden(true)
                }
            } else {
                DriverHelmetAvatar(
                    driverID: target.id,
                    name: target.title,
                    season: target.season,
                    size: 34
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(target.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text("\(String(target.season)) 赛季 · \(target.team ?? (target.kind == "constructors" ? "车队" : "车手"))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text("P\(target.position)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("\(target.points.formatted()) 分")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, PitPulseTheme.pagePadding)
        .padding(.vertical, 8)
    }

    private var summary: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 8) {
                summaryMetric("排名", "第 \(target.position) 名", tint: PitPulseTheme.accent)
                summaryMetric("积分", target.points.formatted())
                summaryMetric("胜场", "\(target.wins)")
                summaryMetric("赛季", String(target.season))
            }
        }
    }

    private func summaryMetric(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
