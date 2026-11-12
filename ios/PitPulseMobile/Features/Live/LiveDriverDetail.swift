import Charts
import SharedData
import SwiftUI

struct LiveDriverDetail: View {
    @EnvironmentObject private var model: MobileModel
    let number: String
    private var driver: LiveDriver? { model.liveSnapshot.drivers.first { $0.number == number } }
    var body: some View {
        NavigationStack {
            ScrollView {
                if let driver {
                    VStack(alignment: .leading, spacing: 20) {
                        PulseHeading(eyebrow: "\(model.liveSnapshot.statusLabel) · #\(number)", title: driver.name ?? "Car \(number)")
                        HStack { Text(driver.team ?? "—"); Spacer(); Text(driver.position.map { "P\($0)" } ?? "—").bold(); Text(driver.gap ?? "—").monospacedDigit() }.font(.caption).foregroundStyle(.secondary)
                        TelemetryChartPanel(samples: model.liveHistory[number] ?? [], driver: driver)
                        PulseCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text("本圈分段").font(.headline); Spacer(); Text("秒").font(.caption2).foregroundStyle(.secondary) }
                                Chart(Array((driver.sectors ?? []).enumerated()), id: \.offset) { index, sector in
                                    if let value = sector.value.flatMap(LiveIslandLogic.sectorSeconds), value.isFinite, value >= 0 {
                                        BarMark(x: .value("分段", "S\(index + 1)"), y: .value("秒", value))
                                            .foregroundStyle(sector.overallFastest == true ? Color.purple : sector.personalFastest == true ? .green : PulseStyle.red)
                                            .cornerRadius(5)
                                            .annotation(position: .top) { Text(value.formatted(.number.precision(.fractionLength(3)))).font(.system(size: 10).monospacedDigit()) }
                                    }
                                }.frame(height: 150)
                                HStack { Label(driver.bestLap ?? "—", systemImage: "stopwatch"); Spacer(); Text("上一圈 \(driver.lastLap ?? "—")") }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        PulseCard {
                            HStack(spacing: 16) {
                                Text(driver.tireShortLabel ?? "?").font(.title.bold()).foregroundStyle(.red).frame(width: 46, height: 46).overlay(Circle().stroke(.red, lineWidth: 2))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(driver.tireCompound ?? "轮胎未知").font(.headline)
                                    Text(driver.tireAgeLaps.map { "已使用 \($0) 圈" } ?? "胎龄未知").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(driver.retired == true ? "退赛" : driver.inPit == true ? "进站" : driver.inPit == false ? "赛道中" : "状态未知").font(.caption)
                            }
                        }
                    }.padding(20)
                } else { ContentUnavailableView("暂无此车手数据", systemImage: "person.crop.circle.badge.questionmark") }
            }.background(PulseStyle.background).navigationTitle("车手图表").navigationBarTitleDisplayMode(.inline)
        }
    }
}
