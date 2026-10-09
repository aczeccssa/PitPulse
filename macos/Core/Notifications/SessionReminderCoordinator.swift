import CryptoKit
import Foundation
import UserNotifications

struct SessionReminder: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
}

enum ReminderAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

@MainActor
protocol SessionReminderCenter: AnyObject {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func schedule(_ reminder: SessionReminder) async throws
    func removePending(identifiers: [String]) async
    func removeAllPending() async
}

@MainActor
final class UserNotificationReminderCenter: SessionReminderCenter {
    private let center = UNUserNotificationCenter.current()

    func authorization() async -> ReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorized, .provisional: .authorized
        default: .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func pendingIdentifiers() async -> [String] {
        (await center.pendingNotificationRequests()).map(\.identifier)
    }

    func schedule(_ reminder: SessionReminder) async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        components.calendar = calendar
        components.timeZone = calendar.timeZone

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: reminder.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func removePending(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeAllPending() async {
        let identifiers = await pendingIdentifiers().filter { $0.hasPrefix("pitpulse.") }
        await removePending(identifiers: identifiers)
    }
}

enum SessionReminderPlanner {
    static let allowedMinutes = [5, 15, 30, 60]

    static func reminders(
        meetings: [Meeting],
        serverIdentity: String,
        season: Int,
        minutesBefore: Int,
        now: Date
    ) -> [SessionReminder] {
        guard allowedMinutes.contains(minutesBefore) else { return [] }
        return meetings
            .filter { $0.season == season && $0.status == .scheduled }
            .flatMap { meeting in
                meeting.sessions.compactMap { session in
                    guard session.status == .scheduled else { return nil }
                    let fireDate = session.startTime.addingTimeInterval(-Double(minutesBefore * 60))
                    guard fireDate > now else { return nil }
                    let key = "\(serverIdentity)|\(season)|\(session.id)|\(minutesBefore)"
                    let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
                    return SessionReminder(
                        identifier: "pitpulse.\(digest)",
                        title: "\(meeting.country) · \(session.sessionType.displayName)",
                        body: "\(meeting.name) 将于 \(session.startTime.formatted(date: .omitted, time: .shortened)) 开始。",
                        fireDate: fireDate
                    )
                }
            }
            .sorted { $0.fireDate < $1.fireDate }
    }
}
