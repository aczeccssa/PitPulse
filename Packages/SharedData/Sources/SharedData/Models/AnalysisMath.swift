import Foundation

public enum AnalysisMath {
    /// Parses recorded lap and elapsed times, such as 1:23.456 or 1:35:23.504.
    public static func elapsedSeconds(_ value: String?) -> Double? {
        guard let value, !value.hasPrefix("+") else { return nil }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == parts.count, numbers.allSatisfy({ $0.isFinite && $0 >= 0 }),
              numbers.dropFirst().allSatisfy({ $0 < 60 }),
              numbers.dropLast().allSatisfy({ $0.rounded() == $0 }) else { return nil }
        let seconds = numbers.reduce(0) { $0 * 60 + $1 }
        return seconds > 0 && seconds.isFinite ? seconds : nil
    }

    public static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0, seconds <= 360000 else { return "—" }
        let milliseconds = Int((seconds * 1000).rounded())
        let whole = milliseconds / 1000
        let tail = String(format: "%02d.%03d", whole % 60, milliseconds % 1000)
        return whole >= 3600 ? "\(whole / 3600):\(String(format: "%02d", whole / 60 % 60)):\(tail)" : "\(whole / 60):\(tail)"
    }
    public static func telemetry(at date: Date?, in rows: [AnalysisTelemetry]) -> AnalysisTelemetry? {
        guard let date else { return nil }
        let closest = rows.filter { $0.date != nil }.min {
            abs($0.date!.timeIntervalSince(date)) < abs($1.date!.timeIntervalSince(date))
        }
        guard let closest, abs(closest.date!.timeIntervalSince(date)) <= 1 else { return nil }
        return closest
    }
}
