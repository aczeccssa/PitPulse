import AppKit
import Combine
import NookApp
import OSLog
import SwiftUI
import SharedData

@MainActor
final class LiveIslandActions: ObservableObject {
    private enum Keys {
        static let tire = "liveIslandShowTire"
        static let energy = "liveIslandShowEnergy"
    }

    @Published var snapshot = LiveSnapshot.disconnected()
    @Published var presentation = "hidden"
    @Published var mode = "Telemetry"
    @Published var selectedNumber: String?
    @Published var showRadar = false
    @Published var messagePage = "Race Control"
    @Published var messageFilter = "all"
    @Published var messagesExpanded = false
    @Published var wecClass: String?
    @Published var showTire: Bool {
        didSet { defaults.set(showTire, forKey: Keys.tire) }
    }
    @Published var showEnergy: Bool {
        didSet { defaults.set(showEnergy, forKey: Keys.energy) }
    }
    let map = MapStore()
    let radio = RadioPlayer()
    var expand: (() -> Void)?
    var collapse: (() -> Void)?
    var hide: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showTire = defaults.object(forKey: Keys.tire) as? Bool ?? true
        showEnergy = defaults.object(forKey: Keys.energy) as? Bool ?? true
    }
}

