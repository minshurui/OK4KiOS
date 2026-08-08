import XCTest
@testable import OK4KiOS

// MARK: - Mock HTTP 客户端

final class BaiduMockHTTPClient: BaiduHTTPClientProtocol {
    var requests: [URLRequest] = []
    var responses: [(Int, Data)]
    private var index = 0

    init(responses: [(Int, Data)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard index < responses.count else {
            throw URLError(.badServerResponse)
        }
        let (statusCode, data) = responses[index]
        index += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

// MARK: - 百度网盘适配器测试

final class BaiduDriveAdapterTests: XCTestCase {
    private func makeAdapter(responses: [(Int, Data)], store: MemoryCredentialStore) -> (BaiduDriveServiceAdapter, BaiduMockHTTPClient) {
        let client = BaiduMockHTTPClient(responses: responses)
        let auth = BaiduAuthService(client: client)
        let session = BaiduSession(store: store, service: auth)
        return (BaiduDriveServiceAdapter(session: session, auth: auth, threadStore: FishThreadStore(defaults: UserDefaults(suiteName: "test.baidu.threads")!)), client)
    }

    func testBeginLoginThrowsProtocolPending() async throws {
        let (adapter, _) = makeAdapter(responses: [], store: MemoryCredentialStore())
        do {
            _ = try await adapter.beginLogin()
            XCTFail("beginLogin 必须诚实抛错")
        } catch FishDriveError.protocolPending(let reason) {
            XCTAssertTrue(reason.contains("百度"))
        }
    }

    func testPollThrowsProtocolPending() async throws {
        let (adapter, _) = makeAdapter(responses: [], store: MemoryCredentialStore())
        let session = FishScanSession(qrPayload: "x", deviceCode: "d", expiresIn: 1, interval: 1, openURL: nil)
        do {
            _ = try await adapter.poll(session)
            XCTFail("poll 必须诚实抛错")
        } catch FishDriveError.protocolPending { }
    }

    func testManualCookieLoginPersistsCredential() async throws {
        let store = MemoryCredentialStore()
        let profile = Data(#"{"username":"testuser","avatar":"http://avatar","vip_level":"1","unknown":{"keep":1}}"#.utf8)
        let (adapter, client) = makeAdapter(responses: [(200, profile)], store: store)

        try await adapter.loginWithCookie("BDUSS=abc123; PANWAP=def456")

        let saved = try XCTUnwrap(try store.data(for: "baidu"))
        let credential = try BaiduCredential(responseData: saved)
        XCTAssertEqual(credential.username, "testuser")
        XCTAssertEqual(credential.cookies["BDUSS"], "abc123")
        XCTAssertEqual(client.requests[0].url?.absoluteString, "https://pan.baidu.com/api/getuserinfo")
        XCTAssertEqual(client.requests[0].value(forHTTPHeaderField: "Cookie"), "BDUSS=abc123; PANWAP=def456")
    }

    func testStatusNotLoggedIn() async throws {
        let (adapter, _) = makeAdapter(responses: [], store: MemoryCredentialStore())
        let status = try await adapter.status()
        XCTAssertEqual(status.state, .notLoggedIn)
        XCTAssertTrue(status.detail.contains("手动 Cookie"))
    }

    func testStatusLoggedInWithValidCookie() async throws {
        let store = MemoryCredentialStore()
        let profile = Data(#"{"username":"testuser"}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, profile)], store: store)

        try await adapter.loginWithCookie("BDUSS=abc123")
        let status = try await adapter.status()
        XCTAssertEqual(status.state, FishDriveStatus.State.loggedIn)
        XCTAssertEqual(status.displayName, "testuser")
    }

    func testLogoutRemovesCredential() async throws {
        let store = MemoryCredentialStore()
        let profile = Data(#"{"username":"testuser"}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, profile)], store: store)

        try await adapter.loginWithCookie("BDUSS=abc123")
        XCTAssertNotNil(try store.data(for: "baidu"))
        try await adapter.logout()
        XCTAssertNil(try store.data(for: "baidu"))
    }

    func testRefreshWithValidCookie() async throws {
        let store = MemoryCredentialStore()
        let profile = Data(#"{"username":"testuser"}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, profile)], store: store)

        try await adapter.loginWithCookie("BDUSS=abc123")
        try await adapter.refresh()
        let status = try await adapter.status()
        XCTAssertEqual(status.state, FishDriveStatus.State.loggedIn)
    }

    func testThreadOptions() {
        let (adapter, _) = makeAdapter(responses: [], store: MemoryCredentialStore())
        XCTAssertEqual(adapter.threadOptions, FishThreadOption.all)
        adapter.setThread("vip")
        XCTAssertEqual(adapter.currentThread(), "vip")
    }
}

// MARK: - 注册表测试

final class BaiduRegistryTests: XCTestCase {
    func testBaiduRoutesToAdapter() {
        let service = FishDriveRegistry.service(for: "baidu")
        XCTAssertFalse(service.supportsScanLogin)
        XCTAssertEqual(service.displayName, "百度网盘")
        XCTAssertTrue(service.protocolEvidence.contains("部分取证"))
    }
}
