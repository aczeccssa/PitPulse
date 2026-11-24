import CryptoKit
import Foundation
import UserNotifications

public struct SessionReminder: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String
    public let fireDate: Date
}

public enum ReminderAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

@MainActor
public protocol SessionReminderCenter: AnyObject {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func schedule(_ reminder: SessionReminder) async throws
    func removePending(identifiers: [String]) async
}

@MainActor
public final class UserNotificationReminderCenter: SessionReminderCenter {
    private let center = UNUserNotificationCenter.current()

    public init() {
        center.delegate = Self.presentationDelegate
    }

    private static let presentationDelegate = ReminderPresentationDelegate()

    public func authorization() async -> ReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorized, .provisional: .authorized
        default: .denied
        }
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    public func pendingIdentifiers() async -> [String] {
        (await center.pendingNotificationRequests()).map(\.identifier)
    }

    public func schedule(_ reminder: SessionReminder) async throws {
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

    public func removePending(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

private final class ReminderPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.identifier.hasPrefix("pitpulse.") ? [.banner, .sound] : []
    }
}

@MainActor
public final class SessionReminderCoordinator {
    private let center: any SessionReminderCenter
    private var pendingSync: Task<Result<Void, any Error>, Never>?

    public init(center: any SessionReminderCenter) {
        self.center = center
    }

    public func authorize() async throws -> Bool {
        switch await center.authorization() {
        case .authorized: true
        case .denied: false
        case .notDetermined: try await center.requestAuthorization()
        }
    }

    public func authorization() async -> ReminderAuthorization {
        await center.authorization()
    }

    public func sync(_ reminders: [SessionReminder]) async throws {
        let previous = pendingSync
        let task = Task { [center] in
            _ = await previous?.value
            let desired = Set(reminders.map(\.identifier))
            let obsolete = await center.pendingIdentifiers().filter {
                $0.hasPrefix("pitpulse.") && !desired.contains($0)
            }
            if !obsolete.isEmpty { await center.removePending(identifiers: obsolete) }
            do {
                for reminder in reminders where reminder.fireDate > .now {
                    try await center.schedule(reminder)
                }
                return Result<Void, any Error>.success(())
            } catch {
                return .failure(error)
            }
        }
        pendingSync = task
        try await task.value.get()
    }
}

public enum SessionReminderPlanner {
    public static let defaultMinutes = 60
    public static let allowedMinutes = [5, 15, 30, 60]

    public static func reminders(
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
