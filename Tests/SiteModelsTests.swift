import XCTest
@testable import OK4KiOS

final class SiteModelsTests: XCTestCase {
    func testCreatesManualXMLSite() {
        let site = TVBoxSite(key: "manual", name: "XML", type: 0, api: "https://example.test/api")
        XCTAssertEqual(site.kindLabel, "XML")
        XCTAssertTrue(site.canRunNatively)
        XCTAssertEqual(site.apiURL?.host, "example.test")
    }

    func testDecodesType3SiteAndFindsNativeHosts() throws {
        let data = #"{"spider":"https://example.test/spider.jar","sites":[{"key":"Wogg","name":"玩偶","type":3,"api":"csp_Wogg","ext":{"site":["https://one.test","https://two.test"]}},{"key":"Guard","name":"加密","type":3,"api":"csp_Guard","ext":"ciphertext"}]}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(TVBoxConfig.self, from: data)
        XCTAssertEqual(config.sites.count, 2)
        XCTAssertEqual(config.sites[0].jar, "https://example.test/spider.jar")
        XCTAssertEqual(config.sites[1].jar, "https://example.test/spider.jar")
        XCTAssertEqual(config.sites[0].nativeBaseURLs.map(\.host), ["one.test", "two.test"])
        XCTAssertTrue(config.sites[0].canRunNatively)
        XCTAssertFalse(config.sites[1].canRunNatively)
    }

    func testDecodesType4RuleSite() throws {
        let data = #"{"sites":[{"key":"rule","name":"规则接口","type":4,"api":"https://example.test/rule","ext":"payload"}]}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(TVBoxConfig.self, from: data)
        XCTAssertEqual(config.sites.first?.type, 4)
        XCTAssertEqual(config.sites.first?.kindLabel, "规则网关")
    }
}
