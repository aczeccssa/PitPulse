import XCTest
@testable import PitPulseData
@testable import F1Companion

final class MotorsportAssetTests: XCTestCase {
    func testStableIDsMapToSeasonSpecificCatalogNames() {
        XCTAssertEqual(MotorsportAsset.name(kind: .helmet, id: "max_verstappen", season: 2026), "helmet-max_verstappen-2026")
        XCTAssertEqual(MotorsportAsset.name(kind: .teamLogo, id: "red_bull", season: 2026), "team-logo-red_bull-2026")
        XCTAssertEqual(MotorsportAsset.abbreviation("Lando Norris"), "NOR")
        XCTAssertEqual(MotorsportAsset.name(kind: .helmet, id: "verstappen", season: 2026), "helmet-max_verstappen-2026")
        XCTAssertEqual(MotorsportAsset.name(kind: .helmet, id: "lindblad", season: 2026), "helmet-arvid_lindblad-2026")
    }
}
