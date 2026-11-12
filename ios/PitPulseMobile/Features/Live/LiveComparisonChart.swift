import Charts
import SharedData
import SwiftUI

struct LiveComparisonChart: View {
    let drivers: [LiveDriver]
    let mode: Int
    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(mode == 0 ? "距离领跑车手" : "前八位圈速对比").font(.headline)
                Chart(Array(drivers.prefix(8)), id: \.number) { driver in
                    let name = MotorsportAssetName.abbreviation(driver.name ?? driver.number)
                    if mode == 0 {
                        if let gap = gapSeconds(driver.gap) {
                            BarMark(x: .value("差距 秒", gap), y: .value("车手", name)).foregroundStyle(PulseStyle.red).cornerRadius(3)
                                .annotation(position: .trailing) { Text(gap == 0 ? "LEADER" : String(format: "+%.3f", gap)).font(.system(size: 9).monospacedDigit()) }
                        }
                    } else {
                        if let best = driver.bestLap.flatMap(LiveIslandLogic.sectorSeconds), best.isFinite {
                            BarMark(x: .value("秒", best), y: .value("车手", name)).foregroundStyle(by: .value("圈速", "最快圈")).position(by: .value("圈速", "最快圈"))
                        }
                        if let last = driver.lastLap.flatMap(LiveIslandLogic.sectorSeconds), last.isFinite {
                            BarMark(x: .value("秒", last), y: .value("车手", name)).foregroundStyle(by: .value("圈速", "上一圈")).position(by: .value("圈速", "上一圈"))
                        }
                    }
                }.chartForegroundStyleScale(["最快圈": PulseStyle.red, "上一圈": Color.gray])
                    .frame(height: mode == 0 ? 185 : 220)
                Text(mode == 0 ? "仅对可换算为秒的差距绘图；被套圈不换算成虚构秒数。" : "最快圈与上一圈并排比较，原始圈速见下方计时表。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func gapSeconds(_ value: String?) -> Double? {
        guard let value else { return nil }
        if value.uppercased() == "LEADER" { return 0 }
        guard let number = Double(value.replacingOccurrences(of: "+", with: "")), number.isFinite, number >= 0 else { return nil }
        return number
    }
}
