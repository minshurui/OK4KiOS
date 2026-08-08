import XCTest
@testable import OK4KiOS

// MARK: - Mock HTTP Client

final class QuarkMockHTTPClient: QuarkHTTPClientProtocol {
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

// MARK: - 夸克完整生命周期（创建/轮询/授权/刷新/退出）

final class QuarkDriveAdapterTests: XCTestCase {
    private func makeAdapter(responses: [(Int, Data)], store: MemoryCredentialStore) -> (QuarkDriveServiceAdapter, QuarkMockHTTPClient) {
        let client = QuarkMockHTTPClient(responses: responses)
        let auth = QuarkAuthService(client: client)
        let session = QuarkSession(store: store, service: auth)
        return (QuarkDriveServiceAdapter(session: session, auth: auth, threadStore: FishThreadStore(defaults: UserDefaults(suiteName: "test.quark.threads")!)), client)
    }

    func testBeginLoginCreatesSessionFromQrCodeResponse() async throws {
        let body = Data(#"{"data":{"qr_code":"https://uop.quark.cn/cas/qr?token=abc","qr_token":"device123","expires_in":180,"interval":3}}"#.utf8)
        let (adapter, client) = makeAdapter(responses: [(200, body)], store: MemoryCredentialStore())
        let session = try await adapter.beginLogin()
        XCTAssertEqual(session.deviceCode, "device123")
        XCTAssertEqual(session.qrPayload, "https://uop.quark.cn/cas/qr?token=abc")
        XCTAssertEqual(session.expiresIn, 180)
        XCTAssertEqual(session.interval, 3)
        XCTAssertTrue(client.requests[0].url?.absoluteString.contains("getTokenForQrcodeLogin") ?? false)
    }

    func testPollPendingThenAuthorizedPersistsCredential() async throws {
        let store = MemoryCredentialStore()
        let qrCode = Data(#"{"data":{"qr_code":"https://uop.quark.cn/cas/qr?token=abc","qr_token":"device123","expires_in":180,"interval":3}}"#.utf8)
        let pending = Data(#"{"data":{"status":"pending"}}"#.utf8)
        let authorized = Data(#"{"data":{"status":"confirmed","access_token":"a","refresh_token":"r","token_type":"Bearer","nickname":"User"},"unknown":{"keep":1}}"#.utf8)
        let profile = Data(#"{"data":{"nickname":"User","phone":"13800138000"}}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, qrCode), (200, pending), (200, authorized), (200, profile)], store: store)
        let session = try await adapter.beginLogin()
        XCTAssertEqual(session.deviceCode, "device123")
        let first = try await adapter.poll(session)
        XCTAssertEqual(first, .pending)
        let second = try await adapter.poll(session)
        XCTAssertEqual(second, .authorized)
        let saved = try XCTUnwrap(try store.data(for: "quark"))
        let credential = try QuarkCredential(responseData: saved)
        XCTAssertEqual(credential.accessToken, "a")
        XCTAssertEqual(credential.refreshToken, "r")
        XCTAssertEqual(credential.displayName, "User")
    }

    func testStatusNotLoggedIn() async throws {
        let store = MemoryCredentialStore()
        let (adapter, _) = makeAdapter(responses: [], store: store)
        let status = try await adapter.status()
        XCTAssertEqual(status.state, .notLoggedIn)
        XCTAssertTrue(status.detail.contains("扫码"))
    }

    func testStatusLoggedIn() async throws {
        let store = MemoryCredentialStore()
        let credential = try QuarkCredential(responseData: Data(#"{"data":{"access_token":"a","refresh_token":"r","nickname":"User"}}"#.utf8))
        try store.set(credential.raw, for: "quark")
        let profile = Data(#"{"data":{"nickname":"User","phone":"13800138000"}}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, profile)], store: store)
        let status = try await adapter.status()
        XCTAssertEqual(status.state, .loggedIn)
        XCTAssertEqual(status.displayName, "User")
    }

    func testLogoutRemovesCredential() async throws {
        let store = MemoryCredentialStore()
        let credential = try QuarkCredential(responseData: Data(#"{"data":{"access_token":"a","refresh_token":"r"}}"#.utf8))
        try store.set(credential.raw, for: "quark")
        let (adapter, _) = makeAdapter(responses: [], store: store)
        try await adapter.logout()
        XCTAssertNil(try store.data(for: "quark"))
    }

    func testRefreshWithMissingRefreshTokenThrows() async throws {
        let store = MemoryCredentialStore()
        let credential = try QuarkCredential(responseData: Data(#"{"data":{"access_token":"a"}}"#.utf8))
        try store.set(credential.raw, for: "quark")
        let (adapter, _) = makeAdapter(responses: [], store: store)
        do {
            try await adapter.refresh()
            XCTFail("refresh 必须抛错")
        } catch FishDriveError.protocolPending(let reason) {
            XCTAssertTrue(reason.contains("refresh"))
        } catch {
            XCTFail("应抛 protocolPending，实际 \(error)")
        }
    }

    func testThreadOptions() async throws {
        let store = MemoryCredentialStore()
        let (adapter, _) = makeAdapter(responses: [], store: store)
        XCTAssertEqual(adapter.threadOptions.count, 2)
        XCTAssertEqual(adapter.currentThread(), "normal")
        adapter.setThread("vip")
        XCTAssertEqual(adapter.currentThread(), "vip")
    }
}
