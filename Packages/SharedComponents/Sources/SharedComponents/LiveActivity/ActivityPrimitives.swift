#if os(iOS)
import SwiftUI
import SharedData

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
struct ActivityPreviewNumbersKey: EnvironmentKey {
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

@MainActor
public enum ActivityHelmetImage {
    public static func thumbnail(named name: String) -> UIImage? {
        MotorsportImages.uiImage(named: name).flatMap { thumbnail(image: $0) }
    }
    public static func thumbnail(image: UIImage) -> UIImage? {
        image.preparingThumbnail(of: CGSize(width: 180, height: 180))
    }
}

struct ActivityHelmet: View {
    let asset: String
    let size: CGFloat
    var body: some View {
        Group {
            if let image = ActivityHelmetImage.thumbnail(named: asset) { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "person.crop.circle").resizable().scaledToFit() }
        }.frame(width: size, height: size * 0.85).accessibilityHidden(true)
    }
}

struct DriverPortrait: View {
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

struct SectorStrip: View {
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

struct DriverWeatherView: View {
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

#endif
