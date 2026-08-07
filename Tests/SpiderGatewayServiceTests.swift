import XCTest
@testable import OK4KiOS

final class SpiderGatewayServiceTests: XCTestCase {
    func testPlayerExternalizesAndroidLoopbackURL() async throws {
        let configData = #"{"spider":"https://example.test/spider.jar","sites":[{"key":"Guard","name":"Guard","type":3,"api":"csp_Guard"}]}"#.data(using: .utf8)!
        let site = try JSONDecoder().decode(TVBoxConfig.self, from: configData).sites[0]
        let response = #"{"url":"http://127.0.0.1:9978/proxy?siteKey=Guard","header":{"Referer":"https://example.test/"}}"#.data(using: .utf8)!
        let service = SpiderGatewayService(
            site: site,
            gatewayURL: URL(string: "http://100.118.96.31:9980")!,
            client: GatewayClient(data: response)
        )

        let playback = try await service.player(flag: "line", id: "episode")

        XCTAssertEqual(playback.url, "http://100.118.96.31:9980/proxy?siteKey=Guard")
        XCTAssertEqual(playback.headers["Referer"], "https://example.test/")
    }
}

private struct GatewayClient: APIClientProtocol {
    let data: Data

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        XCTAssertEqual(request.url?.path, "/api/spider")
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
