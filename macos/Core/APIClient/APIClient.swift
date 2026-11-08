import Foundation

actor APIClient {
    static let supportedSchemaVersion = 1

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func health(token: String?) async throws -> HealthResponse {
        var request = try makeRequest(path: "/api/v1/health", queryItems: [])
        applyToken(token, to: &request)
        let (data, response) = try await data(for: request)
        try validate(response: response, data: data)
        return try Self.decode(HealthResponse.self, from: data)
    }

    func calendar(season: Int, token: String?) async throws -> APIEnvelope<[Meeting]> {
        try await envelope(
            [Meeting].self,
            path: "/api/v1/calendar",
            queryItems: [URLQueryItem(name: "season", value: String(season))],
            token: token
        )
    }

    func nextMeeting(season: Int, token: String?) async throws -> APIEnvelope<Meeting?> {
        try await envelope(
            Meeting?.self,
            path: "/api/v1/meetings/next",
            queryItems: [URLQueryItem(name: "season", value: String(season))],
            token: token
        )
    }

    func sessionResults(sessionId: String, token: String?) async throws -> APIEnvelope<[SessionResult]> {
        try await envelope(
            [SessionResult].self,
            path: "/api/v1/sessions/\(sessionId)/results",
            queryItems: [],
            token: token
        )
    }

    func driverStandings(season: Int, token: String?) async throws -> APIEnvelope<[DriverStanding]> {
        try await envelope(
            [DriverStanding].self,
            path: "/api/v1/standings/drivers",
            queryItems: [URLQueryItem(name: "season", value: String(season))],
            token: token
        )
    }

    func constructorStandings(season: Int, token: String?) async throws -> APIEnvelope<[ConstructorStanding]> {
        try await envelope(
            [ConstructorStanding].self,
            path: "/api/v1/standings/constructors",
            queryItems: [URLQueryItem(name: "season", value: String(season))],
            token: token
        )
    }

    func refresh(target: ManualRefreshTarget, season: Int, sessionId: String?, token: String?) async throws -> DataRefreshEvent {
        var request = try makeRequest(path: "/api/v1/refresh", queryItems: [])
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RefreshRequest(season: season, target: target, sessionId: sessionId))
        applyToken(token, to: &request)
        let (data, response) = try await data(for: request)
        try validate(response: response, data: data)
        return try Self.decode(DataRefreshEvent.self, from: data)
    }


    func sessionAnalysis(sessionId: String, driverId: String, lap: Int?, token: String?) async throws -> APIEnvelope<SessionAnalysis> {
        try await envelope(SessionAnalysis.self, path: "/api/v1/sessions/\(sessionId)/drivers/\(driverId)/analysis",
            queryItems: lap.map { [URLQueryItem(name: "lap", value: String($0))] } ?? [], token: token)
    }

    func seasonAnalysis(kind: String, id: String, season: Int, token: String?) async throws -> APIEnvelope<SeasonAnalysis> {
        try await envelope(SeasonAnalysis.self, path: "/api/v1/standings/\(kind)/\(id)/analysis",
            queryItems: [URLQueryItem(name: "season", value: String(season))], token: token)
    }

    func mapData(path: String, token: String?) async throws -> Data {
        var request = try makeRequest(path: path, queryItems: [])
        applyToken(token, to: &request)
        let (data, response) = try await data(for: request)
        try validate(response: response, data: data)
        if path.hasPrefix("/api/v1/weather/tiles/"), (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-PitPulse-Stale") == "true" {
            throw APIClientError.transport("雷达瓦片已过期，请稍后重试")
        }
        return data
    }

    func liveStream(
        token: String?,
        series: String = "f1",
        onConnected: @escaping @MainActor @Sendable () async -> Void = {},
        onSnapshot: @escaping @MainActor @Sendable (LiveSnapshot) async -> Void,
        onDataRefresh: @escaping @MainActor @Sendable (DataRefreshEvent) async -> Void = { _ in }
    ) async throws {
        var request = try makeRequest(
            path: "/api/v1/live/stream",
            queryItems: [URLQueryItem(name: "series", value: series)]
        )
        request.timeoutInterval = 60
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        applyToken(token, to: &request)
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw APIClientError.timeout
        } catch let error as URLError {
            throw APIClientError.transport(error.localizedDescription)
        } catch {
            throw APIClientError.transport(error.localizedDescription)
        }
        try validate(response: response, data: Data())
        await onConnected()

        var parser = SSEParser()
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                for event in parser.append(byte) {
                    if event.name == "snapshot" {
                        await onSnapshot(try Self.decode(LiveSnapshot.self, from: Data(event.data.utf8)))
                    } else if event.name == "dataRefresh" {
                        await onDataRefresh(try Self.decode(DataRefreshEvent.self, from: Data(event.data.utf8)))
                    }
                }
            }
            for event in parser.finish() {
                if event.name == "snapshot" {
                    await onSnapshot(try Self.decode(LiveSnapshot.self, from: Data(event.data.utf8)))
                } else if event.name == "dataRefresh" {
                    await onDataRefresh(try Self.decode(DataRefreshEvent.self, from: Data(event.data.utf8)))
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as APIClientError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw APIClientError.timeout
        } catch {
            throw APIClientError.transport(error.localizedDescription)
        }
        throw APIClientError.transport("live stream ended")
    }

    private func envelope<Value: Codable & Sendable>(
        _ type: Value.Type,
        path: String,
        queryItems: [URLQueryItem],
        token: String?
    ) async throws -> APIEnvelope<Value> {
        var request = try makeRequest(path: path, queryItems: queryItems)
        applyToken(token, to: &request)
        let (data, response) = try await data(for: request)
        try validate(response: response, data: data)
        let decoded = try Self.decode(APIEnvelope<Value>.self, from: data)
        guard decoded.meta.schemaVersion == Self.supportedSchemaVersion else {
            throw APIClientError.incompatibleSchema(
                found: decoded.meta.schemaVersion,
                expected: Self.supportedSchemaVersion
            )
        }
        return decoded
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidServerAddress(baseURL.absoluteString)
        }
        let basePath = baseURL.path == "/" ? "" : baseURL.path
        components.path = basePath + path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw APIClientError.invalidServerAddress(baseURL.absoluteString)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("PitPulse macOS/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func applyToken(_ token: String?, to request: inout URLRequest) {
        guard let token, !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw APIClientError.timeout
        } catch let error as URLError {
            throw APIClientError.transport(error.localizedDescription)
        } catch {
            throw APIClientError.transport(error.localizedDescription)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw APIClientError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Self.parseRetryAfter)
            throw APIClientError.rateLimited(retryAfter: retryAfter)
        case 500..<600:
            throw APIClientError.server(status: http.statusCode)
        default:
            _ = data
            throw APIClientError.server(status: http.statusCode)
        }
    }

    private static func parseRetryAfter(_ value: String) -> Date? {
        if let seconds = TimeInterval(value), seconds >= 0 {
            return Date().addingTimeInterval(seconds)
        }
        if let date = RFC3339.parse(value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
        return formatter.date(from: value)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = RFC3339.parse(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid RFC 3339 date: \(value)"
                )
            }
            return date
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIClientError.decoding(String(describing: error))
        }
    }
}
