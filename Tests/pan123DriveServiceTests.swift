import XCTest
@testable import OK4KiOS

// MARK: - Mock HTTP Client

final class Pan123MockHTTPClient: Pan123HTTPClientProtocol {
    var requests: [URLRequest] = []
    private var responses: [(Int, Data)]
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

// MARK: - 生命周期测试

final class Pan123DriveAdapterTests: XCTestCase {
    private func makeAdapter(responses: [(Int, Data)], store: MemoryCredentialStore) -> (Pan123DriveServiceAdapter, Pan123MockHTTPClient) {
        let client = Pan123MockHTTPClient(responses: responses)
        let auth = Pan123AuthService(client: client)
        let session = Pan123Session(store: store, service: auth)
        return (Pan123DriveServiceAdapter(session: session, auth: auth, threadStore: FishThreadStore(defaults: UserDefaults(suiteName: "test.pan123.threads")!)), client)
    }

    func testBeginLoginCreatesSessionFromOAuthResponse() async throws {
        let body = Data(#"{"device_code":"code","expires_in":180,"interval":3,"verification_uri_complete":"https://open-api.123pan.com/scan"}"#.utf8)
        let (adapter, client) = makeAdapter(responses: [(200, body)], store: MemoryCredentialStore())
        let session = try await adapter.beginLogin()
        XCTAssertEqual(session.deviceCode, "code")
        XCTAssertEqual(session.qrPayload, "https://open-api.123pan.com/scan")
        XCTAssertEqual(session.expiresIn, 180)
        XCTAssertEqual(session.interval, 3)
        XCTAssertEqual(client.requests[0].url?.absoluteString, "https://open-api.123pan.com/api/v1/oauth2/user/authorize")
    }

    func testPollPendingThenAuthorizedPersistsCredential() async throws {
        let store = MemoryCredentialStore()
        let deviceCode = Data(#"{"device_code":"code","expires_in":180,"interval":3,"verification_uri_complete":"https://open-api.123pan.com/scan"}"#.utf8)
        let pending = Data(#"{"status":"pending"}"#.utf8)
        let authorized = Data(#"{"status":"authorized","data":{"access_token":"a","refresh_token":"r","token_type":"Bearer"},"unknown":{"keep":1}}"#.utf8)
        let profile = Data(#"{"data":{"nickname":"User"}}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, deviceCode), (200, pending), (200, authorized), (200, profile)], store: store)
        let session = try await adapter.beginLogin()
        XCTAssertEqual(session.deviceCode, "code")
        let first = try await adapter.poll(session)
        XCTAssertEqual(first, .pending)
        let second = try await adapter.poll(session)
        XCTAssertEqual(second, .authorized)
        let saved = try XCTUnwrap(try store.data(for: "pan123"))
        let credential = try Pan123Credential(responseData: saved)
        XCTAssertEqual(credential.accessToken, "a")
        XCTAssertEqual(credential.refreshToken, "r")
        XCTAssertEqual(credential.displayName, "User")
    }

    func testRefreshUsesRefreshToken() async throws {
        let store = MemoryCredentialStore()
        let initial = Data(#"{"access_token":"old","refresh_token":"r","token_type":"Bearer"}"#.utf8)
        try store.set(initial, for: "pan123")
        let refreshed = Data(#"{"access_token":"new","refresh_token":"r2","token_type":"Bearer"}"#.utf8)
        let profile = Data(#"{"data":{"nickname":"User"}}"#.utf8)
        let (adapter, client) = makeAdapter(responses: [(200, refreshed), (200, profile)], store: store)
        try await adapter.refresh()
        XCTAssertEqual(client.requests[0].url?.absoluteString, "https://oauth.litepan.top/api/oauth/refresh")
        let saved = try XCTUnwrap(try store.data(for: "pan123"))
        let credential = try Pan123Credential(responseData: saved)
        XCTAssertEqual(credential.accessToken, "new")
        XCTAssertEqual(credential.refreshToken, "r2")
    }

    func testLogoutRemovesCredential() async throws {
        let store = MemoryCredentialStore()
        let initial = Data(#"{"access_token":"a","refresh_token":"r","token_type":"Bearer"}"#.utf8)
        try store.set(initial, for: "pan123")
        let (adapter, _) = makeAdapter(responses: [], store: store)
        try await adapter.logout()
        XCTAssertNil(try store.data(for: "pan123"))
    }

    func testStatusNotLoggedIn() async throws {
        let (adapter, _) = makeAdapter(responses: [], store: MemoryCredentialStore())
        let status = try await adapter.status()
        XCTAssertEqual(status.state, .notLoggedIn)
        XCTAssertTrue(status.detail.contains("扫码"))
    }

    func testStatusLoggedIn() async throws {
        let store = MemoryCredentialStore()
        let initial = Data(#"{"access_token":"a","refresh_token":"r","token_type":"Bearer","nickname":"User"}"#.utf8)
        try store.set(initial, for: "pan123")
        let profile = Data(#"{"data":{"nickname":"User"}}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, profile)], store: store)
        let status = try await adapter.status()
        XCTAssertEqual(status.state, FishDriveStatus.State.loggedIn)
        XCTAssertEqual(status.displayName, "User")
    }

    func testThreadOptions() {
        let (adapter, _) = makeAdapter(responses: [], store: MemoryCredentialStore())
        XCTAssertEqual(adapter.threadOptions, FishThreadOption.all)
        adapter.setThread("vip")
        XCTAssertEqual(adapter.currentThread(), "vip")
    }
}

// MARK: - 注册表测试

final class Pan123RegistryTests: XCTestCase {
    func testPan123RoutesToFullLifecycleService() {
        let service = FishDriveRegistry.service(for: "pan123")
        XCTAssertTrue(service.supportsScanLogin)
        XCTAssertEqual(service.displayName, "123网盘")
        XCTAssertTrue(service.protocolEvidence.contains("完整"))
    }
}
