import AppKit
import SwiftUI
import SharedData

struct LiveSectorView: View {
    let sector: LiveSector?
    let index: Int
    var showsSegments = true
    var referenceSeconds: Double? = nil

    private var color: Color {
        sector?.overallFastest == true ? .purple : sector?.personalFastest == true ? .green : .white
    }

    /// WEC has no mini-segment statuses, so its bar compares the sector time
    /// with the best time of the same class instead of per-segment colours.
    private var paceColor: Color {
        guard let referenceSeconds,
              let raw = sector?.value,
              let seconds = LiveIslandLogic.sectorSeconds(raw) else { return .gray.opacity(0.3) }
        let delta = seconds - referenceSeconds
        if delta <= 0.001 { return .purple }
        if delta <= 0.35 { return .green }
        if delta <= 1.0 { return .yellow }
        return .gray.opacity(0.55)
    }

    private func segmentColor(_ status: Int?) -> Color {
        switch status {
        case 2048: return .yellow
        case 2049: return .green
        case 2051: return .purple
        case 2064: return .blue
        default: return .gray.opacity(0.3)
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(sector?.value.flatMap { $0.isEmpty ? nil : $0 } ?? "—")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(showsSegments ? 1 : 0.78)
                .foregroundStyle(color)
            if showsSegments {
                if let segments = sector?.segments, !segments.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(segments.indices, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1).fill(segmentColor(segments[index]))
                        }
                    }.frame(height: 4)
                } else {
                    Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 4)
                }
            } else {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(paceColor)
                    .frame(height: 3)
            }
        }
        .accessibilityLabel("S\(index + 1)，\(sector?.value ?? "未提供")\(sector?.overallFastest == true ? "，全场最快" : sector?.personalFastest == true ? "，个人最快" : "")")
    }
}

