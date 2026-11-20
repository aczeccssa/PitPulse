import SharedData
import SwiftUI

struct LiveDriverDetail: View {
    @EnvironmentObject private var model: MobileModel
    @Environment(\.dismiss) private var dismiss
    let number: String
    private var driver: LiveDriver? { model.liveSnapshot.drivers.first { $0.number == number } }
    var body: some View {
        NavigationStack {
            ScrollView {
                if let driver {
                    VStack(alignment: .leading, spacing: 20) {
                        driverCard(driver)
                        PulseCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Current Lap Sectors").font(.headline)
                                LiveSectorTimes(sectors: driver.sectors ?? [], showsSegments: true)
                                HStack {
                                    Label(driver.bestLap ?? "—", systemImage: "stopwatch")
                                        .accessibilityLabel("Fastest lap \(driver.bestLap ?? "Unknown")")
                                    Spacer()
                                    PulseNumber("Last lap \(driver.lastLap ?? "—")")
                                }
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }
                        }
                        TelemetryChartPanel(samples: model.liveHistory[number] ?? [], driver: driver)
                    }.padding(20)
                } else { ContentUnavailableView("No data for this driver", systemImage: "person.crop.circle.badge.questionmark") }
            }
            .background(PulseStyle.background)
            .navigationTitle("Driver Charts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close driver charts", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
        }
    }

    private func driverCard(_ driver: LiveDriver) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AssetImage(name: model.helmetAsset(for: driver))
                    .frame(width: 52, height: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text("#\(number)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(driver.name ?? "Car \(number)")
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 4)
                if let position = driver.position ?? driver.classPosition {
                    PulseNumber("P\(position)")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(PulseStyle.red)
                        .contentTransition(.numericText())
                }
            }
            Divider()
            HStack(spacing: 8) {
                LiveTireBadge(driver: driver, size: 24)
                PulseNumber(driver.tireAgeLaps.map { "Tire age \($0) laps" } ?? "Tire age —")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                Spacer()
                LiveDriverTrackStatus(driver: driver, showsOnTrack: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardPanel(WebDashboardStyle.homePanel)
    }
}

struct LiveTireBadge: View {
    let driver: LiveDriver
    var size: CGFloat = 18

    var body: some View {
        let color: Color = switch driver.tireShortLabel {
        case "S": PulseStyle.red
        case "M": WebDashboardStyle.adaptive(dark: 0xffd34e, light: 0x855400)
        case "H": .primary
        case "I": WebDashboardStyle.adaptive(dark: 0x68d6a1, light: 0x176640)
        case "W": .blue
        default: .secondary
        }
        Text(driver.tireShortLabel ?? "—")
            .font(.caption2.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .overlay { Circle().strokeBorder(color, lineWidth: 1.5) }
            .accessibilityLabel(driver.tireCompound ?? "Unknown compound")
    }
}

struct LiveDriverTrackStatus: View {
    let driver: LiveDriver
    var showsOnTrack = false

    var body: some View {
        if driver.retired == true {
            status("Retired", color: PulseStyle.red)
        } else if driver.inPit == true {
            status("In Pit", color: WebDashboardStyle.adaptive(dark: 0xffcc66, light: 0x855400))
        } else if showsOnTrack {
            status(driver.inPit == false ? "On Track" : "Unknown Status", color: .secondary)
        }
    }

    private func status(_ title: String, color: Color) -> some View {
        Text(title)
            .font((showsOnTrack ? Font.caption : .caption2).weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, showsOnTrack ? 8 : 4)
            .padding(.vertical, 3)
            .background(color.opacity(0.11), in: .rect(cornerRadius: 4))
    }
}

struct LiveSectorTimes: View {
    let sectors: [LiveSector]
    let showsSegments: Bool

    var body: some View {
        HStack(alignment: .top, spacing: showsSegments ? 8 : 4) {
            ForEach(0..<3, id: \.self) { index in
                let sector = sectors.indices.contains(index) ? sectors[index] : nil
                let segments = sector?.segments ?? []
                VStack(spacing: 4) {
                    if showsSegments {
                        HStack(spacing: 4) {
                            Text("S\(index + 1)").foregroundStyle(.secondary)
                            Spacer(minLength: 2)
                            sectorTime(sector)
                        }
                        .font(.caption.weight(.semibold))
                        HStack(spacing: 2) {
                            if segments.isEmpty {
                                RoundedRectangle(cornerRadius: 1).fill(.secondary.opacity(0.25))
                            } else {
                                ForEach(segments.indices, id: \.self) { index in
                                    RoundedRectangle(cornerRadius: 1).fill(segmentStyle(segments[index]).color)
                                }
                            }
                        }
                        .frame(height: 4)
                        .accessibilityHidden(true)
                    } else {
                        sectorTime(sector).font(.caption2.weight(.semibold))
                        Capsule()
                            .fill(sectorColor(sector))
                            .frame(height: 3)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("S\(index + 1)，\(sector?.value ?? "No Results Yet")"
                                    + (showsSegments && !segments.isEmpty ? ", mini-sectors " + segments.map { segmentStyle($0).label }.joined(separator: "、") : ""))
            }
        }
    }

    private func sectorTime(_ sector: LiveSector?) -> some View {
        PulseNumber(sector?.value ?? "—")
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func sectorColor(_ sector: LiveSector?) -> Color {
        guard sector?.value?.isEmpty == false else { return .secondary.opacity(0.25) }
        if sector?.overallFastest == true { return .purple }
        if sector?.personalFastest == true { return .green }
        if sector?.overallFastest == false || sector?.personalFastest == false { return .yellow }
        return .secondary.opacity(0.5)
    }

    private func segmentStyle(_ status: Int?) -> (color: Color, label: String) {
        switch status {
        case 2048: (.yellow, "Yellow")
        case 2049: (.green, "Green")
        case 2051: (.purple, "Purple")
        case 2064: (.blue, "Blue")
        default: (.secondary.opacity(0.25), "Unknown")
        }
    }
}
