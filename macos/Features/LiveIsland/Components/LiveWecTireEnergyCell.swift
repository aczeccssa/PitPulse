import AppKit
import SwiftUI
import SharedData

struct LiveWecTireEnergyCell: View {
    let driver: LiveDriver
    var showTire = true
    var showEnergy = true

    private var energyColor: Color {
        guard let percent = driver.energyPercent else { return .gray }
        if percent < 25 { return .red }
        if percent < 50 { return .orange }
        return .green
    }

    private var hasTire: Bool { showTire && driver.tireLabel != nil }
    private var hasEnergy: Bool { showEnergy && driver.energyPercent != nil }

    private var abilityLabel: String {
        let tire = hasTire ? driver.tireLabel.map { "轮胎 \($0)" } : nil
        let energy = hasEnergy ? driver.energyPercent.map { "虚拟能量 \(Int($0.rounded()))%" } : nil
        return [tire, energy].compactMap { $0 }.joined(separator: "，")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if hasTire {
                HStack(spacing: 5) {
                    LiveTireInline(driver: driver, fontSize: 11)
                }
            }
            if hasEnergy, let percent = driver.energyPercent {
                HStack(spacing: 4) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(energyColor)
                            .frame(width: max(1, 50 * min(max(percent / 100, 0), 1)))
                    }
                    .frame(width: 50, height: 5)
                    Text("\(Int(percent.rounded()))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(energyColor)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(abilityLabel.isEmpty ? "轮胎与能量未提供" : abilityLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(abilityLabel.isEmpty ? "轮胎与能量未提供" : abilityLabel)
    }
}

