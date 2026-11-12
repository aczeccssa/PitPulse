import AppKit
import SwiftUI
import SharedData

struct LiveTireInline: View {
    let driver: LiveDriver
    var fontSize: CGFloat = 9

    private var color: Color {
        switch driver.tireCompound?.uppercased() {
        case "SOFT": .red
        case "MEDIUM": .yellow
        case "HARD": .white
        case "INTERMEDIATE", "INTER": .green
        case "WET": .blue
        default: .gray
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(driver.tireShortLabel ?? "—")
                .font(.system(size: fontSize, weight: .heavy))
                .foregroundStyle(color)
            if let age = driver.tireAgeLaps {
                Text("\(age)")
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .help(driver.tireLabel.map { "轮胎 \($0)" } ?? "轮胎未提供")
        .accessibilityLabel(driver.tireLabel.map { "轮胎 \($0)" } ?? "轮胎未提供")
    }
}

