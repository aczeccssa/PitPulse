import Foundation

/// Ten seconds is a minimum hold, not a rotation timer. Each new movement
/// of the focused car renews its hold, so a continuing loss/gain stays in view.
public struct IslandPositionFocus: Sendable {
    public private(set) var driverID: String?
    private var positions: [String: Int] = [:]
    private var pending: [String: Int] = [:]
    private var lastMovementAt: TimeInterval?
    public init() {}
    public mutating func update(positions next: [String: Int], now: TimeInterval) {
        let valid = next.filter { $0.value > 0 }
        let changed = valid.keys.filter { positions[$0] != nil && positions[$0] != valid[$0] }
        for id in changed { pending[id] = positions[id] }
        positions = valid
        pending = pending.filter { valid[$0.key] != nil }
        if driverID == nil || driverID.flatMap({ valid[$0] }) == nil {
            driverID = valid.min { $0.value < $1.value }?.key
            lastMovementAt = nil
        }
        if let driverID, lastMovementAt != nil, changed.contains(driverID) {
            lastMovementAt = now
            // Opponents exchanging places with this car belong to the same event.
            for id in changed { pending.removeValue(forKey: id) }
            return
        }
        guard !pending.isEmpty, lastMovementAt.map({ now - $0 >= 10 }) ?? true else { return }
        // Use the order before the exchange: if A loses its place to B, keep A
        // as the story rather than immediately switching to the overtaking car.
        driverID = pending.min { $0.value < $1.value }?.key
        pending.removeAll()
        lastMovementAt = now
    }
}
