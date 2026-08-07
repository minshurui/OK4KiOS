import XCTest
@testable import OK4KiOS

final class SiteModelsTests: XCTestCase {
    func testDecodesType3SiteAndFindsNativeHosts() throws {
        let data = #"{"spider":"https://example.test/spider.jar","sites":[{"key":"Wogg","name":"玩偶","type":3,"api":"csp_Wogg","ext":{"site":["https://one.test","https://two.test"]}},{"key":"Guard","name":"加密","type":3,"api":"csp_Guard","ext":"ciphertext"}]}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(TVBoxConfig.self, from: data)
        XCTAssertEqual(config.sites.count, 2)
        XCTAssertEqual(config.sites[0].nativeBaseURLs.map(\.host), ["one.test", "two.test"])
        XCTAssertTrue(config.sites[0].canRunNatively)
        XCTAssertFalse(config.sites[1].canRunNatively)
    }
}
