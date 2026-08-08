import XCTest
@testable import OK4KiOS

// MARK: - Mock HTTP Client

final class Pan115MockHTTPClient: Pan115HTTPClientProtocol {
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

// MARK: - 115网盘 完整生命周期测试

final class Pan115DriveAdapterTests: XCTestCase {
    private func makeAdapter(responses: [(Int, Data)], store: MemoryCredentialStore) -> (Pan115DriveServiceAdapter, Pan115MockHTTPClient) {
        let client = Pan115MockHTTPClient(responses: responses)
        let auth = Pan115AuthService(client: client)
        let session = Pan115Session(store: store, service: auth)
        return (Pan115DriveServiceAdapter(session: session, auth: auth, threadStore: FishThreadStore(defaults: UserDefaults(suiteName: "test.pan115.threads")!)), client)
    }

    func testBeginLoginCreatesSessionFromQRCodeResponse() async throws {
        let body = Data(#"{"data":{"qrcode":"https://115.com/s/qrcode123","uid":"12345","time":180,"sign":"abc"}}"#.utf8)
        let (adapter, client) = makeAdapter(responses: [(200, body)], store: MemoryCredentialStore())
        let session = try await adapter.beginLogin()
        XCTAssertEqual(session.deviceCode, "12345")
        XCTAssertEqual(session.qrPayload, "https://115.com/s/qrcode123")
        XCTAssertEqual(session.expiresIn, 180)
        XCTAssertEqual(session.interval, 3)
        XCTAssertEqual(client.requests[0].url?.absoluteString, "https://passportapi.115.com/app/1.0/alipaymini/1.0/login/qrcode/")
    }

    func testPollPendingThenAuthorizedPersistsCredential() async throws {
        let store = MemoryCredentialStore()
        let qrBody = Data(#"{"data":{"qrcode":"https://115.com/s/qrcode123","uid":"12345","time":180,"sign":"abc"}}"#.utf8)
        let pendingBody = Data(#"{"status":false,"message":"pending"}"#.utf8)
        let authorizedBody = Data(#"{"status":true,"data":{"token":"tok123","user_id":"u123","user_name":"User"},"unknown":{"keep":1}}"#.utf8)
        let profileBody = Data(#"{"data":{"user_name":"User"}}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, qrBody), (200, pendingBody), (200, authorizedBody), (200, profileBody)], store: store)
        let session = try await adapter.beginLogin()
        XCTAssertEqual(session.deviceCode, "12345")
        let first = try await adapter.poll(session)
        XCTAssertEqual(first, .pending)
        let second = try await adapter.poll(session)
        XCTAssertEqual(second, .authorized)
        let saved = try XCTUnwrap(try store.data(for: "pan115"))
        let credential = try Pan115Credential(responseData: saved)
        XCTAssertEqual(credential.token, "tok123")
        XCTAssertEqual(credential.userID, "u123")
        XCTAssertEqual(credential.userName, "User")
    }

    func testStatusNotLoggedIn() async throws {
        let store = MemoryCredentialStore()
        let (adapter, _) = makeAdapter(responses: [], store: store)
        let status = try await adapter.status()
        XCTAssertEqual(status.state, .notLoggedIn)
        XCTAssertTrue(status.detail.contains("扫码"))
    }

    func testLogoutRemovesCredential() async throws {
        let store = MemoryCredentialStore()
        try store.set(Data(#"{"token":"tok"}"#.utf8), for: "pan115")
        let (adapter, _) = makeAdapter(responses: [], store: store)
        try await adapter.logout()
        XCTAssertNil(try store.data(for: "pan115"))
    }

    func testRegistryRoutesToFullLifecycleService() {
        let service = FishDriveRegistry.service(for: "pan115")
        XCTAssertTrue(service.supportsScanLogin)
        XCTAssertEqual(service.displayName, "115网盘")
        XCTAssertTrue(service.protocolEvidence.contains("完整"))
    }
}
