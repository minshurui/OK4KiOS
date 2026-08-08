import XCTest
@testable import OK4KiOS

// MARK: - 天翼云盘 Mock HTTP 客户端

final class TianyiMockHTTPClient: TianyiHTTPClientProtocol {
    var requests: [URLRequest] = []
    private let responses: [(Int, Data)]
    private var index = 0

    init(responses: [(Int, Data)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, data) = responses[min(index, responses.count - 1)]
        index += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

// MARK: - 天翼云盘适配器测试

final class TianyiDriveServiceTests: XCTestCase {
    private func makeAdapter(responses: [(Int, Data)], store: MemoryCredentialStore) -> (TianyiDriveServiceAdapter, TianyiMockHTTPClient) {
        let client = TianyiMockHTTPClient(responses: responses)
        let auth = TianyiAuthService(client: client)
        let session = TianyiSession(store: store, service: auth)
        return (TianyiDriveServiceAdapter(session: session, auth: auth, threadStore: FishThreadStore(defaults: UserDefaults(suiteName: "test.tianyi.threads")!)), client)
    }

    func testRegistryRoutesTianyiToAdapter() {
        let service = FishDriveRegistry.service(for: "tianyi")
        XCTAssertTrue(service is TianyiDriveServiceAdapter)
        XCTAssertEqual(service.driveKey, "tianyi")
        XCTAssertEqual(service.displayName, "天翼云盘")
        XCTAssertFalse(service.supportsScanLogin)
    }

    func testBeginLoginThrowsProtocolPending() async throws {
        let store = MemoryCredentialStore()
        let (adapter, _) = makeAdapter(responses: [], store: store)
        do {
            _ = try await adapter.beginLogin()
            XCTFail("beginLogin 必须诚实抛错")
        } catch FishDriveError.protocolPending(let reason) {
            XCTAssertTrue(reason.contains("天翼云盘"))
        }
    }

    func testPollThrowsProtocolPending() async throws {
        let store = MemoryCredentialStore()
        let (adapter, _) = makeAdapter(responses: [], store: store)
        let session = FishScanSession(qrPayload: "x", deviceCode: "d", expiresIn: 1, interval: 1, openURL: nil)
        do {
            _ = try await adapter.poll(session)
            XCTFail("poll 必须诚实抛错")
        } catch FishDriveError.protocolPending { }
    }

    func testStatusNotLoggedIn() async throws {
        let store = MemoryCredentialStore()
        let (adapter, _) = makeAdapter(responses: [], store: store)
        let status = try await adapter.status()
        XCTAssertEqual(status.state, .notLoggedIn)
        XCTAssertTrue(status.detail.contains("扫码"))
    }

    func testStatusLoggedInWithStoredCredential() async throws {
        let store = MemoryCredentialStore()
        let credentialData = Data(#"{"session_key":"sk","session_secret":"ss","userNickName":"测试用户"}"#.utf8)
        try store.set(credentialData, for: "tianyi")
        let profile = Data(#"{"userNickName":"测试用户","userId":"123"}"#.utf8)
        let (adapter, client) = makeAdapter(responses: [(200, profile)], store: store)
        let status = try await adapter.status()
        XCTAssertEqual(status.state, .loggedIn)
        XCTAssertEqual(status.displayName, "测试用户")
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertTrue(client.requests[0].url?.absoluteString.contains("/api/portal/v2/getUserBriefInfo.action") ?? false)
    }

    func testLogoutRemovesCredential() async throws {
        let store = MemoryCredentialStore()
        let credentialData = Data(#"{"session_key":"sk","session_secret":"ss"}"#.utf8)
        try store.set(credentialData, for: "tianyi")
        let (adapter, _) = makeAdapter(responses: [], store: store)
        try await adapter.logout()
        XCTAssertNil(try store.data(for: "tianyi"))
    }

    func testThreadPreference() {
        let store = MemoryCredentialStore()
        let (adapter, _) = makeAdapter(responses: [], store: store)
        XCTAssertEqual(adapter.currentThread(), "normal")
        adapter.setThread("vip")
        XCTAssertEqual(adapter.currentThread(), "vip")
    }
}
