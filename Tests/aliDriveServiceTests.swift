import XCTest
@testable import OK4KiOS

// MARK: - Mock HTTP 客户端

final class AliMockHTTPClient: AliHTTPClientProtocol {
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
        let (status, data) = responses[index]
        index += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

// MARK: - 内存凭据存储

final class AliMemoryCredentialStore: FishCredentialStore {
    private var storage: [String: Data] = [:]

    func data(for key: String) throws -> Data? {
        storage[key]
    }

    func set(_ data: Data, for key: String) throws {
        storage[key] = data
    }

    func remove(_ key: String) throws {
        storage.removeValue(forKey: key)
    }
}

// MARK: - 阿里云盘完整生命周期测试

final class AliDriveAdapterTests: XCTestCase {
    private func makeAdapter(responses: [(Int, Data)], store: AliMemoryCredentialStore) -> (AliDriveServiceAdapter, AliMockHTTPClient) {
        let client = AliMockHTTPClient(responses: responses)
        let auth = AliAuthService(client: client)
        let session = AliSession(store: store, service: auth)
        return (AliDriveServiceAdapter(session: session, auth: auth, threadStore: FishThreadStore(defaults: UserDefaults(suiteName: "test.ali.threads")!)), client)
    }

    func testBeginLoginCreatesSessionFromOAuthResponse() async throws {
        let body = Data(#"{"qrCodeUrl":"https://open.aliyundrive.com/oauth/users/authorize?client_id=10e184c407cb4d8087f9d3b8f1fd2c23&redirect_uri=https://opentoken.xiaoya.pro/callback&scope=user:base,file:all:read,file:all:write&state=","sid":"sid123","expiresIn":300,"interval":3}"#.utf8)
        let (adapter, client) = makeAdapter(responses: [(200, body)], store: AliMemoryCredentialStore())
        let session = try await adapter.beginLogin()
        XCTAssertEqual(session.deviceCode, "sid123")
        XCTAssertTrue(session.qrPayload.contains("open.aliyundrive.com/oauth/users/authorize"))
        XCTAssertEqual(session.expiresIn, 300)
        XCTAssertEqual(session.interval, 3)
        XCTAssertEqual(client.requests[0].url?.absoluteString, "https://open.aliyundrive.com/oauth/users/authorize")
    }

    func testPollPendingThenAuthorizedPersistsCredential() async throws {
        let store = AliMemoryCredentialStore()
        let beginBody = Data(#"{"qrCodeUrl":"https://open.aliyundrive.com/oauth/users/authorize?client_id=10e184c407cb4d8087f9d3b8f1fd2c23&redirect_uri=https://opentoken.xiaoya.pro/callback&scope=user:base,file:all:read,file:all:write&state=","sid":"sid123","expiresIn":300,"interval":3}"#.utf8)
        let pendingBody = Data(#"{"error":"authorization_pending"}"#.utf8)
        let authorizedBody = Data(#"{"authCode":"code123"}"#.utf8)
        let tokenBody = Data(#"{"access_token":"access123","refresh_token":"refresh123","token_type":"Bearer","unknown":{"keep":1}}"#.utf8)
        let profileBody = Data(#"{"name":"User","user_id":"uid123"}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [
            (200, beginBody),
            (400, pendingBody),
            (200, authorizedBody),
            (200, tokenBody),
            (200, profileBody)
        ], store: store)

        let session = try await adapter.beginLogin()
        XCTAssertEqual(session.deviceCode, "sid123")

        let first = try await adapter.poll(session)
        XCTAssertEqual(first, .pending)

        let second = try await adapter.poll(session)
        XCTAssertEqual(second, .authorized)

        let saved = try XCTUnwrap(try store.data(for: "ali"))
        let savedDict = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(savedDict["access_token"] as? String, "access123")
        XCTAssertEqual(savedDict["refresh_token"] as? String, "refresh123")
        XCTAssertEqual(savedDict["name"] as? String, "User")
        // 未知字段无损保留
        let unknown = try XCTUnwrap(savedDict["unknown"] as? [String: Any])
        XCTAssertEqual(unknown["keep"] as? Int, 1)
    }

    func testRefreshUsesRefreshTokenAndPersists() async throws {
        let store = AliMemoryCredentialStore()
        let initial = Data(#"{"access_token":"old","refresh_token":"refresh123","token_type":"Bearer"}"#.utf8)
        try store.set(initial, for: "ali")

        let refreshBody = Data(#"{"access_token":"new","refresh_token":"refresh123","token_type":"Bearer"}"#.utf8)
        let profileBody = Data(#"{"name":"User"}"#.utf8)
        let (adapter, client) = makeAdapter(responses: [(200, refreshBody), (200, profileBody)], store: store)

        try await adapter.refresh()

        XCTAssertEqual(client.requests[0].url?.absoluteString, "https://auth.xiaoya.pro/api/ali_open/refresh")
        let saved = try XCTUnwrap(try store.data(for: "ali"))
        let savedDict = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(savedDict["access_token"] as? String, "new")
    }

    func testLogoutRemovesCredential() async throws {
        let store = AliMemoryCredentialStore()
        try store.set(Data(#"{"access_token":"x"}"#.utf8), for: "ali")
        let (adapter, _) = makeAdapter(responses: [], store: store)
        try await adapter.logout()
        XCTAssertNil(try store.data(for: "ali"))
    }

    func testStatusNotLoggedIn() async throws {
        let store = AliMemoryCredentialStore()
        let (adapter, _) = makeAdapter(responses: [], store: store)
        let status = try await adapter.status()
        XCTAssertEqual(status.state, .notLoggedIn)
    }

    func testStatusLoggedIn() async throws {
        let store = AliMemoryCredentialStore()
        try store.set(Data(#"{"access_token":"x","refresh_token":"r","name":"User"}"#.utf8), for: "ali")
        let profileBody = Data(#"{"name":"User"}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, profileBody)], store: store)
        let status = try await adapter.status()
        XCTAssertEqual(status.state, .loggedIn)
        XCTAssertEqual(status.displayName, "User")
    }
}
