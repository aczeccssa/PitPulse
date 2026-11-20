import Foundation
import XCTest
@testable import SharedData

final class EngineeringReportsTests: XCTestCase {
    func testPowerUnitReportKeepsZeroAndAcceptsUnreportedElements() throws {
        let json = """
        {
          "data": {
            "usage": [
              {"driverName": "Driver", "used": {"ice": 0, "mgu-k": 2, "gbx": null}}
            ],
            "elements": [{"code": "ice", "name": "Internal combustion engine", "quota": 4}],
            "penalties": []
          },
          "meta": {"sections": {"usage": {"coverage": {"complete": false}, "stale": true}}}
        }
        """
        let report = try JSONDecoder().decode(EngineeringReport<PowerUnitReport>.self, from: Data(json.utf8))
        let usage = try XCTUnwrap(report.data.usage.first)
        XCTAssertEqual(usage.count(for: "ICE"), 0)
        XCTAssertEqual(usage.count(for: "mgu-k"), 2)
        XCTAssertNil(usage.count(for: "gbx"))
        XCTAssertNil(usage.count(for: "es"))
        XCTAssertEqual(report.meta?.sections?["usage"]?.coverage?.complete, false)
    }

    func testElapsedTimeParsingDoesNotConfuseGapAndTotalTime() throws {
        XCTAssertEqual(try XCTUnwrap(AnalysisMath.elapsedSeconds("1:35:23.504")), 5723.504, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(AnalysisMath.elapsedSeconds("1:23.456")), 83.456, accuracy: 0.001)
        XCTAssertNil(AnalysisMath.elapsedSeconds("+15.123"))
        XCTAssertNil(AnalysisMath.elapsedSeconds("1:73.0"))
        XCTAssertNil(AnalysisMath.elapsedSeconds("DNF"))
    }
}
