import XCTest
@testable import OK4KiOS

final class VodModelsTests: XCTestCase {
    func testAppleCMSMixedNumericAndStringFields() throws {
        let data = #"{"code":"1","page":"2","total":1,"list":[{"vod_id":42,"vod_name":"Demo","vod_play_from":"A$$$B","vod_play_url":"One$https://a.test/1#Two$https://b.test/2$$$Only$https://a.test/3"}]}"#.data(using: .utf8)!
        let result = try JSONDecoder().decode(VodResult.self, from: data)
        XCTAssertEqual(result.page?.value, 2)
        XCTAssertEqual(result.list.first?.id, "42")
        XCTAssertEqual(result.list.first?.flags.count, 2)
        XCTAssertEqual(result.list.first?.flags[0].episodes.count, 2)
        XCTAssertEqual(result.list.first?.flags[1].episodes.first?.url, "https://a.test/3")
    }
}
