// Standalone checks use production models, MapStore and RadioPlayer without starting the App.
import Foundation
import SwiftUI

final class RefreshURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class AppModel: ObservableObject {
    var requests = 0
    var serverAddress = "https://example.invalid"
    var response: ((String) async throws -> Data)?
    func mapData(path: String) async throws -> Data {
        requests += 1
        if let response { return try await response(path) }
        try await Task.sleep(for: .milliseconds(400))
        return Data()
    }
}
enum MotorsportAsset {
    static func abbreviation(_ value: String) -> String { value }
}

@main
struct LiveMapCheck {
    @MainActor
    static func main() async throws {
        let refreshConfiguration = URLSessionConfiguration.ephemeral
        refreshConfiguration.protocolClasses = [RefreshURLProtocol.self]
        let refreshSession = URLSession(configuration: refreshConfiguration)
        RefreshURLProtocol.handler = { request in
            precondition(request.httpMethod == "POST")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer mock-token")
            let bodyData: Data
            if let body = request.httpBody {
                bodyData = body
            } else {
                let stream = request.httpBodyStream!
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 1024)
                var data = Data()
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }
                    data.append(contentsOf: bytes.prefix(count))
                }
                bodyData = data
            }
            let body = try! JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
            precondition(body["season"] as? Int == 2026 && body["target"] as? String == "results")
            precondition(body["sessionId"] as? String == "2026:17:race")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"target":"results","season":2026,"sessionId":"2026:17:race","status":"completed","updatedAt":"2026-10-12T00:00:00Z","retryAfter":null}"#.utf8))
        }
        let refreshClient = APIClient(baseURL: URL(string: "https://pitpulse.example")!, session: refreshSession)
        let refreshEvent = try await refreshClient.refresh(target: .results, season: 2026, sessionId: "2026:17:race", token: "mock-token")
        precondition(refreshEvent.status == .completed && refreshEvent.sessionId == "2026:17:race")
        refreshSession.invalidateAndCancel()
        RefreshURLProtocol.handler = nil

        let decoder = JSONDecoder()
        let old = try decoder.decode(LiveSnapshot.self, from: Data(#"{"schemaVersion":1,"stateVersion":1,"sourceStatus":"connected","sourceMode":"live","drivers":[{"number":"44"}]}"#.utf8))
        precondition(old.weather == nil && old.teamRadio == nil && old.drivers[0].location == nil)
        let driver = try decoder.decode(LiveDriver.self, from: Data(#"{"number":"44","telemetry":{"utc":"2026-10-10T10:00:00Z","speed":300},"location":{"x":100,"y":200,"utc":"2026-10-10T10:00:05Z"}}"#.utf8))
        let now = RFC3339.parse("2026-10-10T10:00:12Z")!
        precondition(!LiveFreshness.isFresh(driver.telemetry?.utc, now: now))
        precondition(LiveFreshness.isFresh(driver.location?.utc, now: now))
        precondition(driver.location?.longitude == nil)
        let delayed = try decoder.decode(LiveDriver.self, from: Data(#"{"number":"44","location":{"x":100,"y":200,"utc":"2026-10-10T10:00:00Z","receivedAt":"2026-10-10T10:00:11Z"}}"#.utf8))
        precondition(LiveFreshness.age(delayed.location?.utc, now: now) == 12)
        precondition(LiveFreshness.isFresh(delayed.location?.receivedAt, now: now))
        precondition(!LiveFreshness.isFresh(delayed.location?.receivedAt, now: now.addingTimeInterval(11)))
        let redBull = try decoder.decode(LiveDriver.self, from: Data(#"{"number":"3","team":"Red Bull Racing"}"#.utf8))
        let mercedes = try decoder.decode(LiveDriver.self, from: Data(#"{"number":"12","team":"Mercedes"}"#.utf8))
        precondition(redBull.teamColorHex == "#3671C6" && mercedes.teamColorHex == "#27F4D2")
        let rc = try decoder.decode(LiveRaceControlMessage.self, from: Data(#"{"id":"7","utc":"2026-10-10T10:00:00Z","Message":"Flag","driverNumber":44,"lap":5,"sector":2}"#.utf8))
        precondition(rc.concernsDriver("44") && !rc.concernsDriver("4"))
        let textMessage = try decoder.decode(LiveRaceControlMessage.self, from: Data(#"{"Message":"INCIDENT INVOLVING CAR 44 AND CAR 1 NOTED"}"#.utf8))
        precondition(textMessage.concernsDriver("44") && textMessage.concernsDriver("1") && !textMessage.concernsDriver("4") && !textMessage.concernsDriver(nil))
        precondition(rc.id == "7" && rc.driverNumber == "44" && rc.lap == 5 && rc.sector == 2)
        let legacy = try decoder.decode(LiveRaceControlMessage.self, from: Data(#"{"Id":"7","Utc":"2026-10-10T10:00:00Z","RacingNumber":"44"}"#.utf8))
        precondition(legacy.id == "7" && legacy.driverNumber == "44")
        decoder.dateDecodingStrategy = .iso8601
        let meeting = try decoder.decode(Meeting.self, from: Data(#"{"id":"2026:17","season":2026,"round":17,"name":"Singapore","country":"Singapore","location":"Marina Bay","startDate":"2026-10-09T00:00:00Z","endDate":"2026-10-11T00:00:00Z","status":"scheduled","sessions":[]}"#.utf8))
        precondition(meeting.circuit == nil)
        let model = AppModel(), player = RadioPlayer()
        player.toggle(LiveRadio(id: "a", utc: "", driverNumber: "44"), sessionID: "one", model: model)
        try await Task.sleep(for: .milliseconds(20))
        player.toggle(LiveRadio(id: "b", utc: "", driverNumber: "1"), sessionID: "one", model: model)
        try await Task.sleep(for: .milliseconds(20))
        precondition(player.loadingID == "b")
        player.stop()
        try await Task.sleep(for: .milliseconds(450))
        precondition(model.requests == 2 && player.loadingID == nil && player.playingID == nil && player.error == nil && player.progress == 0)
        let maps = MapStore(), mapModel = AppModel()
        var oldGeometryStarted = false
        mapModel.response = { path in
            if path == "/api/v1/maps/config" { return Data(#"{"data":{"publicToken":"pk.test"}}"#.utf8) }
            if path.contains("2026:17") {
                oldGeometryStarted = true
                await withCheckedContinuation { continuation in DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { continuation.resume() } }
                throw URLError(.timedOut)
            }
            return Data(#"{"data":{"geometry":null,"layoutVerified":false}}"#.utf8)
        }
        let newer = try decoder.decode(Meeting.self, from: Data(#"{"id":"2026:18","season":2026,"name":"Austin","country":"USA","location":"Austin","startDate":"2026-10-23T00:00:00Z","endDate":"2026-10-25T00:00:00Z","status":"scheduled","sessions":[]}"#.utf8))
        let first = Task { await maps.load(model: mapModel, meeting: meeting) }
        while !oldGeometryStarted { await Task.yield() }
        await maps.load(model: mapModel, meeting: newer)
        await first.value
        precondition(maps.error == nil && maps.publicToken == "pk.test" && maps.webView == nil,
                     "stale geometry response changed map state: error=\(String(describing: maps.error)), token=\(maps.publicToken ?? "nil"), webView=\(maps.webView != nil)")
        let requestsBeforeHide = mapModel.requests
        maps.release(preserveCamera: true)
        await maps.load(model: mapModel, meeting: newer)
        precondition(maps.publicToken == "pk.test" && mapModel.requests == requestsBeforeHide + 2)
        maps.release()
        mapModel.response = { _ in
            await withCheckedContinuation { continuation in DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { continuation.resume() } }
            return Data(#"{"data":{"publicToken":"pk.test"}}"#.utf8)
        }
        let pending = Task { await maps.load(model: mapModel, meeting: nil) }
        try await Task.sleep(for: .milliseconds(20)); maps.release()
        await pending.value
        precondition(maps.publicToken == nil && maps.webView == nil && maps.model == nil)
        print("Live/map compatibility, freshness, RC filtering, Radio cancellation and MapStore stale-response/release checks passed")
    }
}
