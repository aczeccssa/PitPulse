#if os(iOS) || os(macOS)
import SwiftUI
import Charts
import WidgetKit
import SharedData

struct LastRaceWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: LastRaceWidgetSnapshot?
}

struct LastRaceWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LastRaceWidgetEntry {
        LastRaceWidgetEntry(date: .now, snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (LastRaceWidgetEntry) -> Void) {
        completion(entry(at: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LastRaceWidgetEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var dates = [now]
        if let saved = current.snapshot?.savedAt {
            let expiry = saved.addingTimeInterval(6 * 3600 + 1)
            if expiry > now { dates.append(expiry) }
        }
        let entries = dates.sorted().map { LastRaceWidgetEntry(date: $0, snapshot: current.snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
    private func entry(at date: Date) -> LastRaceWidgetEntry {
        LastRaceWidgetEntry(date: date, snapshot: RaceWidgetCache.readLastRace())
    }
}

public struct LastRaceWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.lastRaceKind, provider: LastRaceWidgetProvider()) { entry in
            LastRaceWidgetView(entry: entry).containerBackground(widgetBackground, for: .widget)
        }
        .configurationDisplayName("上站结果 · Formula 1")
        .description("中尺寸看领奖台与比赛数字，大尺寸展开完整结果。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct LastRaceWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    let entry: LastRaceWidgetEntry
    var previewFamily: WidgetFamily? = nil
    private var family: WidgetFamily { previewFamily ?? systemFamily }

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.podium.isEmpty {
            switch family {
            case .systemMedium: medium(snapshot)
            default: content(snapshot)
            }
        } else {
            WidgetEmpty(title: "上站结果", icon: "flag.checkered")
        }
    }

    private func medium(_ snapshot: LastRaceWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let season = snapshot.season ?? Calendar.current.component(.year, from: snapshot.raceDate ?? entry.date)
        let podium = Array(snapshot.podium.prefix(3))
        return VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(label: "LAST RACE",
                          trailing: stale ? "缓存过期" : snapshot.round.map { "F1 · R\($0)" },
                          warning: stale)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(snapshot.meeting)
                    .font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text(raceMeta(snapshot))
                    .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 0) {
                ForEach(Array(podium.enumerated()), id: \.element.id) { index, row in
                    podiumCompact(row, season: season)
                    if index < podium.count - 1 { Divider().frame(height: 38) }
                }
            }
            Divider()
            HStack(spacing: 0) {
                stat("最快圈", snapshot.fastestLap ?? "—", highlight: true)
                Divider().frame(height: 22)
                stat("圈数", snapshot.laps.map(String.init) ?? "—")
                Divider().frame(height: 22)
                if let safetyCars = snapshot.safetyCars {
                    stat("安全车", "\(safetyCars)")
                } else {
                    stat("冠军积分", podium.first?.points.map { "\(Int($0.rounded()))" } ?? "—")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func raceMeta(_ snapshot: LastRaceWidgetSnapshot) -> String {
        var parts: [String] = []
        if let date = snapshot.raceDate {
            parts.append(date.formatted(.dateTime.month(.abbreviated).day()))
        }
        parts.append(snapshot.session)
        return parts.joined(separator: " · ")
    }

    private func podiumCompact(_ row: LastRacePodiumEntry, season: Int) -> some View {
        let isWinner = row.position == 1
        return VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text("P\(row.position)")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(isWinner ? widgetRed : .secondary)
                MotorsportImages.image(named: MotorsportAssetName.helmetName(driverID: row.driverID, name: row.name, season: season))
                    .resizable().scaledToFit().frame(width: 26, height: 22).accessibilityHidden(true)
                Text(widgetDriverLabel(row.name, number: row.driverNumber))
                    .font(.system(size: 10, weight: .bold)).lineLimit(1)
            }
            Text(row.time)
                .font(.system(size: 9, weight: .semibold)).monospacedDigit()
                .foregroundStyle(isWinner ? widgetRed : .primary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity)
    }

    private func content(_ snapshot: LastRaceWidgetSnapshot) -> some View {
        let stale = snapshot.isStale(at: entry.date)
        let season = snapshot.season ?? Calendar.current.component(.year, from: snapshot.raceDate ?? entry.date)
        let podium = Array(snapshot.podium.prefix(3))
        return VStack(alignment: .leading, spacing: 9) {
            WidgetHeading(label: "LAST RACE",
                          trailing: stale ? "缓存过期" : snapshot.round.map { "F1 · R\($0)" },
                          warning: stale)
            Text(snapshot.meeting)
                .font(.system(size: 22, weight: .bold)).lineLimit(2).minimumScaleFactor(0.85)
            HStack(spacing: 6) {
                if let date = snapshot.raceDate {
                    Text(date, format: .dateTime.month(.abbreviated).day())
                }
                Text("·")
                Text(snapshot.session)
                Spacer(minLength: 4)
                Text("已结束")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(widgetRed)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(widgetRed.opacity(0.12), in: Capsule())
            }.font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ForEach(Array(podium.enumerated()), id: \.element.id) { index, row in
                    podiumColumn(row, season: season)
                    if index < podium.count - 1 { Divider().frame(height: 84) }
                }
            }

            Divider()
            HStack(spacing: 0) {
                stat("最快圈", snapshot.fastestLap ?? "—", highlight: true)
                Divider().frame(height: 28)
                stat("圈数", snapshot.laps.map(String.init) ?? "—")
                Divider().frame(height: 28)
                if let safetyCars = snapshot.safetyCars {
                    stat("安全车", "\(safetyCars)")
                } else {
                    stat("冠军积分", podium.first?.points.map { "\(Int($0.rounded()))" } ?? "—")
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text("比赛结果")
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

    private func podiumColumn(_ row: LastRacePodiumEntry, season: Int) -> some View {
        let isWinner = row.position == 1
        return VStack(spacing: 3) {
            Text("P\(row.position)")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(isWinner ? widgetRed : .secondary)
            MotorsportImages.image(named: MotorsportAssetName.helmetName(driverID: row.driverID, name: row.name, season: season))
                .resizable().scaledToFit().frame(width: 52, height: 46).accessibilityHidden(true)
            Text(widgetDriverLabel(row.name, number: row.driverNumber))
                .font(.system(size: 11, weight: .bold)).lineLimit(1)
            Text(row.time)
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(isWinner ? widgetRed : .primary)
                .lineLimit(1).minimumScaleFactor(0.62)
            Text(row.team)
                .font(.system(size: 7.5)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }

    private func stat(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold)).monospacedDigit()
                .foregroundStyle(highlight ? widgetRed : .primary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Widget Preview · Last Race") {
    WidgetSizePreview(families: [.systemMedium, .systemLarge]) { family in
        LastRaceWidgetView(entry: LastRaceWidgetEntry(date: WidgetPreviewData.now, snapshot: WidgetPreviewData.lastRace), previewFamily: family)
    }
}
#endif
#endif
