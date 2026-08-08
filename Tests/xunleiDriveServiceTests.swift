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

    func testBeginLoginThrowsProtocolPending() async throws {
        let store = MemoryCredentialStore()
        let (adapter, _) = makeAdapter(responses: [], store: store)
        do {
            _ = try await adapter.beginLogin()
            XCTFail("beginLogin 必须诚实抛错")
        } catch FishDriveError.protocolPending(let reason) {
            XCTAssertTrue(reason.contains("迅雷"))
        }
    }

    func testPollThrowsProtocolPending() async throws {
        let store = MemoryCredentialStore()
        let (adapter, _) = makeAdapter(responses: [], store: store)
        let session = FishScanSession(qrPayload: "x", deviceCode: "d", expiresIn: 1, interval: 1, openURL: nil)
        do {
            _ = try await adapter.poll(session)
            XCTFail("poll 必须诚实抛错")
        } catch FishDriveError.protocolPending(let reason) {
            XCTAssertTrue(reason.contains("迅雷"))
        }
    }

    func testRefreshWithoutCredentialThrowsNotLoggedIn() async throws {
        let store = MemoryCredentialStore()
        let (adapter, _) = makeAdapter(responses: [], store: store)
        do {
            try await adapter.refresh()
            XCTFail("无凭据 refresh 必须抛 notLoggedIn")
        } catch FishDriveError.notLoggedIn { }
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
        XCTAssertFalse(service.supportsScanLogin)
        XCTAssertTrue(service.protocolEvidence.contains("端点已取证"))
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
