import XCTest
@testable import OK4KiOS

final class APIClientTests: XCTestCase {
    func testHTTPErrorEquality() {
        XCTAssertEqual(HTTPError.status(403), HTTPError.status(403))
    }
}
