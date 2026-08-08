import XCTest
@testable import OK4KiOS

final class GuangyaSessionTests: XCTestCase {
    func testFinishLoginPersistsTokenEvenWhenProfileFails() async throws {
        let store = MemoryFishCredentialStore()
        let client = GuangyaMockHTTPClient(responses: [(500, Data(#"{"error":"profile failed"}"#.utf8))])
        let session = GuangyaSession(store: store, service: GuangyaAuthService(client: client))
        let credential = try GuangyaCredential(responseData: Data(#"{"access_token":"a","refresh_token":"r"}"#.utf8))
        let saved = try await session.finishLogin(credential)
        XCTAssertEqual(saved.accessToken, "a")
        XCTAssertNotNil(try store.data(for: "guangya"))
    }

    func testValidatedCredentialRefreshesAfterProfileFailureAndPersistsProfile() async throws {
        let store = MemoryFishCredentialStore()
        try store.set(Data(#"{"access_token":"expired","refresh_token":"refresh","unknown":{"keep":true}}"#.utf8), for: "guangya")
        let client = GuangyaMockHTTPClient(responses: [
            (401, Data(#"{"error":"expired"}"#.utf8)),
            (200, Data(#"{"data":{"access_token":"new-access"}}"#.utf8)),
            (200, Data(#"{"data":{"nickname":"User"}}"#.utf8))
        ])
        let session = GuangyaSession(store: store, service: GuangyaAuthService(client: client))
        let value = try await session.validatedCredential()
        XCTAssertEqual(value.accessToken, "new-access")
        XCTAssertEqual(value.refreshToken, "refresh")
        XCTAssertEqual(value.name, "User")
        let persisted = try XCTUnwrap(try store.data(for: "guangya"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: persisted) as? [String: Any])
        XCTAssertNotNil(root["unknown"])
    }

    func testLogoutRemovesCredential() async throws {
        let store = MemoryFishCredentialStore()
        try store.set(Data(#"{"access_token":"a"}"#.utf8), for: "guangya")
        let session = GuangyaSession(store: store)
        try await session.logout()
        XCTAssertNil(try store.data(for: "guangya"))
    }
}

private final class MemoryFishCredentialStore: FishCredentialStore {
    private var values: [String: Data] = [:]
    func data(for account: String) throws -> Data? { values[account] }
    func set(_ data: Data, for account: String) throws { values[account] = data }
    func remove(_ account: String) throws { values.removeValue(forKey: account) }
}
