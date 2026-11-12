import AppKit
import SwiftUI
import SharedData

struct LiveIslandCompactLeading: View {
    @ObservedObject var model: AppModel
    @ObservedObject var actions: LiveIslandActions

    private var snapshot: LiveSnapshot { actions.snapshot }
    private var hasTiming: Bool { snapshot.sourceStatus == .connected }
    private var favorite: LiveDriver? {
        LiveIslandLogic.matchedDriver(
            favoriteId: model.favoriteDriverId(for: snapshot.isWec ? .wec : .f1),
            favorites: model.favoriteDrivers,
            drivers: hasTiming ? snapshot.drivers : []
        )
    }
    private var lapText: String {
        if snapshot.isWec, let laps = favorite?.lapCount { return "L\(laps)" }
        return snapshot.lapLabel
    }
    private var alertCode: String? {
        guard hasTiming else { return nil }
        return switch snapshot.trackCondition {
        case .clear, .unknown: nil
        case .yellow: "YF"
        case .fullCourseYellow: "FCY"
        case .safetyCar, .safetyCarEnding: "SC"
        case .virtualSafetyCar, .virtualSafetyCarEnding: "VSC"
        case .red: "RF"
        }
    }
    private var alertColor: Color {
        switch snapshot.trackCondition {
        case .yellow, .fullCourseYellow, .safetyCar: .yellow
        case .safetyCarEnding, .virtualSafetyCar, .virtualSafetyCarEnding: .orange
        case .red: .red
        default: .clear
        }
    }
    private var alertTextColor: Color {
        switch snapshot.trackCondition {
        case .yellow, .fullCourseYellow, .safetyCar: .black.opacity(0.8)
        default: .white
        }
    }

    var body: some View {
        Button { actions.expand?() } label: {
            HStack(spacing: 5) {
                if let logo = MotorsportAsset.seriesLogo(isWec: snapshot.isWec) {
                    Image(nsImage: logo)
                        .resizable().scaledToFit()
                        .frame(height: 11)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: AppSymbol.menuBar.resolvedSystemName())
                }
                Text(LiveIslandLogic.sessionLabel(snapshot.sessionType
                    ?? snapshot.sessionName
                    ?? model.currentIslandSession.map { $0.session.sessionType.displayName }
                    ?? model.nextSession.map { $0.session.sessionType.displayName }
                    ?? "PitPulse"))
                    .lineLimit(1)
                if hasTiming {
                    Text(lapText).monospacedDigit()
                }
                if let alertCode {
                    Text(alertCode)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(alertTextColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(alertColor, in: Capsule())
                        .accessibilityLabel(snapshot.trackCondition.label)
                }
            }
            .padding(.horizontal, alertCode == nil ? 0 : 8)
            .padding(.vertical, alertCode == nil ? 0 : 4)
            .background(alertCode == nil ? Color.clear : alertColor.opacity(0.18), in: Capsule())
            .overlay {
                if alertCode != nil {
                    Capsule().strokeBorder(alertColor.opacity(0.5), lineWidth: 0.5)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
        .accessibilityLabel("\(snapshot.isWec ? "WEC" : "F1")，\(snapshot.sessionType ?? snapshot.sessionName ?? "F1 Session")，\(snapshot.sessionStateLabel)，\(hasTiming ? "\(lapText)，\(snapshot.trackCondition.label)" : snapshot.statusLabel)")
        .accessibilityIdentifier("liveIsland.expand")
        .accessibilityHint("展开 Live Island")
        .environment(\.colorScheme, .dark)
    }
}

