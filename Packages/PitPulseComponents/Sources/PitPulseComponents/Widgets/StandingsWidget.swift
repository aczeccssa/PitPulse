#if os(iOS) || os(macOS)
import SwiftUI
import Charts
import WidgetKit
import PitPulseShared

struct StandingsWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: StandingsWidgetSnapshot?
}

struct StandingsWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> StandingsWidgetEntry {
        StandingsWidgetEntry(date: .now, snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (StandingsWidgetEntry) -> Void) {
        completion(entry(at: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StandingsWidgetEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var dates = [now]
        if let saved = current.snapshot?.savedAt {
            let expiry = saved.addingTimeInterval(6 * 3600 + 1)
            if expiry > now { dates.append(expiry) }
        }
        let entries = dates.sorted().map { StandingsWidgetEntry(date: $0, snapshot: current.snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
    private func entry(at date: Date) -> StandingsWidgetEntry {
        StandingsWidgetEntry(date: date, snapshot: RaceWidgetCache.readStandings())
    }
}

public struct StandingsWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.standingsKind, provider: StandingsWidgetProvider()) { entry in
            StandingsWidgetView(entry: entry).containerBackground(widgetBackground, for: .widget)
        }
        .configurationDisplayName("车手积分 · Formula 1")
        .description("小尺寸看榜首，中尺寸查看前五名与和榜首的差距。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StandingsWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    let entry: StandingsWidgetEntry
    var previewFamily: WidgetFamily? = nil
    private var family: WidgetFamily { previewFamily ?? systemFamily }

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.drivers.isEmpty {
            switch family {
            case .systemSmall: small(snapshot)
            default: content(snapshot)
            }
        } else {
            WidgetEmpty(title: "车手积分", icon: "trophy.fill")
        }
    }

    private func small(_ snapshot: StandingsWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let leader = snapshot.drivers[0]
        let runnerUp = snapshot.drivers.count > 1 ? snapshot.drivers[1] : nil
        return VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(label: "STANDINGS",
                          trailing: stale ? "缓存过期" : "\(snapshot.season)",
                          warning: stale)
            HStack(spacing: 7) {
                MotorsportImages.image(named: MotorsportAssetName.helmetName(driverID: leader.driverID, name: leader.name, season: snapshot.season))
                    .resizable().scaledToFit().frame(width: 42, height: 36).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(widgetDriverLabel(leader.name, number: leader.driverNumber))
                        .font(.system(size: 16, weight: .bold)).lineLimit(1)
                    // Text(leader.team)
                    WidgetTeamLogo(constructorID: leader.constructorID, season: snapshot.season)
                        .frame(width: 34, height: 14)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(leader.points.rounded()))")
                    .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(widgetRed)
                Text("积分").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                Text("领先 P2").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(runnerUp.map { "+\(Int($0.gapToLeader.rounded()))" } ?? "—")
                    .font(.system(size: 10, weight: .bold)).monospacedDigit()
            }
        }
    }

    private func content(_ snapshot: StandingsWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let season = snapshot.season
        return VStack(alignment: .leading, spacing: 8) {
            WidgetHeading(label: "STANDINGS",
                          trailing: stale ? "缓存过期" : "\(season)",
                          warning: stale)
//            HStack(spacing: 4) {
//                Text("车手").font(.system(size: 11, weight: .bold))
//                Spacer(minLength: 4)
//                Text("积分").font(.system(size: 8, weight: .medium))
//                    .foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
//                Text("与榜首").font(.system(size: 8, weight: .medium))
//                    .foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
//            }
            ForEach(Array(snapshot.drivers.prefix(4))) { driver in
                row(driver, season: season)
            }
//            Spacer(minLength: 0)
        }
    }

    private func row(_ driver: WidgetStandingDriver, season: Int) -> some View {
        let isLeader = driver.position == 1
        return HStack(spacing: 5) {
            Text("\(driver.position)")
                .font(.system(size: 9, weight: .bold)).monospacedDigit()
                .foregroundStyle(isLeader ? widgetRed : .secondary)
                .frame(width: 12, alignment: .leading)
            MotorsportImages.image(named: MotorsportAssetName.helmetName(driverID: driver.driverID, name: driver.name, season: season))
                .resizable().scaledToFit().frame(width: 20, height: 16).accessibilityHidden(true)
            Text(widgetDriverLabel(driver.name, number: driver.driverNumber))
                .font(.system(size: 10, weight: .bold)).lineLimit(1)
                .frame(minWidth: 58, alignment: .leading)
            // Text(driver.team)
            WidgetTeamLogo(constructorID: driver.constructorID, season: season)
                .frame(width: 24, height: 12)
            Spacer(minLength: 2)
            Text("\(Int(driver.points.rounded()))")
                .font(.system(size: 10, weight: .bold)).monospacedDigit()
                .frame(width: 30, alignment: .trailing)
            Text(gapText(driver.gapToLeader))
                .font(.system(size: 8, weight: .medium)).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, 1.5).padding(.horizontal, 4)
        .background(isLeader ? widgetRed.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .leading) {
            if isLeader {
                RoundedRectangle(cornerRadius: 1.5).fill(widgetRed)
                    .frame(width: 2.5, height: 14).padding(.leading, -1)
            }
        }
    }

    private func gapText(_ gap: Double) -> String {
        let value = Int(gap.rounded())
        return value <= 0 ? "—" : "−\(value)"
    }
}

#if DEBUG
#Preview("Widget Preview · Standing") {
    WidgetSizePreview(families: [.systemSmall, .systemMedium]) { family in
        StandingsWidgetView(entry: StandingsWidgetEntry(date: WidgetPreviewData.now, snapshot: WidgetPreviewData.standings), previewFamily: family)
    }
}
#endif
#endif
