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

    func testBeginLoginCreatesQRCode() async throws {
        let qr = Data(#"{"errno":0,"data":{"img":"data:image/png;base64,x","sign":"abc123"}}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, qr)], store: MemoryCredentialStore())
        let session = try await adapter.beginLogin()
        XCTAssertEqual(session.deviceCode, "abc123")
        XCTAssertFalse(session.qrPayload.isEmpty)
    }

    func testPollPendingThenAuthorized() async throws {
        let store = MemoryCredentialStore()
        let qr = Data(#"{"errno":0,"data":{"img":"x","sign":"abc123"}}"#.utf8)
        let pending = Data(#"{"errno":0,"data":{"status":0}}"#.utf8)
        let confirmed = Data(#"{"errno":0,"data":{"status":2}}"#.utf8)
        let profile = Data(#"{"errno":0,"username":"testuser"}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, qr), (200, pending), (200, confirmed), (200, profile)], store: store)
        let session = try await adapter.beginLogin()
        let first = try await adapter.poll(session)
        XCTAssertEqual(first, .pending)
        let second = try await adapter.poll(session)
        XCTAssertEqual(second, .authorized)
        XCTAssertNotNil(try store.data(for: "baidu"))
    }

    func testManualCookieLoginPersistsCredential() async throws {
        let store = MemoryCredentialStore()
        let profile = Data(#"{"errno":0,"username":"testuser","avatar":"http://avatar","vip_level":"1","unknown":{"keep":1}}"#.utf8)
        let (adapter, client) = makeAdapter(responses: [(200, profile)], store: store)

        try await adapter.loginWithCookie("BDUSS=abc123; PANWAP=def456")

        let saved = try XCTUnwrap(try store.data(for: "baidu"))
        let credential = try BaiduCredential(responseData: saved)
        XCTAssertEqual(credential.username, "testuser")
        XCTAssertEqual(credential.cookies["BDUSS"], "abc123")
        XCTAssertEqual(client.requests[0].url?.absoluteString, "https://pan.baidu.com/api/user/getinfo")
        let sentCookie = client.requests[0].value(forHTTPHeaderField: "Cookie") ?? ""
        XCTAssertTrue(sentCookie.contains("BDUSS=abc123") && sentCookie.contains("PANWAP=def456"))
    }

    func testStatusNotLoggedIn() async throws {
        let (adapter, _) = makeAdapter(responses: [], store: MemoryCredentialStore())
        let status = try await adapter.status()
        XCTAssertEqual(status.state, .notLoggedIn)
        XCTAssertTrue(status.detail.contains("手动 Cookie"))
    }

    func testStatusLoggedInWithValidCookie() async throws {
        let store = MemoryCredentialStore()
        let profile = Data(#"{"errno":0,"username":"testuser"}"#.utf8)
        // loginWithCookie 用 1 个 profile，status 再请求 1 个
        let (adapter, _) = makeAdapter(responses: [(200, profile), (200, profile)], store: store)

        try await adapter.loginWithCookie("BDUSS=abc123")
        let status = try await adapter.status()
        XCTAssertEqual(status.state, FishDriveStatus.State.loggedIn)
        XCTAssertEqual(status.displayName, "testuser")
    }

    func testLogoutRemovesCredential() async throws {
        let store = MemoryCredentialStore()
        let profile = Data(#"{"errno":0,"username":"testuser"}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, profile)], store: store)

        try await adapter.loginWithCookie("BDUSS=abc123")
        XCTAssertNotNil(try store.data(for: "baidu"))
        try await adapter.logout()
        XCTAssertNil(try store.data(for: "baidu"))
    }

    func testRefreshWithValidCookie() async throws {
        let store = MemoryCredentialStore()
        let profile = Data(#"{"errno":0,"username":"testuser"}"#.utf8)
        // loginWithCookie + refresh(profile) + status(profile) 共 3 个请求
        let (adapter, _) = makeAdapter(responses: [(200, profile), (200, profile), (200, profile)], store: store)

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
        XCTAssertTrue(service.supportsScanLogin)
        XCTAssertEqual(service.displayName, "百度网盘")
    }
}
