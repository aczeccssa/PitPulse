import Foundation

#if os(iOS)
import ActivityKit

/// The cross-process contract between the iOS app (which owns the live stream)
/// and the Live Activity / Dynamic Island extension (which renders it).
public struct PitPulseActivityAttributes: ActivityAttributes {
    public struct Driver: Codable, Hashable, Sendable {
        public var name: String
        public var position: Int?
        public var asset: String?
        public var gap: String?
        public var interval: String?
        public var speed: Int?
        public var tire: String?
        public var lastLap: String?
        public var positionChange: Int?
        public var sectors: [Sector]
        public init(name: String, position: Int? = nil, asset: String? = nil, gap: String? = nil, interval: String? = nil, speed: Int? = nil, tire: String? = nil, lastLap: String? = nil, sectors: [Sector] = [], positionChange: Int? = nil) {
            self.name = name; self.position = position; self.asset = asset; self.gap = gap
            self.interval = interval; self.speed = speed; self.tire = tire; self.lastLap = lastLap; self.sectors = sectors; self.positionChange = positionChange
        }
    }
    public struct Sector: Codable, Hashable, Sendable {
        public var time: String?
        public var segments: [Int?]
        public var personalFastest: Bool?
        public var overallFastest: Bool?
        public init(time: String? = nil, segments: [Int?] = [], personalFastest: Bool? = nil, overallFastest: Bool? = nil) {
            self.time = time; self.segments = segments
            self.personalFastest = personalFastest; self.overallFastest = overallFastest
        }
    }
    public struct Weather: Codable, Hashable, Sendable {
        public var rainfall: Bool?
        public var airTemperature: Double?
        public var trackTemperature: Double?
        public var visibilityMeters: Int?
        public init(rainfall: Bool? = nil, airTemperature: Double? = nil, trackTemperature: Double? = nil, visibilityMeters: Int? = nil) {
            self.rainfall = rainfall; self.airTemperature = airTemperature
            self.trackTemperature = trackTemperature; self.visibilityMeters = visibilityMeters
        }
    }
    public struct ContentState: Codable, Hashable, Sendable {
        public var sessionName: String
        public var meetingName: String
        public var statusLabel: String
        public var lapLabel: String
        public var leaderName: String?
        public var leaderGap: String?
        public var challengerName: String?
        public var challengerGap: String?
        public var leaderAsset: String?
        public var challengerAsset: String?
        public var trackLabel: String?
        public var driverCount: Int
        public var isStale: Bool
        public var updatedLabel: String?
        public var presentation: String?
        public var favoriteName: String?
        public var favoritePosition: Int?
        public var favoriteGap: String?
        public var favoriteGapLabel: String?
        public var favoriteAsset: String?
        public var podium: [Driver]?
        public var battleDrivers: [Driver]?
        public var trackedDriver: Driver?
        public var battleGap: String?
        public var weather: Weather?
        public var positionDrivers: [Driver]?
        public var positionFocus: String?
        public var positionWindowStart: Int?

        public init(
            sessionName: String,
            meetingName: String,
            statusLabel: String,
            lapLabel: String,
            leaderName: String? = nil,
            leaderGap: String? = nil,
            challengerName: String? = nil,
            challengerGap: String? = nil,
            leaderAsset: String? = nil,
            challengerAsset: String? = nil,
            trackLabel: String? = nil,
            driverCount: Int = 0,
            isStale: Bool = false,
            updatedLabel: String? = nil,
            presentation: String? = nil,
            favoriteName: String? = nil,
            favoritePosition: Int? = nil,
            favoriteGap: String? = nil,
            favoriteGapLabel: String? = nil,
            favoriteAsset: String? = nil,
            podium: [Driver]? = nil,
            battleDrivers: [Driver]? = nil,
            trackedDriver: Driver? = nil,
            battleGap: String? = nil,
            weather: Weather? = nil,
            positionDrivers: [Driver]? = nil,
            positionFocus: String? = nil,
            positionWindowStart: Int? = nil
        ) {
            self.sessionName = sessionName
            self.meetingName = meetingName
            self.statusLabel = statusLabel
            self.lapLabel = lapLabel
            self.leaderName = leaderName
            self.leaderGap = leaderGap
            self.challengerName = challengerName
            self.challengerGap = challengerGap
            self.leaderAsset = leaderAsset
            self.challengerAsset = challengerAsset
            self.trackLabel = trackLabel
            self.driverCount = driverCount
            self.isStale = isStale
            self.updatedLabel = updatedLabel
            self.presentation = presentation
            self.favoriteName = favoriteName
            self.favoritePosition = favoritePosition
            self.favoriteGap = favoriteGap
            self.favoriteGapLabel = favoriteGapLabel
            self.favoriteAsset = favoriteAsset
            self.podium = podium; self.battleDrivers = battleDrivers
            self.trackedDriver = trackedDriver; self.battleGap = battleGap
            self.weather = weather
            self.positionDrivers = positionDrivers; self.positionFocus = positionFocus
            self.positionWindowStart = positionWindowStart
        }
    }

    public var seriesTitle: String

    public init(seriesTitle: String) {
        self.seriesTitle = seriesTitle
    }
}
#endif

#if os(iOS)
import SwiftUI

/// Shared by the actual Live Activity and the in-app mode preview.
public struct ActivityStatus: View {
    let state: PitPulseActivityAttributes.ContentState
    let expired: Bool
    public init(state: PitPulseActivityAttributes.ContentState, expired: Bool) {
        self.state = state
        self.expired = expired
    }
    public var body: some View {
        Text(state.isStale || expired ? "数据过期" : state.statusLabel)
            .font(.system(size: 10, weight: .bold)).lineLimit(1)
            .foregroundStyle(state.isStale || expired ? Color.orange : Color.secondary)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background((state.isStale || expired ? Color.orange : Color.clear).opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
    }
}

public extension PitPulseActivityAttributes.ContentState {
    var lapProgress: Double? {
        let values = lapLabel.replacingOccurrences(of: "L", with: "").split(separator: "/")
        guard values.count == 2, let current = Double(values[0]), let total = Double(values[1]),
              current.isFinite, total.isFinite, current >= 0, total > 0, current <= total else { return nil }
        return current / total
    }

    var compactLeadingText: String {
        if presentation == IslandContentMode.positionChanges.rawValue { return "P1 · " + (leaderName.map(MotorsportAssetName.abbreviation) ?? "—") }
        if presentation == IslandContentMode.favorite.rawValue || (presentation == IslandContentMode.battle.rawValue && battleDrivers?.count == 1) {
            return (presentation == IslandContentMode.battle.rawValue ? battleDrivers?.first?.name : trackedDriver?.name ?? favoriteName).map(MotorsportAssetName.abbreviation) ?? "车手"
        }
        if presentation == IslandContentMode.battle.rawValue {
            return battleDrivers.map { $0.map { $0.position.map { "P\($0)" } ?? "—" }.joined(separator: "·") } ?? "P1·P2"
        }
        return sessionName.uppercased()
    }

    var compactTrailingText: String {
        if presentation == IslandContentMode.positionChanges.rawValue { return positionFocus.map(MotorsportAssetName.abbreviation) ?? lapLabel }
        if presentation == IslandContentMode.favorite.rawValue || (presentation == IslandContentMode.battle.rawValue && battleDrivers?.count == 1) { return (presentation == IslandContentMode.battle.rawValue ? battleDrivers?.first?.position : trackedDriver?.position ?? favoritePosition).map { "P\($0)" } ?? "—" }
        if presentation == IslandContentMode.battle.rawValue { return (battleDrivers == nil ? challengerGap : battleGap) ?? "—" }
        return lapLabel
    }

    var trackColor: Color {
        let label = (trackLabel ?? "").lowercased()
        if label.contains("红旗") || label.contains("red flag") { return .red }
        if label.contains("黄旗") || label.contains("安全车") || label.contains("yellow") || label.contains("safety car") { return .yellow }
        if label.contains("绿旗") || label.contains("green") { return .green }
        return .secondary
    }
}

/// Explicit frames let the SceneKit preview display the same number-roll intent
/// as native ActivityKit's numeric content transition.
public struct ActivityPreviewNumbers: Sendable {
    public var previous: [String: String]
    public var progress: Double
    public var reduceMotion: Bool
    public init(previous: [String: String] = [:], progress: Double = 1, reduceMotion: Bool = false) {
        self.previous = previous; self.progress = progress; self.reduceMotion = reduceMotion
    }
}
private struct ActivityPreviewNumbersKey: EnvironmentKey {
    static let defaultValue = ActivityPreviewNumbers()
}
public extension EnvironmentValues {
    var activityPreviewNumbers: ActivityPreviewNumbers {
        get { self[ActivityPreviewNumbersKey.self] }
        set { self[ActivityPreviewNumbersKey.self] = newValue }
    }
}
public struct ActivityNumberText: View {
    let text: String
    @Environment(\.activityPreviewNumbers) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(_ text: String) { self.text = text }
    public var body: some View {
        if let previous = preview.previous[text], previous != text, preview.progress < 1 {
            Text(text).hidden().overlay {
                ZStack {
                    Text(previous).offset(y: (reduceMotion || preview.reduceMotion) ? 0 : -14 * preview.progress).opacity(1 - preview.progress)
                    Text(text).offset(y: (reduceMotion || preview.reduceMotion) ? 0 : 14 * (1 - preview.progress)).opacity(preview.progress)
                }.fixedSize()
            }.clipped().accessibilityLabel(text)
        } else {
            Text(text).contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(.easeOut(duration: 0.28), value: text)
        }
    }
}

public struct ActivityPayloadView: View {
    let state: PitPulseActivityAttributes.ContentState
    public init(state: PitPulseActivityAttributes.ContentState) { self.state = state }
    public var body: some View {
        switch state.presentation.flatMap(IslandContentMode.init(rawValue:)) ?? .overview {
        case .positionChanges:
            PositionChangesActivityView(state: state)
        case .battle:
            if state.battleDrivers?.count == 1 { TrackedDriverView(driver: state.battleDrivers![0], weather: state.weather) }
            else { BattleView(state: state) }
        case .favorite:
            TrackedDriverView(driver: state.trackedDriver ?? .init(name: state.favoriteName ?? "请先收藏一位车手", position: state.favoritePosition, asset: state.favoriteAsset, gap: state.favoriteGap), weather: state.weather)
        case .overview:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    ActivityNumberText(state.lapLabel).font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                    Spacer()
                    Label(state.trackLabel ?? "等待赛道状态", systemImage: "flag.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(state.trackColor).lineLimit(1)
                }
                if let progress = state.lapProgress {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.14))
                            Capsule().fill(state.trackColor).frame(width: geometry.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("比赛进度")
                    .accessibilityValue("\(Int(progress * 100))%")
                }
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array((state.podium ?? []).prefix(3).enumerated()), id: \.offset) { _, driver in
                        VStack(spacing: 3) {
                            DriverPortrait(driver: driver, size: 48)
                            ActivityNumberText(driver.position == 1 ? "LEADER" : driver.gap ?? "—").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }

            }
        }
    }
}

@MainActor
public enum ActivityHelmetImage {
    public static func thumbnail(named name: String) -> UIImage? {
        UIImage(named: name).flatMap { thumbnail(image: $0) }
    }
    public static func thumbnail(image: UIImage) -> UIImage? {
        image.preparingThumbnail(of: CGSize(width: 180, height: 180))
    }
}

private struct ActivityHelmet: View {
    let asset: String
    let size: CGFloat
    var body: some View {
        Group {
            if let image = ActivityHelmetImage.thumbnail(named: asset) { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "person.crop.circle").resizable().scaledToFit() }
        }.frame(width: size, height: size * 0.85).accessibilityHidden(true)
    }
}

private struct PositionChangesActivityView: View {
    let state: PitPulseActivityAttributes.ContentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var themeRed: Color { Color(red: 0.98, green: 0.25, blue: 0.23) }
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LAP").font(.system(size: 9)).foregroundStyle(.secondary)
                ActivityNumberText(state.lapLabel).font(.system(size: 18, weight: .bold, design: .rounded))
                Divider()
                HStack(spacing: 5) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("P1").font(.system(size: 9)).foregroundStyle(.secondary)
                        Text(state.leaderName.map(MotorsportAssetName.abbreviation) ?? "—")
                            .font(.system(size: 14, weight: .heavy)).foregroundStyle(themeRed)
                    }
                    if let asset = state.leaderAsset { ActivityHelmet(asset: asset, size: 30) }
                }
            }.frame(width: 98, alignment: .leading)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(state.positionDrivers ?? [], id: \.name) { driver in
                        HStack(spacing: 5) {
                            ActivityNumberText(driver.position.map(String.init) ?? "—").frame(width: 16)
                            if let asset = driver.asset { ActivityHelmet(asset: asset, size: 18) }
                            Text(MotorsportAssetName.abbreviation(driver.name)).fontWeight(.semibold)
                            if let delta = driver.positionChange, delta != 0 {
                                Image(systemName: delta > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                    .font(.system(size: 7)).foregroundStyle(delta > 0 ? .green : .red)
                            }
                            Spacer(minLength: 0)
                            ActivityNumberText(driver.position == 1 ? "LEADER" : driver.gap ?? "—").foregroundStyle(.secondary)
                        }
                        .font(.system(size: 9)).monospacedDigit()
                        .padding(.horizontal, 4).frame(width: geometry.size.width, height: 18)
                        .background(driver.name == state.positionFocus ? themeRed.opacity(0.20) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .offset(y: CGFloat((driver.position ?? 1) - 1 - (state.positionWindowStart ?? 0)) * 18)
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.65), value: state.positionDrivers)
            }.frame(height: 90).clipped()
        }.frame(height: 90)
    }
}

private struct DriverPortrait: View {
    let driver: PitPulseActivityAttributes.Driver
    var size: CGFloat = 56
    var body: some View {
        VStack(spacing: 2) {
            if let asset = driver.asset { ActivityHelmet(asset: asset, size: size) }
            ActivityNumberText("\(driver.position.map { "P\($0) · " } ?? "")\(MotorsportAssetName.abbreviation(driver.name))")
                .font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
    }
}

private struct SectorStrip: View {
    let sectors: [PitPulseActivityAttributes.Sector]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                let sector = sectors.indices.contains(index) ? sectors[index] : nil
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 3) {
                        Text("S\(index + 1)").foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        ActivityNumberText(sector?.time ?? "—").monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    }.font(.system(size: 9))
                    HStack(spacing: 2) {
                        let segments = sector?.segments.isEmpty == false ? sector!.segments : [nil]
                        ForEach(segments.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1).fill(color(segments[i]))
                        }
                    }.frame(height: 4)
                }
            }
        }.accessibilityLabel("分段计时与进度")
    }
    private func color(_ value: Int?) -> Color {
        switch value { case 2048: .yellow; case 2049: .green; case 2051: .purple; case 2064: .blue; default: .white.opacity(0.15) }
    }
}

private struct DriverWeatherView: View {
    let weather: PitPulseActivityAttributes.Weather?
    private var condition: String {
        switch weather?.rainfall { case true: "降雨"; case false: "无降雨"; case nil: "天气 —" }
    }
    private var visibility: String {
        guard let meters = weather?.visibilityMeters, meters > 0 else { return "—" }
        return meters >= 1000 ? String(format: "%.1f km", Double(meters) / 1000) : "\(meters) m"
    }
    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Label(condition, systemImage: weather?.rainfall == true ? "cloud.rain.fill" : "drop")
                .font(.system(size: 10, weight: .medium))
            ActivityNumberText("可见度 \(visibility)").font(.system(size: 9)).foregroundStyle(.secondary)
            ActivityNumberText("气温 \(temperature(weather?.airTemperature))")
            ActivityNumberText("赛道 \(temperature(weather?.trackTemperature))")
        }
        .font(.system(size: 10, design: .monospaced))
        .lineLimit(1).minimumScaleFactor(0.8)
        .frame(width: 80, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }
    private func temperature(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.0f°C", value)
    }
}

private struct TrackedDriverView: View {
    let driver: PitPulseActivityAttributes.Driver
    let weather: PitPulseActivityAttributes.Weather?
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                DriverPortrait(driver: driver, size: 66)
                VStack(alignment: .leading, spacing: 5) {
                    Text(driver.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    HStack { metric("距领先", driver.gap); metric("距前车", driver.interval) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                DriverWeatherView(weather: weather)
            }
            SectorStrip(sectors: driver.sectors)
            HStack {
                metric("速度", driver.speed.map { "\($0) km/h" })
                Spacer(minLength: 4)
                metric("轮胎", driver.tire)
                Spacer(minLength: 4)
                metric("上圈", driver.lastLap)
            }
        }
    }
    private func metric(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            ActivityNumberText(value ?? "—").font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BattleView: View {
    let state: PitPulseActivityAttributes.ContentState
    private var drivers: [PitPulseActivityAttributes.Driver] {
        state.battleDrivers ?? [.init(name: state.leaderName ?? "—", position: 1, asset: state.leaderAsset), .init(name: state.challengerName ?? "—", position: 2, asset: state.challengerAsset)]
    }
    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                if let first = drivers.first { driverColumn(first) }
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    ActivityNumberText((state.battleDrivers == nil ? state.challengerGap : state.battleGap) ?? "—").font(.system(size: 27, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    Text("两车差距").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if drivers.count > 1 { driverColumn(drivers[1]) }
            }

        }
    }
    private func driverColumn(_ driver: PitPulseActivityAttributes.Driver) -> some View {
        VStack(spacing: 9) {
            DriverPortrait(driver: driver, size: 58)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    let sector = driver.sectors.indices.contains(index) ? driver.sectors[index] : nil
                    VStack(spacing: 3) {
                        Text("S\(index + 1)").font(.system(size: 9)).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 2).fill(sectorColor(sector)).frame(height: 5)
                    }
                    .accessibilityLabel("S\(index + 1)，\(sector?.time ?? "未完成")")
                }
            }
            ActivityNumberText(driver.tire ?? "—").font(.system(size: 9)).foregroundStyle(.secondary)
        }.frame(width: 88)
    }

    private func sectorColor(_ sector: PitPulseActivityAttributes.Sector?) -> Color {
        guard let sector, let time = sector.time, !time.isEmpty else { return .white.opacity(0.15) }
        if sector.overallFastest == true { return .purple }
        if sector.personalFastest == true { return .green }
        return .yellow
    }

}

#endif

#if canImport(UIKit)
import UIKit

/// Pixel-backed RGBA textures for SceneKit; independent of device display scale.
@MainActor
public enum IslandPreviewTexture {
    // Fixed pixel dimensions and RGBA8 avoid UIKit's implicit @3x scaling
    // and grayscale formats unsupported by SceneKit's Metal texture loader.
    public static func make(width: Int, height: Int, draw: (CGContext) -> Void) -> UIImage {
        let bitmap = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        UIGraphicsPushContext(bitmap)
        draw(bitmap)
        UIGraphicsPopContext()
        return UIImage(cgImage: bitmap.makeImage()!, scale: 1, orientation: .up)
    }
}
#endif
