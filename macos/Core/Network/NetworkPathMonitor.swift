import Network

@MainActor
protocol NetworkPathMonitoring: AnyObject {
    func start(_ receive: @escaping @Sendable (Bool) -> Void)
    func cancel()
}

@MainActor
final class SystemNetworkPathMonitor: NetworkPathMonitoring {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.pitpulse.network-path")

    func start(_ receive: @escaping @Sendable (Bool) -> Void) {
        monitor.pathUpdateHandler = { path in receive(path.status == .satisfied) }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}
