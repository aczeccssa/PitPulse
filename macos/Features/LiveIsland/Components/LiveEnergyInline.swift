import AppKit
import SwiftUI
import SharedData

struct LiveEnergyInline: View {
    let percent: Double?

    private var color: Color {
        guard let percent else { return .gray }
        if percent < 25 { return .red }
        if percent < 50 { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 3) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(color).frame(width: max(1, 16 * min(max((percent ?? 0) / 100, 0), 1)))
            }
            .frame(width: 16, height: 3)
            Text(percent.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .help(percent.map { "虚拟能量剩余 \(Int($0.rounded()))%" } ?? "虚拟能量未提供")
        .accessibilityLabel(percent.map { "虚拟能量 \(Int($0.rounded()))%" } ?? "虚拟能量未提供")
    }
}

