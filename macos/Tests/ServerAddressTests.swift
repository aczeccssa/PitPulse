import XCTest
@testable import PitPulseData
@testable import PitPulseDesktop

final class ServerAddressTests: XCTestCase {
    func testLocalHTTPIsAllowed() throws {
        let address = try ServerAddress(rawValue: "http://localhost:38701")
        XCTAssertEqual(address.url.absoluteString, "http://localhost:38701")
    }

    func testLoopbackHTTPIsAllowed() throws {
        XCTAssertNoThrow(try ServerAddress(rawValue: "http://127.0.0.1:38701"))
        XCTAssertNoThrow(try ServerAddress(rawValue: "http://[::1]:38701"))
    }

    func testAnyHostAndIPOverHTTPIsAllowed() throws {
        XCTAssertEqual(
            try ServerAddress(rawValue: "http://192.168.1.50:38701").url.absoluteString,
            "http://192.168.1.50:38701"
        )
        XCTAssertEqual(
            try ServerAddress(rawValue: "http://pitpulse.example").url.absoluteString,
            "http://pitpulse.example"
        )
        XCTAssertEqual(
            try ServerAddress(rawValue: "http://10.0.0.8:38701/api").url.absoluteString,
            "http://10.0.0.8:38701/api"
        )
    }

    func testBareAddressDefaultsToHTTP() throws {
        XCTAssertEqual(
            try ServerAddress(rawValue: "192.168.1.50:38701").url.absoluteString,
            "http://192.168.1.50:38701"
        )
        XCTAssertEqual(
            try ServerAddress(rawValue: "pitpulse.example").url.absoluteString,
            "http://pitpulse.example"
        )
    }

    func testHTTPSAndCredentialsAreValidated() throws {
        XCTAssertNoThrow(try ServerAddress(rawValue: "https://pitpulse.example"))
        XCTAssertThrowsError(try ServerAddress(rawValue: "https://user:secret@pitpulse.example"))
        XCTAssertThrowsError(try ServerAddress(rawValue: "https://pitpulse.example?token=secret"))
        XCTAssertThrowsError(try ServerAddress(rawValue: "not a server address"))
    }
}

extension ServerAddressTests {
    func testIdentityNormalizesHostButPreservesCaseSensitivePath() throws {
        let canonical = try ServerAddress(rawValue: "https://EXAMPLE.com:443/PitPulse/")
        XCTAssertEqual(canonical.identity, "https://example.com/PitPulse")
        XCTAssertNotEqual(canonical.identity, try ServerAddress(rawValue: "https://example.com/pitpulse").identity)
    }
}
