import SceneKit
import SharedComponents
import SharedData
import SwiftUI

enum IslandPreviewGeometry {
    /// Expanded island uses the same continuous corner for its fill and clipping.
    static let expandedRadius: CGFloat = 44
}

/// Deterministic fixture updates; these never enter the actual ActivityKit stream.
struct IslandPreviewSample {
    var state: PitPulseActivityAttributes.ContentState
    var numbers: ActivityPreviewNumbers
    init(state source: PitPulseActivityAttributes.ContentState, elapsed: Double, reduceMotion: Bool) {
        state = source
        let step = Int(elapsed / 5) % 4
        let prior = (step + 3) % 4
        var previous: [String: String] = [:]
        func value(_ values: [String]) -> String {
            previous[values[step]] = values[prior]
            return values[step]
        }
        state.lapLabel = value(["L32/71", "L33/71", "L34/71", "L35/71"])
        let gap = value(["+0.842", "+0.716", "+0.584", "+0.691"])
        state.battleGap = gap; state.challengerGap = gap
        if var driver = state.trackedDriver {
            driver.gap = gap; driver.interval = gap
            let speed = [312, 318, 305, 321]
            previous["\(speed[step]) km/h"] = "\(speed[prior]) km/h"
            driver.speed = speed[step]
            driver.lastLap = value(["1:11.482", "1:11.368", "1:11.206", "1:11.417"])
            driver.tire = value(["M 18", "M 19", "M 20", "M 21"])
            if !driver.sectors.isEmpty {
                driver.sectors[0].time = value(["18.426", "18.372", "18.298", "18.411"])
            }
            state.trackedDriver = driver
        }
        if state.podium?.count ?? 0 > 1 { state.podium?[1].gap = gap }
        if state.battleDrivers?.count ?? 0 > 1 {
            state.battleDrivers?[1].gap = gap
            state.battleDrivers?[1].tire = state.trackedDriver?.tire
        }
        let phase = elapsed.truncatingRemainder(dividingBy: 5) / 0.32
        numbers = .init(previous: elapsed < 5 ? [:] : previous, progress: min(1, 1 - pow(1 - min(1, phase), 3)), reduceMotion: reduceMotion)
    }
}
