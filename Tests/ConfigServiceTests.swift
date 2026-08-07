import Foundation
import XCTest
@testable import OK4KiOS

final class ConfigServiceTests: XCTestCase {
    func testLoadFiltersUtilityEntriesButKeepsVodSites() async throws {
        let data = #"{"sites":[{"key":"FishConfig","name":"设置中心","type":3,"api":"csp_FishConfig"},{"key":"Wogg","name":"玩偶","type":3,"api":"csp_Wogg","ext":{"site":"https://wogg.example"}},{"key":"json","name":"JSON","type":1,"api":"https://api.example/vod"}]}"#.data(using: .utf8)!
        let service = ConfigService(client: ConfigClient(data: data))

        let sites = try await service.load(urlString: "https://config.example/tvbox.json")

        XCTAssertEqual(sites.map(\.key), ["Wogg", "json"])
        XCTAssertTrue(sites.allSatisfy(\.isBrowsableVodSite))
    }
}

private struct ConfigClient: APIClientProtocol {
    let data: Data

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, response)
    }
}
