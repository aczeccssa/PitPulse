import AppKit
import XCTest
@testable import SharedData
@testable import PitPulseDesktop

extension LiveIslandTests {
    func testTeamAssetIDKeepsF1SeriesSeparateFromWecBrandLogos() throws {
        func driver(_ json: String) throws -> LiveDriver {
            try JSONDecoder().decode(LiveDriver.self, from: Data(json.utf8))
        }
        XCTAssertEqual(
            LiveIslandLogic.teamAssetID(for: try driver(#"{"number":"1","team":"Red Bull Racing"}"#), isWec: false),
            "red_bull"
        )
        XCTAssertEqual(
            LiveIslandLogic.teamAssetID(for: try driver(#"{"number":"38","team":"CADILLAC HERTZ TEAM JOTA","manufacturer":"Cadillac V-Series.R"}"#), isWec: true),
            "wec_cadillac"
        )
        XCTAssertEqual(
            LiveIslandLogic.teamAssetID(for: try driver(#"{"number":"7","team":"TOYOTA RACING","manufacturer":"Toyota TR010 Hybrid"}"#), isWec: true),
            "wec_toyota"
        )
        XCTAssertNil(LiveIslandLogic.teamAssetID(for: try driver(#"{"number":"99","team":"Unknown Team"}"#), isWec: true))
    }

    func testCarSideArtworkUsesTeamForF1AndCarNumberForWec() throws {
        func driver(_ json: String) throws -> LiveDriver {
            try JSONDecoder().decode(LiveDriver.self, from: Data(json.utf8))
        }
        XCTAssertEqual(
            LiveIslandLogic.carSideAssetID(for: try driver(#"{"number":"63","team":"Mercedes"}"#), isWec: false),
            "mercedes"
        )
        XCTAssertEqual(
            LiveIslandLogic.carSideAssetID(for: try driver(#"{"number":"1","team":"Red Bull Racing"}"#), isWec: false),
            "red_bull"
        )
        XCTAssertEqual(
            LiveIslandLogic.carSideAssetID(for: try driver(#"{"number":"38","manufacturer":"Cadillac V-Series.R"}"#), isWec: true),
            "38"
        )
        XCTAssertNil(LiveIslandLogic.carSideAssetID(for: try driver(#"{"number":"99","team":"Unknown Team"}"#), isWec: false))
    }

    func testWecTeamLogoPrefersCustomerTeamAndFallsBackToBrand() throws {
        func driver(_ json: String) throws -> LiveDriver {
            try JSONDecoder().decode(LiveDriver.self, from: Data(json.utf8))
        }
        XCTAssertEqual(
            LiveIslandLogic.teamAssetID(for: try driver(#"{"number":"10","team":"GARAGE 59","manufacturer":"McLaren 720S LMGT3 Evo"}"#), isWec: true),
            "wec_garage_59"
        )
        XCTAssertEqual(
            LiveIslandLogic.teamAssetID(for: try driver(#"{"number":"20","team":"BMW M TEAM WRT","manufacturer":"BMW M Hybrid V8"}"#), isWec: true),
            "wec_bmw"
        )
        XCTAssertEqual(
            LiveIslandLogic.teamAssetID(for: try driver(#"{"number":"69","team":"TEAM WRT","manufacturer":"BMW M4 LMGT3 Evo"}"#), isWec: true),
            "wec_team_wrt"
        )
    }

    func testDriverAssetSlugFoldsDiacriticsUsedByWecPortraits() {
        func driver(_ name: String) throws -> LiveDriver {
            try JSONDecoder().decode(LiveDriver.self, from: Data("{\"number\":\"8\",\"name\":\"\(name)\"}".utf8))
        }
        XCTAssertEqual(LiveIslandLogic.driverAssetID(for: try! driver("Marco SØRENSEN")), "marco-sorensen")
        XCTAssertEqual(LiveIslandLogic.driverAssetID(for: try! driver("Sébastien Bourdais")), "sebastien-bourdais")
        XCTAssertEqual(LiveIslandLogic.driverAssetID(for: try! driver("Petru UMBRĂRESCU")), "petru-umbrarescu")
        XCTAssertNil(LiveIslandLogic.driverAssetID(for: LiveDriver(number: "8", name: nil, team: nil, position: nil, gap: nil, interval: nil, lapCount: nil, lastLap: nil, bestLap: nil)))
    }
}
