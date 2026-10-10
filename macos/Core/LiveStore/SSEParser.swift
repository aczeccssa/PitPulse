import Foundation

struct SSEEvent: Equatable, Sendable {
    let name: String
    let data: String
}

struct SSEParser {
    private static let maximumLineBytes = 1024 * 1024
    private static let maximumEventBytes = 2 * 1024 * 1024

    private var line = Data()
    private var dataLines: [String] = []
    private var eventName: String?
    private var eventBytes = 0
    private var discardingLine = false
    private var discardingEvent = false
    private var skipNextLineFeed = false

    mutating func append(_ byte: UInt8) -> [SSEEvent] {
        if skipNextLineFeed {
            skipNextLineFeed = false
            if byte == 0x0A { return [] }
        }
        if byte == 0x0D {
            skipNextLineFeed = true
            return finishLine()
        }
        if byte == 0x0A { return finishLine() }
        guard !discardingLine else { return [] }
        line.append(byte)
        if line.count > Self.maximumLineBytes {
            line.removeAll(keepingCapacity: false)
            discardingLine = true
        }
        return []
    }

    mutating func finish() -> [SSEEvent] {
        var events = line.isEmpty ? [] : finishLine()
        if let event = dispatch() { events.append(event) }
        return events
    }

    private mutating func finishLine() -> [SSEEvent] {
        if discardingLine {
            discardingLine = false
            line.removeAll(keepingCapacity: true)
            return []
        }
        guard let text = String(data: line, encoding: .utf8) else {
            line.removeAll(keepingCapacity: true)
            return []
        }
        line.removeAll(keepingCapacity: true)
        if text.isEmpty {
            let event = dispatch()
            if discardingEvent {
                discardingEvent = false
                dataLines.removeAll(keepingCapacity: true)
                eventName = nil
                eventBytes = 0
                return []
            }
            return event.map { [$0] } ?? []
        }
        guard !text.hasPrefix(":"), !discardingEvent else { return [] }
        let field: Substring
        var value: Substring
        if let separator = text.firstIndex(of: ":") {
            field = text[..<separator]
            value = text[text.index(after: separator)...]
            if value.first == " " { value = value.dropFirst() }
        } else {
            field = Substring(text)
            value = ""
        }
        switch field {
        case "data":
            eventBytes += value.utf8.count
            if eventBytes > Self.maximumEventBytes {
                discardingEvent = true
                dataLines.removeAll(keepingCapacity: false)
                eventBytes = 0
            } else {
                dataLines.append(String(value))
            }
        case "event": eventName = String(value)
        default: break
        }
        return []
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            dataLines.removeAll(keepingCapacity: true)
            eventName = nil
            eventBytes = 0
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(name: eventName ?? "message", data: dataLines.joined(separator: "\n"))
    }
}
