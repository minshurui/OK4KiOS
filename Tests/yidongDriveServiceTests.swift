import XCTest
@testable import OK4KiOS

final class YiDongDriveServiceTests: XCTestCase {
    func testCredentialImportAndStatusRoundTrip() async throws {
        let store = MemoryCredentialStore()
        let client = MockYiDongHTTPClient(responses: [(200, Data(#"{"data":{"name":"User","userID":"139-1"}}"#.utf8))])
        let service = YiDongDriveService(client: client)
        let adapter = YiDongDriveServiceAdapter(service: service, store: store,
                                                threadStore: FishThreadStore(defaults: UserDefaults(suiteName: "test.yidong")!))
        try adapter.importCredential(jsonData: Data(#"{"authorization":"Bearer xyz","name":"User"}"#.utf8))
        let status = try await adapter.status()
        XCTAssertEqual(status.state, FishDriveStatus.State.loggedIn)
        XCTAssertTrue(status.detail.contains("User"))
        // 登录后持久化保留未知字段
        let saved = try XCTUnwrap(try store.data(for: "yidong"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertNotNil(root["authorization"])
    }

    func testBeginLoginIsHonestPending() async {
        let adapter = YiDongDriveServiceAdapter(service: YiDongDriveService(client: MockYiDongHTTPClient(responses: [])),
                                                store: MemoryCredentialStore(),
                                                threadStore: FishThreadStore(defaults: UserDefaults(suiteName: "test.yidong.p")!))
        do {
            _ = try await adapter.beginLogin()
            XCTFail("扫码协议未取证必须诚实抛错")
        } catch FishDriveError.protocolPending { }
    }

    func testLogoutRemovesCredential() async throws {
        let store = MemoryCredentialStore()
        try store.set(Data(#"{"authorization":"Bearer xyz"}"#.utf8), for: "yidong")
        let adapter = YiDongDriveServiceAdapter(service: YiDongDriveService(client: MockYiDongHTTPClient(responses: [])),
                                                store: store,
                                                threadStore: FishThreadStore(defaults: UserDefaults(suiteName: "test.yidong.l")!))
        try await adapter.logout()
        XCTAssertNil(try store.data(for: "yidong"))
    }
}

private final class MockYiDongHTTPClient: YiDongHTTPClient {
    let responses: [(Int, Data)]
    private var index = 0
    init(responses: [(Int, Data)]) {
        self.responses = responses
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (code, data) = responses[min(index, responses.count - 1)]
        index += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}
