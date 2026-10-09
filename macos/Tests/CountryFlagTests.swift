import XCTest
@testable import F1Companion

final class CountryFlagTests: XCTestCase {
    func testSupportedFlagCodes() {
        XCTAssertEqual(CountryFlag.emoji(for: "AU"), "🇦🇺")
        XCTAssertEqual(CountryFlag.emoji(for: "gb"), "🇬🇧")
        XCTAssertEqual(CountryFlag.emoji(for: "US"), "🇺🇸")
        XCTAssertEqual(CountryFlag.emoji(for: "AE"), "🇦🇪")
        XCTAssertEqual(CountryFlag.emoji(for: "JP"), "🇯🇵")
    }

    func testUnknownAndInvalidCodesUseGlobeFallback() {
        XCTAssertNil(CountryFlag.emoji(for: "XX"))
        XCTAssertNil(CountryFlag.emoji(for: "A"))
        XCTAssertEqual(CountryFlag.display(country: "Unknownland", code: "XX"), "🌐 Unknownland")
    }

    func testSameCountryMeetingsKeepDistinctIdentifiers() {
        let first = TestData.meeting(id: "2026:1", code: "US")
        let second = TestData.meeting(id: "2026:2", round: 2, name: "Miami Grand Prix", code: "US")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(CountryFlag.emoji(for: first.countryCode), CountryFlag.emoji(for: second.countryCode))
    }
}
