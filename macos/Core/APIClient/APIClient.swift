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
        return RFC3339.parse(value)
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
