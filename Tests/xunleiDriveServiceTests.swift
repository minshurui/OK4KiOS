import XCTest
@testable import OK4KiOS

// MARK: - 迅雷网盘生命周期测试（mock HTTP，不真网）

final class XunleiDriveAdapterTests: XCTestCase {
    private func makeAdapter(responses: [(Int, Data)], store: MemoryCredentialStore) -> (XunleiDriveServiceAdapter, XunleiMockHTTPClient) {
        let client = XunleiMockHTTPClient(responses: responses)
        let auth = XunleiAuthService(client: client)
        let session = XunleiSession(store: store, service: auth)
        return (XunleiDriveServiceAdapter(session: session, auth: auth, threadStore: FishThreadStore(defaults: UserDefaults(suiteName: "test.xunlei.threads")!)), client)
    }

    func testBeginLoginCreatesDeviceCodeSession() async throws {
        let store = MemoryCredentialStore()
        let device = Data(#"{"device_code":"dc1","user_code":"u1","verification_uri_complete":"https://pan.xunlei.com/scan","interval":3,"expires_in":300}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, device)], store: store)
        let session = try await adapter.beginLogin()
        XCTAssertTrue(session.deviceCode.contains("dc1"))
    }

    func testPollPendingThenAuthorized() async throws {
        let store = MemoryCredentialStore()
        let device = Data(#"{"device_code":"dc1","user_code":"u1","verification_uri_complete":"https://pan.xunlei.com/scan","interval":3,"expires_in":300}"#.utf8)
        let pending = Data(#"{"error":"authorization_pending"}"#.utf8)
        let authorized = Data(#"{"access_token":"a","refresh_token":"r","token_type":"Bearer"}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, device), (200, pending), (200, authorized)], store: store)
        let session = try await adapter.beginLogin()
        let first = try await adapter.poll(session)
        XCTAssertEqual(first, .pending)
        let second = try await adapter.poll(session)
        XCTAssertEqual(second, .authorized)
        XCTAssertNotNil(try store.data(for: "xunlei"))
    }

    func testRefreshWithoutCredentialThrowsNotLoggedIn() async throws {
        let store = MemoryCredentialStore()
        let (adapter, _) = makeAdapter(responses: [], store: store)
        do {
            try await adapter.refresh()
            XCTFail("无凭据 refresh 必须抛 notLoggedIn")
        } catch XunleiAuthError.notLoggedIn { } catch FishDriveError.notLoggedIn { }
    }

    func testStatusNotLoggedIn() async throws {
        let store = MemoryCredentialStore()
        let (adapter, _) = makeAdapter(responses: [], store: store)
        let status = try await adapter.status()
        XCTAssertEqual(status.state, .notLoggedIn)
    }

    func testLogoutRemovesStoredCredential() async throws {
        let store = MemoryCredentialStore()
        try store.set(Data(#"{"access_token":"legacy"}"#.utf8), for: "xunlei")
        let (adapter, _) = makeAdapter(responses: [], store: store)
        try await adapter.logout()
        XCTAssertNil(try store.data(for: "xunlei"))
    }

    func testRegistryRoutesToXunleiAdapter() {
        let service = FishDriveRegistry.service(for: "xunlei")
        XCTAssertEqual(service.driveKey, "xunlei")
        XCTAssertEqual(service.displayName, "迅雷网盘")
        XCTAssertTrue(service.supportsScanLogin)
    }
}

// MARK: - 迅雷 mock HTTP client

final class XunleiMockHTTPClient: XunleiHTTPClientProtocol {
    var responses: [(Int, Data)]
    var requests: [URLRequest] = []

    init(responses: [(Int, Data)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let (statusCode, data) = responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}
