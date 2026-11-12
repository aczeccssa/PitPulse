import AppKit
import SwiftUI
import SharedData

extension LiveIslandExpandedView {
    var mode: String { actions.mode }
    var showRadar: Bool { actions.showRadar }
    /// The detail strip follows the clicked row, not the favourite: liking a
    /// car must never replace what is currently selected. When nothing is
    /// selected it falls back to a favourite that is actually in this session,
    /// otherwise it stays empty ("No selected").
    var selectedDriver: LiveDriver? {
        if let number = actions.selectedNumber,
           let driver = snapshot.drivers.first(where: { $0.number == number }) {
            return driver
        }
        return favorite
    }
    var meeting: Meeting? { LiveIslandLogic.meeting(for: snapshot, in: model.meetings, now: Date()) }

    var snapshot: LiveSnapshot { actions.snapshot }
    var hasTiming: Bool { snapshot.sourceStatus == .connected }
    // WEC publishes no mini-sector segments, so the sector columns stay compact
    // and the freed width carries a larger tire/energy readout.
    var sectorWidth: CGFloat { snapshot.isWec ? 50 : 88 }
    var wecTelemetryWidth: CGFloat { 106 }
    var title: String {
        let components = [snapshot.meetingName, snapshot.sessionName ?? snapshot.sessionType].compactMap { $0 }
        if !components.isEmpty { return components.joined(separator: " · ") }
        return model.liveSeries == .wec ? "FIA WEC" : model.nextMeeting?.name ?? "PitPulse"
    }
    var favoriteID: String? {
        model.favoriteDriverId(for: snapshot.isWec ? .wec : .f1)
    }

    var favorite: LiveDriver? {
        LiveIslandLogic.matchedDriver(
            favoriteId: favoriteID,
            favorites: model.favoriteDrivers,
            drivers: hasTiming ? snapshot.drivers : []
        )
    }

    var wecClasses: [(id: String, label: String, count: Int)] {
        var labels: [String: String] = [:]
        var counts: [String: Int] = [:]
        var order: [String] = []
        for driver in snapshot.drivers {
            guard let id = driver.classId, !id.isEmpty else { continue }
            if counts[id] == nil {
                order.append(id)
                labels[id] = (driver.className ?? id).uppercased()
            }
            counts[id, default: 0] += 1
        }
        let priority = ["HYPERCAR": 0, "LMP1": 1, "LMP2": 1, "LMGT3": 2]
        return order.sorted { (priority[$0] ?? 9, $0) < (priority[$1] ?? 9, $1) }
            .map { (id: $0, label: labels[$0] ?? $0, count: counts[$0] ?? 0) }
    }

    /// Best sector time per class, used to colour WEC's compact sector bars
    /// when the upstream feed provides no per-segment statuses.
    var wecSectorBests: [String: [Double?]] {
        guard snapshot.isWec else { return [:] }
        var bests: [String: [Double?]] = [:]
        for driver in snapshot.drivers {
            let key = driver.classId ?? "ALL"
            var values = bests[key] ?? [nil, nil, nil]
            for index in 0..<min(3, driver.sectors?.count ?? 0) {
                guard let raw = driver.sectors?[index].value,
                      let seconds = LiveIslandLogic.sectorSeconds(raw) else { continue }
                values[index] = values[index].map { min($0, seconds) } ?? seconds
            }
            bests[key] = values
        }
        return bests
    }

    var visibleDrivers: [LiveDriver] {
        guard snapshot.isWec, let selected = actions.wecClass,
              wecClasses.contains(where: { $0.id == selected }) else { return snapshot.drivers }
        return snapshot.drivers.filter { $0.classId == selected }
    }
}
