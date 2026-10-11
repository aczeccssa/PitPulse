// Standalone checks use production models, MapStore and RadioPlayer without starting the App.
import Foundation
import SwiftUI

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
        let decoder = JSONDecoder()
        let old = try decoder.decode(LiveSnapshot.self, from: Data(#"{"schemaVersion":1,"stateVersion":1,"sourceStatus":"connected","sourceMode":"live","drivers":[{"number":"44"}]}"#.utf8))
        precondition(old.weather == nil && old.teamRadio == nil && old.drivers[0].location == nil)
        let driver = try decoder.decode(LiveDriver.self, from: Data(#"{"number":"44","telemetry":{"utc":"2026-10-10T10:00:00Z","speed":300},"location":{"x":100,"y":200,"utc":"2026-10-10T10:00:05Z"}}"#.utf8))
        let now = RFC3339.parse("2026-10-10T10:00:12Z")!
        precondition(!LiveFreshness.isFresh(driver.telemetry?.utc, now: now))
        precondition(LiveFreshness.isFresh(driver.location?.utc, now: now))
        precondition(driver.location?.longitude == nil)
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
        mapModel.response = { path in
            if path == "/api/v1/maps/config" { return Data(#"{"data":{"publicToken":"pk.test"}}"#.utf8) }
            if path.contains("2026:17") {
                await withCheckedContinuation { continuation in DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { continuation.resume() } }
                throw URLError(.timedOut)
            }
            return Data(#"{"data":{"geometry":null,"layoutVerified":false}}"#.utf8)
        }
        let newer = try decoder.decode(Meeting.self, from: Data(#"{"id":"2026:18","season":2026,"name":"Austin","country":"USA","location":"Austin","startDate":"2026-10-23T00:00:00Z","endDate":"2026-10-25T00:00:00Z","status":"scheduled","sessions":[]}"#.utf8))
        let first = Task { await maps.load(model: mapModel, meeting: meeting) }
        try await Task.sleep(for: .milliseconds(20))
        await maps.load(model: mapModel, meeting: newer)
        await first.value
        precondition(maps.error == nil && maps.publicToken == "pk.test" && maps.webView == nil)
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
