import Foundation

struct NextSession: Equatable, Sendable {
    let meeting: Meeting
    let session: Session
}

enum CalendarLogic {
    static func nextSession(
        in meetings: [Meeting],
        now: Date,
        calendar: Calendar = .current
    ) -> NextSession? {
        _ = calendar
        return meetings
            .filter { $0.status == .scheduled }
            .flatMap { meeting in
                meeting.sessions
                    .filter { $0.status == .scheduled && $0.startTime >= now }
                    .map { NextSession(meeting: meeting, session: $0) }
            }
            .sorted {
                if $0.session.startTime != $1.session.startTime {
                    return $0.session.startTime < $1.session.startTime
                }
                if $0.session.id != $1.session.id {
                    return $0.session.id < $1.session.id
                }
                return $0.meeting.id < $1.meeting.id
            }
            .first
    }

    static func nextMeeting(in meetings: [Meeting], now: Date) -> Meeting? {
        nextSession(in: meetings, now: now)?.meeting
    }

    static func localDateTime(
        _ date: Date,
        timeZone: TimeZone,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func localDateComponents(
        _ date: Date,
        timeZone: TimeZone,
        calendar: Calendar = .current
    ) -> DateComponents {
        var localized = calendar
        localized.timeZone = timeZone
        return localized.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    static func countdownText(until date: Date, now: Date) -> String {
        let remaining = max(0, date.timeIntervalSince(now))
        if remaining < 60 {
            return "不到 1 分钟"
        }
        let minutes = Int(remaining / 60)
        if minutes < 60 {
            return "\(minutes) 分钟"
        }
        let hours = minutes / 60
        let remainderMinutes = minutes % 60
        if hours < 24 {
            return remainderMinutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(remainderMinutes) 分钟"
        }
        let days = hours / 24
        let remainderHours = hours % 24
        return remainderHours == 0 ? "\(days) 天" : "\(days) 天 \(remainderHours) 小时"
    }
}
