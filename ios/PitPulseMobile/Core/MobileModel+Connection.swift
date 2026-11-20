import Foundation
import SharedData

extension MobileModel {
    func saveConnection(address: String, token: String) -> String? {
        guard let address = try? ServerAddress(rawValue: address) else { return "Enter a valid server address." }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            do { try keychain.save(token: token, for: address.url) }
            catch { return Self.message(for: error) }
        }
        serverText = address.url.absoluteString
        credentialRevision += 1
        invalidateCalendar()
        if liveStarted { startLive() }
        return nil
    }
    func saveToken(_ token: String) -> String? {
        guard let serverURL else { return "Enter a valid server address first." }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? keychain.deleteToken(for: serverURL)
            return nil
        }
        do {
            try keychain.save(token: trimmed, for: serverURL)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
    func testConnection() async {
        guard let serverURL else {
            healthText = "Invalid server address"
            return
        }
        healthText = "Connecting…"
        do {
            let client = APIClient(baseURL: serverURL)
            let response = try await client.health(token: currentToken)
            async let calendar = client.calendar(season: season, token: currentToken)
            async let drivers = client.driverStandings(season: season, token: currentToken)
            async let teams = client.constructorStandings(season: season, token: currentToken)
            let counts = try await (calendar.data.count, drivers.data.count, teams.data.count)
            healthText = "Service \(response.status) · F1: \(counts.0) races / \(counts.1) drivers / \(counts.2) teams"
            if counts.0 == 0 || counts.1 == 0 || counts.2 == 0 {
                healthText! += "\nThe server is reachable. F1 data is still incomplete."
            }
        } catch {
            healthText = Self.message(for: error)
        }
    }
    static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
