import XCTest
@testable import F1Companion

final class CredentialStoreTests: XCTestCase {
    func testInvalidServiceFailsBeforeKeychainCall() {
        let store = KeychainStore(service: "")
        let server = URL(string: "https://pitpulse.example")!
        XCTAssertThrowsError(try store.token(for: server)) { error in
            XCTAssertEqual(error as? CredentialError, .invalidService)
        }
    }

    func testEmptyTokenIsRejected() {
        let store = KeychainStore(service: "")
        let server = URL(string: "https://pitpulse.example")!
        XCTAssertThrowsError(try store.save(token: "   ", for: server)) { error in
            XCTAssertEqual(error as? CredentialError, .invalidService)
        }
    }
}
