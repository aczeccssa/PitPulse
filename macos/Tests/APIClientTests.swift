import XCTest
@testable import SharedData
@testable import PitPulseDesktop

final class APIClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }


    func testAnalysisEndpointsKeepMissingFieldsAndUseAuthenticatedServer() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertEqual(request.timeoutInterval, 15)
            let body: String
            if request.url?.path.contains("sessions") == true {
                XCTAssertTrue(request.url?.query?.contains("lap=19") == true)
                body = #"{"data":{"laps":[{"lapNumber":19,"lapDuration":106.017,"durationSector1":null}],"stints":[],"pit":[],"positions":[],"weather":[],"raceControl":[],"grid":[],"location":[],"carData":[],"warnings":[],"selectedLap":19},"meta":{"schemaVersion":1,"revision":1,"stale":false,"quality":"partial"}}"#
            } else {
                XCTAssertEqual(request.url?.path, "/api/v1/standings/drivers/antonelli/analysis")
                body = #"{"data":{"rounds":[{"round":1,"entries":[{"points":null}]}],"warnings":[]},"meta":{"schemaVersion":1,"revision":1,"stale":false,"quality":"partial"}}"#
            }
            return Self.response(for: request, body: body)
        }
        let client = APIClient(baseURL: URL(string: "http://localhost:38701")!, session: Self.session())
        let timing = try await client.sessionAnalysis(sessionId: "2026:17:sprint", driverId: "antonelli", lap: 19, token: "secret")
        XCTAssertNil(timing.data.laps[0].durationSector1)
        XCTAssertEqual(timing.data.selectedLap, 19)
        let history = try await client.seasonAnalysis(kind: "drivers", id: "antonelli", season: 2026, token: "secret")
        XCTAssertNil(history.data.rounds[0].points)
    }

    func testCalendarDecodesEnvelopeWithFractionalUTCTimestamp() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertEqual(request.url?.path, "/api/v1/calendar")
            XCTAssertTrue(request.url?.query?.contains("season=2026") == true)
            return Self.response(for: request, body: Self.calendarPayload)
        }

        let client = APIClient(baseURL: URL(string: "http://localhost:38701")!, session: Self.session())
        let response = try await client.calendar(season: 2026, token: "secret")

        XCTAssertEqual(response.meta.schemaVersion, 1)
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data[0].countryCode, "AU")
        XCTAssertEqual(response.data[0].sessions[0].sessionType, .fp1)
        XCTAssertEqual(response.data[0].sessions[0].startTime, TestData.date("2026-03-06T01:30:00.125Z"))
    }

    func testNextMeetingDecodesNullWithoutInventingMeeting() async throws {
        URLProtocolStub.handler = { request in
            let body = #"{"data":null,"meta":{"schemaVersion":1,"revision":0,"stale":false,"quality":"pending"}}"#
            return Self.response(for: request, body: body)
        }
        let client = APIClient(baseURL: URL(string: "https://pitpulse.example")!, session: Self.session())
        let response = try await client.nextMeeting(season: 2026, token: nil)
        XCTAssertNil(response.data)
    }

    func testResultsAndStandingsEndpointsDecodeRealPayloadShapes() async throws {
        URLProtocolStub.handler = { request in
            let body: String
            let requestPath = request.url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath
            }
            switch requestPath {
            case "/api/v1/sessions/2026:1:race/results":
                body = #"{"data":[{"sessionId":"2026:1:race","position":1,"classification":"classified","driverId":"norris","driverName":"Lando Norris","constructorId":"mclaren","team":"McLaren","bestLap":"1:20.000","source":"jolpica-alpha","sourceUpdatedAt":null,"fetchedAt":"2026-03-08T00:00:00Z","revision":2,"quality":"provisional"}],"meta":{"schemaVersion":1,"revision":2,"stale":false,"quality":"provisional","source":"jolpica-alpha","fetchedAt":"2026-03-08T00:00:00Z","sourceUpdatedAt":null}}"#
            case "/api/v1/standings/drivers":
                XCTAssertTrue(request.url?.query?.contains("season=2026") == true)
                body = #"{"data":[{"season":2026,"position":1,"driverId":"norris","driverName":"Lando Norris","constructor":"McLaren","constructorIds":["mclaren"],"points":25.0,"wins":1,"source":"jolpica-ergast","fetchedAt":"2026-03-08T00:00:00Z","revision":1}],"meta":{"schemaVersion":1,"revision":1,"stale":false,"quality":"provisional"}}"#
            default:
                XCTAssertEqual(request.url?.path, "/api/v1/standings/constructors")
                body = #"{"data":[{"season":2026,"position":1,"constructorId":"mclaren","constructorName":"McLaren","points":43.0,"wins":1,"source":"jolpica-ergast","fetchedAt":"2026-03-08T00:00:00Z","revision":1}],"meta":{"schemaVersion":1,"revision":1,"stale":false,"quality":"provisional"}}"#
            }
            return Self.response(for: request, body: body)
        }

        let client = APIClient(baseURL: URL(string: "https://pitpulse.example")!, session: Self.session())
        let results = try await client.sessionResults(sessionId: "2026:1:race", token: nil)
        let drivers = try await client.driverStandings(season: 2026, token: nil)
        let constructors = try await client.constructorStandings(season: 2026, token: nil)
        XCTAssertEqual(results.data.first?.bestLap, "1:20.000")
        XCTAssertNil(results.data.first?.q1)
        XCTAssertEqual(drivers.data.first?.constructorIds, ["mclaren"])
        XCTAssertEqual(constructors.data.first?.points, 43)
    }

    func testUnauthorizedIsNotRetriedAsTransportFailure() async {
        var requestCount = 0
        URLProtocolStub.handler = { request in
            requestCount += 1
            return Self.response(for: request, status: 401, body: #"{"error":{"code":"unauthorized"}}"#)
        }
        let client = APIClient(baseURL: URL(string: "https://pitpulse.example")!, session: Self.session())
        do {
            _ = try await client.calendar(season: 2026, token: "wrong")
            XCTFail("Expected unauthorized")
        } catch {
            XCTAssertEqual(error as? APIClientError, .unauthorized)
            XCTAssertEqual(requestCount, 1)
        }
    }

    func testRateLimitKeepsRetryAfter() async {
        URLProtocolStub.handler = { request in
            Self.response(for: request, status: 429, headers: ["Retry-After": "2"], body: "{}")
        }
        let client = APIClient(baseURL: URL(string: "https://pitpulse.example")!, session: Self.session())
        do {
            _ = try await client.calendar(season: 2026, token: nil)
            XCTFail("Expected rate limit")
        } catch let error as APIClientError {
            guard case let .rateLimited(retryAfter) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertNotNil(retryAfter)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testManualRefreshPostsCurrentTargetAndDecodesResult() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/refresh")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try XCTUnwrap(request.testBodyData)
            let value = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(value["season"] as? Int, 2026)
            XCTAssertEqual(value["target"] as? String, "results")
            XCTAssertEqual(value["sessionId"] as? String, "2026:1:race")
            return Self.response(for: request, body: #"{"target":"results","season":2026,"sessionId":"2026:1:race","status":"completed","updatedAt":"2026-10-12T00:00:00Z"}"#)
        }
        let client = APIClient(baseURL: URL(string: "https://pitpulse.example")!, session: Self.session())
        let event = try await client.refresh(target: .results, season: 2026, sessionId: "2026:1:race", token: "secret")
        XCTAssertEqual(event.status, .completed)
        XCTAssertEqual(event.target, .results)
        XCTAssertEqual(event.sessionId, "2026:1:race")
    }

    func testRateLimitParsesHTTPDateRetryAfter() async {
        URLProtocolStub.handler = { request in
            Self.response(for: request, status: 429, headers: ["Retry-After": "Wed, 02 Jan 2030 03:04:05 GMT"], body: "{}")
        }
        let client = APIClient(baseURL: URL(string: "https://pitpulse.example")!, session: Self.session())
        do {
            _ = try await client.calendar(season: 2026, token: nil)
            XCTFail("Expected rate limit")
        } catch let error as APIClientError {
            guard case let .rateLimited(retryAfter) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            var expectedComponents = DateComponents()
            expectedComponents.timeZone = TimeZone(secondsFromGMT: 0)
            expectedComponents.year = 2030
            expectedComponents.month = 1
            expectedComponents.day = 2
            expectedComponents.hour = 3
            expectedComponents.minute = 4
            expectedComponents.second = 5
            XCTAssertEqual(retryAfter, Calendar(identifier: .gregorian).date(from: expectedComponents))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServerAndTimeoutErrorsAreDistinct() async {
        URLProtocolStub.handler = { request in
            Self.response(for: request, status: 503, body: "{}")
        }
        let serverClient = APIClient(baseURL: URL(string: "https://pitpulse.example")!, session: Self.session())
        do {
            _ = try await serverClient.calendar(season: 2026, token: nil)
            XCTFail("Expected server error")
        } catch {
            XCTAssertEqual(error as? APIClientError, .server(status: 503))
        }

        URLProtocolStub.handler = { _ in throw URLError(.timedOut) }
        let timeoutClient = APIClient(baseURL: URL(string: "https://pitpulse.example")!, session: Self.session())
        do {
            _ = try await timeoutClient.calendar(season: 2026, token: nil)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? APIClientError, .timeout)
        }
    }

    func testIncompatibleSchemaIsRejected() async {
        let body = #"{"data":[],"meta":{"schemaVersion":2,"revision":1,"stale":false,"quality":"provisional"}}"#
        URLProtocolStub.handler = { request in Self.response(for: request, body: body) }
        let client = APIClient(baseURL: URL(string: "https://pitpulse.example")!, session: Self.session())
        do {
            _ = try await client.calendar(season: 2026, token: nil)
            XCTFail("Expected schema mismatch")
        } catch {
            XCTAssertEqual(error as? APIClientError, .incompatibleSchema(found: 2, expected: 1))
        }
    }

    func testMalformedPayloadIsDecodingError() async {
        URLProtocolStub.handler = { request in Self.response(for: request, body: #"{"data":{}}"#) }
        let client = APIClient(baseURL: URL(string: "https://pitpulse.example")!, session: Self.session())
        do {
            _ = try await client.calendar(season: 2026, token: nil)
            XCTFail("Expected decode error")
        } catch {
            guard case .decoding = error as? APIClientError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private static let calendarPayload = #"""
    {
      "data": [
        {
          "id": "2026:1",
          "season": 2026,
          "round": 1,
          "name": "Australian Grand Prix",
          "country": "Australia",
          "countryCode": "AU",
          "location": "Melbourne",
          "startDate": "2026-03-06T01:30:00Z",
          "endDate": "2026-03-08T04:00:00Z",
          "status": "scheduled",
          "sessions": [
            {
              "id": "2026:1:fp1",
              "meetingId": "2026:1",
              "sessionType": "fp1",
              "startTime": "2026-03-06T01:30:00.125Z",
              "status": "scheduled"
            }
          ],
          "source": "jolpica-alpha",
          "fetchedAt": "2026-03-01T00:00:00.250Z",
          "revision": 1
        }
      ],
      "meta": {
        "schemaVersion": 1,
        "revision": 1,
        "stale": false,
        "quality": "provisional",
        "source": "fixture",
        "fetchedAt": "2026-03-01T00:00:00.500Z"
      }
    }
    """#

    func testMapResourcesStayAuthenticatedAndStaleRadarIsRejected() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            return Self.response(for: request, headers: ["Content-Type":"image/png", "X-PitPulse-Stale":"true"], body: "cached")
        }
        let client = APIClient(baseURL: URL(string: "https://pitpulse.example")!, session: Self.session())
        do {
            _ = try await client.mapData(path: "/api/v1/weather/tiles/radar/1/0/0/0", token: "secret")
            XCTFail("Expected stale radar error")
        } catch let error as APIClientError {
            guard case .transport = error else { return XCTFail("Unexpected error: \(error)") }
        }
        URLProtocolStub.handler = { request in Self.response(for: request, body: "public config") }
        let config = try await client.mapData(path: "/api/v1/maps/config", token: "secret")
        XCTAssertEqual(config, Data("public config".utf8))
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        for request: URLRequest,
        status: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json"],
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return (response, Data(body.utf8))
    }
}
