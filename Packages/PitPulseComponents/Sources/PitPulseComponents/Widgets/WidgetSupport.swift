#if os(iOS) || os(macOS)
import SwiftUI
import Charts
import WidgetKit
import PitPulseShared

var widgetBackground: Color {
    #if os(macOS)
    Color(nsColor: .windowBackgroundColor)
    #else
    Color(uiColor: .systemBackground)
    #endif
}

/// Mirrors PulseStyle.red so widgets match the app in both appearances.
var widgetRed: Color {
    #if os(macOS)
    Color(red: 0.86, green: 0.13, blue: 0.11)
    #else
    Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.98, green: 0.25, blue: 0.23, alpha: 1)
            : UIColor(red: 0.78, green: 0.08, blue: 0.07, alpha: 1)
    })
    #endif
}

var raceWidgetFamilies: [WidgetFamily] {
    #if os(iOS)
    [.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular]
    #else
    [.systemSmall, .systemMedium, .systemLarge]
    #endif
}

var scheduleWidgetFamilies: [WidgetFamily] {
    #if os(iOS)
    [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular]
    #else
    [.systemSmall, .systemMedium, .systemLarge]
    #endif
}

struct RaceWeekendEntry: TimelineEntry {
    let date: Date
    let snapshot: RaceWidgetSnapshot?
    let timing: RaceTimingSnapshot?
}

struct RaceWeekendProvider: TimelineProvider {
    func placeholder(in context: Context) -> RaceWeekendEntry { RaceWeekendEntry(date: .now, snapshot: nil, timing: nil) }
    func getSnapshot(in context: Context, completion: @escaping (RaceWeekendEntry) -> Void) {
        completion(entry(at: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RaceWeekendEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var dates = [now]
        let calendar = RaceWidgetCache.readUpcoming()
        let legacy = RaceWidgetCache.read()
        let boundaries = (calendar?.races.flatMap { $0.sessions?.map(\.start) ?? [] } ?? [])
            + (legacy?.sessions?.map(\.start) ?? []) + [legacy?.start].compactMap { $0 }
        dates += boundaries.map { $0.addingTimeInterval(1) }.filter { $0 > now }.sorted().prefix(12)
        if let saved = current.snapshot?.savedAt {
            let expiry = saved.addingTimeInterval(6 * 3600 + 1)
            if expiry > now { dates.append(expiry) }
        }
        if let saved = current.timing?.updatedAt {
            let expiry = saved.addingTimeInterval(91)
            if expiry > now { dates.append(expiry) }
        }
        let entries = Set(dates).sorted().map { date in
            RaceWeekendEntry(date: date,
                snapshot: calendar?.nextSession(at: date) ?? legacy?.advancing(to: date), timing: current.timing)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
    private func entry(at date: Date) -> RaceWeekendEntry {
        RaceWeekendEntry(date: date,
            snapshot: RaceWidgetCache.readUpcoming()?.nextSession(at: date) ?? RaceWidgetCache.read()?.advancing(to: date),
            timing: RaceWidgetCache.readTiming())
    }
}

struct WidgetHeading: View {
    var label: String
    var trailing: String? = nil
    var warning = false
    var body: some View {
        HStack(spacing: 4) {
            Text("PITPULSE").font(.system(size: 9, weight: .heavy)).tracking(1.6).foregroundStyle(widgetRed)
            Spacer(minLength: 0)
            Text(trailing ?? label).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                .foregroundStyle(warning ? .orange : Color.primary.opacity(0.55))
        }
    }
}

struct WidgetEmpty: View {
    let title: String
    let icon: String
    var message = "打开 App 同步数据"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeading(label: "FORMULA 1")
            Spacer(minLength: 0)
            Image(systemName: icon).font(.title3).foregroundStyle(widgetRed)
            Text(title).font(.headline)
            Text(message).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum WeekendSessionStyle {
    static func category(_ title: String) -> String {
        if title.hasPrefix("FP") { return "PRACTICE" }
        if title.contains("Sprint") || title.contains("冲刺") { return "SPRINT" }
        if title.contains("排位") { return "QUALIFYING" }
        if title.contains("正赛") { return "RACE" }
        return "SESSION"
    }

    static func isRace(_ title: String) -> Bool { title == "正赛" }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func monthDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.twoDigits).day())
    }

    static func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    static func range(_ sessions: [RaceWidgetSession]) -> String {
        let dates = sessions.map(\.start)
        guard let first = dates.min(), let last = dates.max() else { return "" }
        if Calendar.current.isDate(first, inSameDayAs: last) { return monthDay(first) }
        return "\(monthDay(first))–\(monthDay(last))"
    }
}
func widgetDriverLabel(_ name: String, number: String?) -> String {
    (number.map { "#\($0) " } ?? "") + MotorsportAssetName.abbreviation(name)
}

struct WidgetTeamLogo: View {
    let constructorID: String?
    let season: Int

    var body: some View {
        if let constructorID {
            MotorsportImages.image(named: MotorsportAssetName.name(kind: .teamLogo, id: constructorID, season: season))
                .resizable().scaledToFit().accessibilityHidden(true)
        }
    }
}
#endif
