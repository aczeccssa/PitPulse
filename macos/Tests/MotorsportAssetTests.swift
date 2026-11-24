import XCTest
@testable import SharedData
@testable import PitPulseDesktop

final class MotorsportAssetTests: XCTestCase {
    func testStableIDsMapToSeasonSpecificCatalogNames() {
        XCTAssertEqual(MotorsportAsset.name(kind: .helmet, id: "max_verstappen", season: 2026), "helmet-max_verstappen-2026")
        XCTAssertEqual(MotorsportAsset.name(kind: .teamLogo, id: "red_bull", season: 2026), "team-logo-red_bull-2026")
        XCTAssertEqual(MotorsportAsset.abbreviation("Lando Norris"), "NOR")
        XCTAssertEqual(MotorsportAsset.name(kind: .helmet, id: "verstappen", season: 2026), "helmet-max_verstappen-2026")
        XCTAssertEqual(MotorsportAsset.name(kind: .helmet, id: "lindblad", season: 2026), "helmet-arvid_lindblad-2026")
    }

    func testDesktopLoadsArchivedArtworkAndKeepsMissingHelmetsEmpty() {
        XCTAssertNotNil(MotorsportAsset.image(kind: .driverPhoto, id: "verstappen", season: 2024))
        XCTAssertNotNil(MotorsportAsset.image(kind: .teamLogo, id: "kick_sauber", season: 2025))
        XCTAssertNotNil(MotorsportAsset.image(kind: .carSide, id: "mclaren", season: 2025))
        XCTAssertNil(MotorsportAsset.f1HelmetImage(id: "leclerc", season: 2025))
    }
}
