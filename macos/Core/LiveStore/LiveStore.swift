import Foundation
import OSLog

@MainActor
final class LiveStore: ObservableObject {
    @Published private(set) var snapshot = LiveSnapshot.disconnected()
    @Published private(set) var isConnecting = false
    @Published private(set) var requiresCredentials = false
    var onDataRefresh: ((DataRefreshEvent) -> Void)?
    var onStreamConnected: (() -> Void)?

    private let logger = Logger(subsystem: "com.pitpulse.F1Companion", category: "LiveStore")
    private var generation = 0
    private var connectionGeneration = 0
    private var baselineConnection: Int?
    private var streamTask: Task<Void, Never>?
    private let retryDelays: [TimeInterval]
    private let session: URLSession

    init(session: URLSession = .shared, retryDelays: [TimeInterval] = [5, 15, 30, 60, 300]) {
        self.session = session
        self.retryDelays = retryDelays.isEmpty ? [5, 15, 30, 60, 300] : retryDelays
    }

    func start(serverURL: URL, token: String?, series: LiveSeries = .f1) {
        let current = beginConnection()
        streamTask = Task { [weak self] in
            await self?.run(
                serverURL: serverURL,
                token: token,
                series: series,
                generation: current
            )
        }
    }

    func stop(reason: String = "disconnected") {
        generation += 1
        logger.notice("connectionReset generation=\(self.generation)")
        streamTask?.cancel()
        streamTask = nil
        isConnecting = false
        requiresCredentials = false
        snapshot = .disconnected(reason: reason)
    }

    @discardableResult
    func beginConnection() -> Int {
        generation += 1
        logger.notice("connectionReset generation=\(self.generation)")
        streamTask?.cancel()
        streamTask = nil
        isConnecting = true
        requiresCredentials = false
        connectionGeneration = 0
        baselineConnection = nil
        snapshot = .disconnected(reason: "connecting")
        return generation
    }

    @discardableResult
    func accept(
        _ incoming: LiveSnapshot,
        generation incomingGeneration: Int,
        connection incomingConnection: Int = 0
    ) -> Bool {
        guard incomingGeneration == generation else {
            logger.debug("snapshotRejected cause=generation incoming=\(incomingGeneration) current=\(self.generation)")
            return false
        }
        if baselineConnection == incomingConnection && incoming.stateVersion <= snapshot.stateVersion {
            logger.debug("snapshotRejected cause=version incoming=\(incoming.stateVersion) current=\(self.snapshot.stateVersion)")
            return false
        }
        logger.info("snapshotAccepted generation=\(incomingGeneration) connection=\(incomingConnection) version=\(incoming.stateVersion) status=\(incoming.sourceStatus.rawValue, privacy: .public) mode=\(incoming.sourceMode.rawValue, privacy: .public) drivers=\(incoming.drivers.count)")
        snapshot = incoming
        baselineConnection = incomingConnection
        isConnecting = false
        requiresCredentials = false
        return true
    }

    func beginStream(generation incomingGeneration: Int) -> Int? {
        guard incomingGeneration == generation else { return nil }
        connectionGeneration += 1
        baselineConnection = nil
        return connectionGeneration
    }

    private func run(
        serverURL: URL,
        token: String?,
        series: LiveSeries,
        generation current: Int
    ) async {
        let client = APIClient(baseURL: serverURL, session: session)
        var attempts = 0
        while current == generation && !Task.isCancelled {
            isConnecting = true
            guard let connection = beginStream(generation: current) else { return }
            do {
                try await client.liveStream(token: token, series: series.rawValue, onConnected: { [weak self] in
                    if connection > 1 { self?.onStreamConnected?() }
                }, onSnapshot: { [weak self] incoming in
                    guard let self else { return }
                    self.accept(incoming, generation: current, connection: connection)
                }, onDataRefresh: { [weak self] event in
                    self?.onDataRefresh?(event)
                })
                throw APIClientError.transport("live stream ended")
            } catch is CancellationError {
                return
            } catch let error as APIClientError where error == .unauthorized {
                guard current == generation else { return }
                logger.error("streamDisconnected cause=unauthorized")
                snapshot = .disconnected(reason: "unauthorized")
                isConnecting = false
                requiresCredentials = true
                return
            } catch let error as APIClientError {
                guard current == generation else { return }
                logger.error("streamDisconnected cause=server_unavailable")
                snapshot = .disconnected(reason: "server_unavailable")
                isConnecting = false
                let delay: TimeInterval
                if case let .rateLimited(retryAfter) = error, let retryAfter {
                    delay = max(retryAfter.timeIntervalSinceNow, 1)
                } else {
                    delay = retryDelays[min(attempts, retryDelays.count - 1)]
                    attempts += 1
                }
                logger.notice("retryScheduled seconds=\(delay)")
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            } catch {
                guard current == generation else { return }
                logger.error("streamDisconnected cause=server_unavailable")
                snapshot = .disconnected(reason: "server_unavailable")
                isConnecting = false
                let delay = retryDelays[min(attempts, retryDelays.count - 1)]
                attempts += 1
                logger.notice("retryScheduled seconds=\(delay)")
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
            guard current == generation else { return }
            snapshot = .disconnected(reason: "reconnecting")
            isConnecting = true
        }
    }
}
