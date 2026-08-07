import XCTest
@testable import OK4KiOS

final class PlaybackRequestTests: XCTestCase {
    func testParsesTVBoxHeaderSuffix() {
        let request = PlaybackRequest.parse("https://example.test/live.m3u8|User-Agent=OK%204K&Referer=https%3A%2F%2Fexample.test%2F")
        XCTAssertEqual(request.urlString, "https://example.test/live.m3u8")
        XCTAssertEqual(request.headers["User-Agent"], "OK 4K")
        XCTAssertEqual(request.headers["Referer"], "https://example.test/")
    }

    func testAdditionalHeadersWinWithoutSuffixOverride() {
        let request = PlaybackRequest.parse("https://example.test/video.mp4", additionalHeaders: ["Origin": "https://example.test"])
        XCTAssertEqual(request.headers["Origin"], "https://example.test")
    }
}
