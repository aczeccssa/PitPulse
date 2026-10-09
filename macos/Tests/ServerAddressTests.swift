import XCTest
@testable import F1Companion

final class ServerAddressTests: XCTestCase {
    func testLocalHTTPIsAllowed() throws {
        let address = try ServerAddress(rawValue: "http://localhost:38701")
        XCTAssertEqual(address.url.absoluteString, "http://localhost:38701")
    }

    func testLoopbackHTTPIsAllowed() throws {
        XCTAssertNoThrow(try ServerAddress(rawValue: "http://127.0.0.1:38701"))
        XCTAssertNoThrow(try ServerAddress(rawValue: "http://[::1]:38701"))
    }

    func testRemoteHTTPIsRejected() {
        XCTAssertThrowsError(try ServerAddress(rawValue: "http://pitpulse.example")) { error in
            XCTAssertEqual(error as? APIClientError, .insecureRemoteServer)
        }
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
