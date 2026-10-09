import Foundation

enum CountryFlag {
    static func emoji(for code: String?) -> String? {
        guard let normalized = normalizedCode(code), isKnownRegion(normalized) else {
            return nil
        }
        let scalars = normalized.unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            guard scalar.value >= 65, scalar.value <= 90 else { return nil }
            return UnicodeScalar(127_397 + scalar.value)
        }
        guard scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }

    static func display(country: String, code: String?) -> String {
        if let emoji = emoji(for: code) {
            return "\(emoji) \(country)"
        }
        return "🌐 \(country)"
    }

    static func normalizedCode(_ code: String?) -> String? {
        guard let code else { return nil }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 2,
              normalized.unicodeScalars.allSatisfy({ (65...90).contains($0.value) })
        else {
            return nil
        }
        return normalized
    }

    private static func isKnownRegion(_ code: String) -> Bool {
        Locale.Region.isoRegions.contains { $0.identifier.uppercased() == code }
    }
}
