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
        let requestBody = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: String])
        XCTAssertEqual(object["client_id"], GuangyaAuthService.clientID)
        XCTAssertEqual(object["scope"], "user")
    }

    func testPollTreatsRealPendingResponseAsPending() async throws {
        let body = Data(#"{"error":"authorization_pending","error_code":4050,"error_description":"Precondition Required"}"#.utf8)
        let client = GuangyaMockHTTPClient(responses: [(400, body)])
        let result = try await GuangyaAuthService(client: client).poll(deviceCode: "code")
        XCTAssertEqual(result, .pending)
    }

    func testPollReturnsAndPreservesCompleteCredentialJSON() async throws {
        let body = Data(#"{"data":{"access_token":"a","refresh_token":"r","token_type":"Bearer","unknown":"preserved"}}"#.utf8)
        let client = GuangyaMockHTTPClient(responses: [(200, body)])
        let result = try await GuangyaAuthService(client: client).poll(deviceCode: "code")
        guard case .authorized(let credential) = result else { return XCTFail("expected authorization") }
        XCTAssertEqual(credential.accessToken, "a")
        XCTAssertEqual(credential.raw, body)
    }
}

private final class GuangyaMockHTTPClient: GuangyaHTTPClientProtocol {
    private var responses: [(Int, Data)]
    private(set) var requests: [URLRequest] = []

    init(responses: [(Int, Data)]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        return (response.1, HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: nil, headerFields: nil)!)
    }
}
