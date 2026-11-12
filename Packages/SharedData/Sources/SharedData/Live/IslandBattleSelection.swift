import Foundation

public enum IslandBattleSelection {
    public static func toggled(_ number: String, in selected: [String]) -> [String] {
        if selected.contains(number) { return selected.filter { $0 != number } }
        return selected.count < 2 ? selected + [number] : selected
    }
    public static func drivers(in drivers: [LiveDriver], selected: [String], favorite: LiveDriver?) -> [LiveDriver] {
        let sorted = drivers.filter { $0.position != nil }.sorted { $0.position! < $1.position! }
        if !selected.isEmpty { return Array(sorted.filter { selected.contains($0.number) }.prefix(2)) }
        guard let favorite, let index = sorted.firstIndex(where: { $0.number == favorite.number }) else { return Array(sorted.prefix(2)) }
        if index == 0 { return Array(sorted.prefix(2)) }
        return [sorted[index - 1], sorted[index]]
    }
    public static func gap(between drivers: [LiveDriver]) -> String? {
        guard drivers.count == 2 else { return nil }
        let front = drivers[0], back = drivers[1]
        if let p = front.position, back.position == p + 1, let interval = back.interval { return interval }
        func seconds(_ value: String?) -> Double? {
            guard let value else { return nil }
            if value.uppercased() == "LEADER" { return 0 }
            guard let result = Double(value.replacingOccurrences(of: "+", with: "")), result.isFinite, result >= 0 else { return nil }
            return result
        }
        guard let a = front.position == 1 ? 0 : seconds(front.gap), let b = seconds(back.gap), b >= a else { return nil }
        return String(format: "+%.3f", b - a)
    }
}
