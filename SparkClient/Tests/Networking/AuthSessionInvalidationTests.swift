#if canImport(XCTest)
import XCTest

final class AuthSessionInvalidationTests: XCTestCase {
    func test403DoesNotInvalidate() {
        XCTAssertFalse(
            AuthSessionInvalidation.shouldInvalidate(
                statusCode: 403,
                backendCode: -1,
                message: "permission_denied"
            )
        )
    }

    func test401Invalidates() {
        XCTAssertTrue(
            AuthSessionInvalidation.shouldInvalidate(
                statusCode: 401,
                backendCode: nil,
                message: ""
            )
        )
    }

    func testTokenNotValidMessageInvalidates() {
        XCTAssertTrue(
            AuthSessionInvalidation.shouldInvalidate(
                statusCode: 200,
                backendCode: nil,
                message: "token_not_valid"
            )
        )
    }

    func testDeviceSessionReplacedMessageInvalidates() {
        XCTAssertTrue(
            AuthSessionInvalidation.shouldInvalidate(
                statusCode: 200,
                backendCode: 40105,
                message: "device_session_replaced"
            )
        )
    }
}
#endif
