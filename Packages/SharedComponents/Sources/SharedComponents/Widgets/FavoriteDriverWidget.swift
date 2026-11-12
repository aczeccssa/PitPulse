#if os(iOS) || os(macOS)
import SwiftUI
import Charts
import WidgetKit
import SharedData

struct FavoriteDriverWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: FavoriteDriverWidgetSnapshot?
}

struct FavoriteDriverWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FavoriteDriverWidgetEntry {
        FavoriteDriverWidgetEntry(date: .now, snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (FavoriteDriverWidgetEntry) -> Void) {
        completion(entry(at: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoriteDriverWidgetEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var dates = [now]
        if let saved = current.snapshot?.savedAt {
            let expiry = saved.addingTimeInterval(6 * 3600 + 1)
            if expiry > now { dates.append(expiry) }
        }
        let entries = dates.sorted().map { FavoriteDriverWidgetEntry(date: $0, snapshot: current.snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
    private func entry(at date: Date) -> FavoriteDriverWidgetEntry {
        FavoriteDriverWidgetEntry(date: date, snapshot: RaceWidgetCache.readFavoriteDriver())
    }
}

public struct FavoriteDriverWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.favoriteDriverKind, provider: FavoriteDriverWidgetProvider()) { entry in
            FavoriteDriverWidgetView(entry: entry).containerBackground(widgetBackground, for: .widget)
        }
        .configurationDisplayName("我的车手 · Formula 1")
        .description("小尺寸看排名与积分，中尺寸看近期比赛，大尺寸展开近三场与赛季数据。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct FavoriteDriverWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    let entry: FavoriteDriverWidgetEntry
    var previewFamily: WidgetFamily? = nil
    private var family: WidgetFamily { previewFamily ?? systemFamily }

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemSmall: small(snapshot)
            case .systemMedium: medium(snapshot)
            default: large(snapshot)
            }
        } else {
            WidgetEmpty(title: "我的车手", icon: "star.fill", message: "在 App 设置中选择喜欢车手")
        }
    }

    func small(_ snapshot: FavoriteDriverWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let driver = snapshot.driver
        return VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(label: "MY DRIVER",
                          trailing: stale ? "缓存过期" : "\(snapshot.season)",
                          warning: stale)
            HStack(spacing: 7) {
                helmet(driver, season: snapshot.season, size: CGSize(width: 42, height: 36))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(widgetDriverLabel(driver.name, number: driver.driverNumber))
                            .font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    HStack(spacing: 4) {
                        WidgetTeamLogo(constructorID: driver.constructorID, season: snapshot.season)
                            .frame(height: 10)
                        Text(driver.team)
                            .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                            .lineLimit(2).minimumScaleFactor(0.8)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(driver.points.rounded()))")
                    .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(widgetRed)
                Text("积分").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                Text(gapLabel(snapshot)).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(gapText(snapshot)).font(.system(size: 10, weight: .bold)).monospacedDigit()
            }
        }
    }

    func medium(_ snapshot: FavoriteDriverWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let driver = snapshot.driver
        let last = snapshot.recentRaces.first
        let form = Array(snapshot.recentRaces.prefix(3))
        return VStack(alignment: .leading, spacing: 4) {
            WidgetHeading(label: "MY DRIVER",
                          trailing: stale ? "缓存过期" : "F1 · \(snapshot.season)",
                          warning: stale)
            HStack(spacing: 7) {
                helmet(driver, season: snapshot.season, size: CGSize(width: 40, height: 32))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(widgetDriverLabel(driver.name, number: driver.driverNumber))
                            .font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    HStack(spacing: 4) {
                        WidgetTeamLogo(constructorID: driver.constructorID, season: snapshot.season)
                            .frame(height: 10)
                        Text(driver.team)
                            .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 2)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(driver.points.rounded()))")
                        .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(widgetRed)
                    Text("积分").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            Divider()
            if let last {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("上站 · \(last.meeting)")
                        .font(.system(size: 9, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(last.date, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    raceResultStat("名次", finishText(last), highlight: true)
                    Divider().frame(height: 20)
                    raceResultStat("积分", pointsText(last))
                    Divider().frame(height: 20)
                    raceResultStat("最快圈", last.fastestLap ?? "—")
                    Divider().frame(height: 20)
                    raceResultStat("时间", last.gap ?? "—")
                }
            } else {
                Text("近期比赛数据将在完赛后更新")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            if form.count > 1 {
                HStack(spacing: 4) {
                    Text("近\(form.count)场")
                        .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                    ForEach(form) { race in
                        Text(finishText(race))
                            .font(.system(size: 8, weight: .bold)).monospacedDigit()
                            .foregroundStyle(race.position == 1 ? widgetRed : .primary)
                            .padding(.horizontal, 4).padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    Spacer(minLength: 2)
                    Text("\(recentPoints(form)) 分")
                        .font(.system(size: 9, weight: .bold)).monospacedDigit().foregroundStyle(widgetRed)
                }
            }
            Spacer(minLength: 0)
        }
    }
    
    func large(_ snapshot: FavoriteDriverWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let driver = snapshot.driver
        let recent = Array(snapshot.recentRaces.prefix(3))
        return VStack(alignment: .leading, spacing: 8) {
            WidgetHeading(label: "MY DRIVER",
                          trailing: stale ? "缓存过期" : "F1 · \(snapshot.season)",
                          warning: stale)
            HStack(alignment: .center, spacing: 12) {
                helmet(driver, season: snapshot.season, size: CGSize(width: 80, height: 70))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(widgetDriverLabel(driver.name, number: driver.driverNumber))
                            .font(.system(size: 24, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Text(driver.name)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 4) {
                        WidgetTeamLogo(constructorID: driver.constructorID, season: snapshot.season)
                            .frame(height: 10)
                        Text(driver.team)
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(driver.points.rounded()))")
                        .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(widgetRed)
                    Text("积分").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 0) {
                stat("分站冠军", "\(snapshot.wins)")
                Divider().frame(height: 26)
                stat(recent.isEmpty ? "近期积分" : "近\(recent.count)场积分",
                     recent.isEmpty ? "—" : "\(recentPoints(recent))")
                Divider().frame(height: 26)
                stat(gapLabel(snapshot), gapText(snapshot), highlight: driver.position != 1)
            }
            seasonProgress(driver)
            Divider().foregroundStyle(.clear)
            HStack {
                Text("近期比赛").font(.system(size: 10, weight: .bold))
                Spacer()
                if !recent.isEmpty {
                    Text("最近 \(recent.count) 场").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            if recent.isEmpty {
                Text("打开 App 同步近期比赛数据")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { race in
                        recentRaceRow(race)
                        if race.id != recent.last?.id { Divider().padding(.leading, 34) }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text("近期比赛 · \(snapshot.driver.team)")
                Spacer()
                if stale {
                    Text("缓存数据")
                } else {
                    Text("更新 ")
                    Text(snapshot.savedAt, style: .time)
                }
            }.font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }

    func seasonProgress(_ driver: WidgetStandingDriver) -> some View {
        let leaderPoints = driver.points + driver.gapToLeader
        let share = leaderPoints > 0 ? min(1, max(0, driver.points / leaderPoints)) : 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("赛季积分")
                Spacer()
                Text("\(Int(driver.points.rounded())) / \(Int(leaderPoints.rounded()))")
            }.font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(widgetRed).frame(width: geometry.size.width * share)
                }
            }.frame(height: 5)
        }
    }

    func recentRaceRow(_ race: FavoriteRaceEntry) -> some View {
        HStack(spacing: 8) {
            Text(race.round.map { "R\($0)" } ?? "—")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .frame(width: 28, alignment: .leading).lineLimit(1)
            VStack(alignment: .leading, spacing: 1) {
                Text(shortMeeting(race.meeting))
                    .font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(race.date, format: .dateTime.month(.abbreviated).day())
                    if let lap = race.fastestLap { Text("· 最快圈 \(lap)") }
                }.font(.system(size: 7.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(race.gap ?? "—")
                .font(.system(size: 9, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.7)
            Text(finishText(race))
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(race.position == 1 ? widgetRed : .primary)
                .frame(width: 32, alignment: .trailing)
            Text(pointsText(race))
                .font(.system(size: 10, weight: .bold)).monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.vertical, 5).padding(.horizontal, 4)
    }

    func stat(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            Text(value)
                .font(.system(size: 14, weight: .bold)).monospacedDigit()
                .foregroundStyle(highlight ? widgetRed : .primary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity)
    }

    func helmet(_ driver: WidgetStandingDriver, season: Int, size: CGSize) -> some View {
        MotorsportImages.image(named: MotorsportAssetName.helmetName(driverID: driver.driverID, name: driver.name, season: season))
            .resizable().scaledToFit().frame(width: size.width, height: size.height).accessibilityHidden(true)
    }

    func raceResultStat(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 7.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                .foregroundStyle(highlight ? widgetRed : .primary)
                .lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity)
    }

    func shortMeeting(_ name: String) -> String {
        name.replacingOccurrences(of: " Grand Prix", with: "")
            .replacingOccurrences(of: " GP", with: "")
    }

    func finishText(_ race: FavoriteRaceEntry) -> String {
        race.position.map { "P\($0)" } ?? race.classification ?? "—"
    }

    func pointsText(_ race: FavoriteRaceEntry) -> String {
        race.points.map { "\(Int($0.rounded()))" } ?? "—"
    }

    func recentPoints(_ races: [FavoriteRaceEntry]) -> Int {
        Int(races.compactMap(\.points).reduce(0, +).rounded())
    }

    func gapLabel(_ snapshot: FavoriteDriverWidgetSnapshot) -> String {
        snapshot.driver.position == 1 ? "领先 P2" : "落后榜首"
    }

    func gapText(_ snapshot: FavoriteDriverWidgetSnapshot) -> String {
        if snapshot.driver.position == 1 {
            return snapshot.gapToBehind.map { "+\(Int($0.rounded()))" } ?? "—"
        }
        let value = Int(snapshot.driver.gapToLeader.rounded())
        return value <= 0 ? "—" : "−\(value)"
    }
}

#if DEBUG
#Preview("Widget Preview · Favorit Driver") {
    WidgetSizePreview(families: [.systemSmall, .systemMedium, .systemLarge]) { family in
        FavoriteDriverWidgetView(entry: FavoriteDriverWidgetEntry(date: WidgetPreviewData.now, snapshot: WidgetPreviewData.favorite), previewFamily: family)
    }
}
#endif
#endif
