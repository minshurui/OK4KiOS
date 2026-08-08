import XCTest
@testable import OK4KiOS

final class GuangyaAuthServiceTests: XCTestCase {
    func testBeginReadsAndroidCompatibleDeviceCodeResponse() async throws {
        let body = Data(#"{"device_code":"code","expires_in":120,"interval":2,"verification_url":"https://example.com/base","verification_uri_complete":"https://example.com/scan?user_code=1"}"#.utf8)
        let client = GuangyaMockHTTPClient(responses: [(200, body)])
        let value = try await GuangyaAuthService(client: client).begin()
        XCTAssertEqual(value.deviceCode, "code")
        XCTAssertEqual(value.verificationURL.absoluteString, "https://example.com/scan?user_code=1")
        XCTAssertEqual(value.expiresIn, 120)
        XCTAssertEqual(value.interval, 2)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://account.guangyapan.com/v1/auth/device/code")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(object["client_id"], GuangyaAuthService.clientID)
        XCTAssertEqual(object["scope"], "user")
    }

    func testPollTreatsRealPendingResponseAsPending() async throws {
        let body = Data(#"{"error":"authorization_pending","error_code":4050,"error_description":"Precondition Required"}"#.utf8)
        let client = GuangyaMockHTTPClient(responses: [(400, body)])
        let result = try await GuangyaAuthService(client: client).poll(deviceCode: "code")
        XCTAssertEqual(result, .pending)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(client.requests[0].httpBody)) as? [String: String])
        XCTAssertEqual(object["grant_type"], "urn:ietf:params:oauth:grant-type:device_code")
        XCTAssertEqual(object["device_code"], "code")
    }

    func testPollPreservesCompleteCredentialJSONAndAliases() async throws {
        let body = Data(#"{"data":{"access_token":"a","refresh_token":"r","token_type":"Bearer","unknown":{"nested":1}},"trace":"keep"}"#.utf8)
        let result = try await GuangyaAuthService(client: GuangyaMockHTTPClient(responses: [(200, body)])).poll(deviceCode: "code")
        guard case .authorized(let credential) = result else { return XCTFail("expected authorization") }
        XCTAssertEqual(credential.accessToken, "a")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: credential.raw) as? [String: Any])
        XCTAssertEqual(object["trace"] as? String, "keep")
        XCTAssertNotNil((object["data"] as? [String: Any])?["unknown"])
    }

    func testRefreshUsesProtocolAndRetainsMissingRefreshAndUnknownFields() async throws {
        let stored = try GuangyaCredential(responseData: Data(#"{"access_token":"old-a","refresh_token":"old-r","token_type":"Bearer","unknown_root":{"keep":true},"data":{"old_nested":1}}"#.utf8))
        let response = Data(#"{"data":{"accessToken":"new-a","new_nested":2},"new_root":"keep"}"#.utf8)
        let client = GuangyaMockHTTPClient(responses: [(200, response)])
        let refreshed = try await GuangyaAuthService(client: client).refresh(stored)
        XCTAssertEqual(refreshed.accessToken, "new-a")
        XCTAssertEqual(refreshed.refreshToken, "old-r")
        let request = client.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://account.guangyapan.com/v1/auth/token")
        let requestBody = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(requestBody["grant_type"], "refresh_token")
        XCTAssertEqual(requestBody["refresh_token"], "old-r")
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: refreshed.raw) as? [String: Any])
        XCTAssertNotNil(raw["unknown_root"])
        XCTAssertEqual(raw["new_root"] as? String, "keep")
        let data = try XCTUnwrap(raw["data"] as? [String: Any])
        XCTAssertEqual(data["old_nested"] as? Int, 1)
        XCTAssertEqual(data["new_nested"] as? Int, 2)
    }

    func testProfileSendsAuthorizationAndMergesUserAliases() async throws {
        let stored = try GuangyaCredential(responseData: Data(#"{"access_token":"a","refresh_token":"r","token_type":"Bearer","token_unknown":1}"#.utf8))
        let response = Data(#"{"data":{"sub":"s","nickname":"User","avatar":"https://example.com/a.png","phone_number":"123"},"profile_unknown":{"keep":true}}"#.utf8)
        let client = GuangyaMockHTTPClient(responses: [(200, response)])
        let profiled = try await GuangyaAuthService(client: client).profile(for: stored)
        XCTAssertEqual(client.requests[0].url?.absoluteString, "https://account.guangyapan.com/v1/user/me")
        XCTAssertEqual(client.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer a")
        XCTAssertEqual(profiled.subject, "s")
        XCTAssertEqual(profiled.name, "User")
        XCTAssertEqual(profiled.picture, "https://example.com/a.png")
        XCTAssertEqual(profiled.phone, "123")
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: profiled.raw) as? [String: Any])
        XCTAssertEqual(raw["token_unknown"] as? Int, 1)
        XCTAssertNotNil(raw["profile_unknown"])
    }

    func testRefreshWithoutRefreshTokenHasExplicitError() async throws {
        let stored = try GuangyaCredential(responseData: Data(#"{"access_token":"a"}"#.utf8))
        do {
            _ = try await GuangyaAuthService(client: GuangyaMockHTTPClient(responses: [])).refresh(stored)
            XCTFail("expected missing refresh token")
        } catch {
            XCTAssertEqual(error as? GuangyaAuthError, .missingRefreshToken)
        }
    }
}

final class GuangyaMockHTTPClient: GuangyaHTTPClientProtocol {
    private var responses: [(Int, Data)]
    private(set) var requests: [URLRequest] = []

    init(responses: [(Int, Data)]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        return (response.1, HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: nil, headerFields: nil)!)
    }
}
