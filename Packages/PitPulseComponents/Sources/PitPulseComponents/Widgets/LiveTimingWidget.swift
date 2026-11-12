#if os(iOS) || os(macOS)
import SwiftUI
import Charts
import WidgetKit
import PitPulseShared

public struct LiveTimingWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: RaceWidgetCache.timingKind, provider: RaceWeekendProvider()) { entry in
            LiveTimingWidgetView(entry: entry).containerBackground(widgetBackground, for: .widget)
                .widgetURL(WidgetDestination.live.url)
        }
        .configurationDisplayName("实时计时 · Formula 1")
        .description("小尺寸前两位，中尺寸前三位，大尺寸完整前八位。明确标记回放和过期数据。")
        .supportedFamilies(raceWidgetFamilies)
    }
}

struct LiveTimingWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    let entry: RaceWeekendEntry
    var previewFamily: WidgetFamily? = nil
    private var family: WidgetFamily { previewFamily ?? systemFamily }
    var body: some View {
        if let timing = entry.timing {
            switch family {
            case .systemSmall: small(timing)
            case .systemMedium: medium(timing)
            case .systemLarge: large(timing)
            #if os(iOS)
            case .accessoryInline:
                Text("\(status(timing)) · \(timing.lap) · \(timing.drivers.first?.name ?? timing.session)")
            case .accessoryCircular:
                VStack(spacing: 2) { Image(systemName: "flag.checkered"); Text(timing.isStale(at: entry.date) ? "过期" : timing.lap).font(.system(size: 9, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7) }
            #endif
            default:
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(timing.session).bold(); Spacer(); Text(timing.lap) }.font(.caption)
                    Text("\(status(timing)) · \(timing.drivers.first?.name ?? timing.meeting)").font(.caption2).lineLimit(1)
                }
            }
        } else { WidgetEmpty(title: "F1 实时计时", icon: "antenna.radiowaves.left.and.right") }
    }
    private func status(_ timing: RaceTimingSnapshot) -> String {
        guard timing.isStale(at: entry.date) else { return timing.status }
        return timing.status.contains("回放") ? "回放 · 数据过期" : "数据过期"
    }
    private func small(_ timing: RaceTimingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeading(label: status(timing), warning: timing.isStale(at: entry.date))
            Text(timing.lap).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1)
            Text(timing.meeting).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            ForEach(Array(timing.drivers.prefix(2))) { row in driverRow(row, compact: true) }
        }
    }
    private func medium(_ timing: RaceTimingSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("PITPULSE").font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundStyle(widgetRed)
                Text(timing.session.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
                Text(timing.lap).font(.title2.bold().monospacedDigit())
                Text(status(timing)).font(.system(size: 9, weight: .semibold)).foregroundStyle(timing.isStale(at: entry.date) ? .orange : widgetRed)
            }.frame(width: 95, alignment: .leading)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
            VStack(alignment: .leading, spacing: 10) {
                Text(timing.meeting).font(.system(size: 10, weight: .semibold)).lineLimit(1).foregroundStyle(.secondary)
                ForEach(Array(timing.drivers.prefix(3))) { row in driverRow(row, compact: true) }
            }.frame(maxWidth: .infinity)
        }
    }
    private func large(_ timing: RaceTimingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeading(label: status(timing), warning: timing.isStale(at: entry.date))
            HStack(alignment: .firstTextBaseline) {
                Text(timing.meeting).font(.headline).lineLimit(2)
                Spacer(minLength: 8)
                Text(timing.lap).font(.title3.bold().monospacedDigit())
            }
            Text("距离领跑车手 · 秒").font(.system(size: 9)).foregroundStyle(.secondary)
            Chart(Array(timing.drivers.prefix(8))) { row in
                if let gap = widgetGap(row.gap) {
                    BarMark(x: .value("秒差", gap), y: .value("车手", MotorsportAssetName.abbreviation(row.name)))
                        .foregroundStyle(widgetRed).cornerRadius(2)
                        .annotation(position: .trailing) { Text(gap == 0 ? "P1" : String(format: "+%.1f", gap)).font(.system(size: 8).monospacedDigit()) }
                }
            }.frame(height: 135).chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            Divider()
            ForEach(Array(timing.drivers.prefix(3))) { row in driverRow(row, compact: false) }
            Spacer(minLength: 0)
            HStack { Text(timing.session); Spacer(); Text("更新 "); Text(timing.updatedAt, style: .time) }.font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
    private func widgetGap(_ text: String) -> Double? {
        if text.uppercased() == "LEADER" { return 0 }
        guard let value = Double(text.replacingOccurrences(of: "+", with: "")), value.isFinite, value >= 0 else { return nil }
        return value
    }
    private func driverRow(_ driver: RaceTimingDriver, compact: Bool) -> some View {
        HStack(spacing: compact ? 5 : 9) {
            Text(driver.position.map(String.init) ?? "—").fontWeight(.semibold).frame(width: compact ? 10 : 16, alignment: .leading)
            MotorsportImages.image(named: MotorsportAssetName.helmetName(name: driver.name, season: 2026)).resizable().scaledToFit()
                .frame(width: compact ? 18 : 25, height: compact ? 16 : 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(MotorsportAssetName.abbreviation(driver.name)).fontWeight(.bold).lineLimit(1)
                if !compact, let asset = driver.teamAsset {
                    MotorsportImages.image(named: asset).resizable().scaledToFit().frame(width: 18, height: 8).accessibilityHidden(true)
                }
            }
            Spacer(minLength: 2)
            Text(driver.gap).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if !compact { Text(driver.tire ?? "—").font(.system(size: 9, weight: .bold)).foregroundStyle(widgetRed).frame(width: 16) }
        }.font(.system(size: compact ? 10 : 11))
    }
}

#if DEBUG
#Preview("Widget Preview · Live Timing") {
    WidgetSizePreview(families: [.systemSmall, .systemMedium, .systemLarge]) { family in
        LiveTimingWidgetView(entry: RaceWeekendEntry(date: WidgetPreviewData.now, snapshot: nil, timing: WidgetPreviewData.timing), previewFamily: family)
    }
}
#endif
#endif
