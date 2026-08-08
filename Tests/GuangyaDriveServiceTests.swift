import XCTest
@testable import OK4KiOS

final class GuangyaDriveServiceTests: XCTestCase {
    func testMyFilesUsesDynamicAuthorizationAndAndroidPaging() async throws {
        let body = Data(#"{"data":{"list":[{"fileId":"folder","fileName":"Dir","resType":2,"unknown":1},{"id":"video","name":"Movie.mp4","fileType":1,"size":99}]}}"#.utf8)
        let client = GuangyaMockHTTPClient(responses: [(200, body)])
        let service = GuangyaDriveService(client: client, authorizationProvider: StaticGuangyaAuthorization())
        let files = try await service.myFiles(parentID: "root", page: 2)
        XCTAssertEqual(files.map(\.id), ["folder", "video"])
        XCTAssertTrue(files[0].isFolder)
        XCTAssertEqual(files[1].size, 99)
        let request = client.requests[0]
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer dynamic")
        let requestBody = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(requestBody["page"] as? Int, 1)
        XCTAssertEqual(requestBody["pageSize"] as? Int, 50)
        XCTAssertEqual(requestBody["parentId"] as? String, "root")
    }

    func testShareAccessTokenFallsBackOn404WithoutAccountAuthorization() async throws {
        let client = GuangyaMockHTTPClient(responses: [(404, Data(#"{}"#.utf8)), (200, Data(#"{"data":{"access_token":"share-token"}}"#.utf8))])
        let service = GuangyaDriveService(client: client, authorizationProvider: StaticGuangyaAuthorization())
        XCTAssertEqual(try await service.shareAccessToken(shareID: "share", code: "code"), "share-token")
        XCTAssertEqual(client.requests.map { $0.url!.path }, ["/userres/v1/get_share_access_token", "/nd.bizuserres.s/v1/get_share_access_token"])
        XCTAssertNil(client.requests[0].value(forHTTPHeaderField: "Authorization"))
    }

    func testRestoreAndTaskSuccessProtocol() async throws {
        let client = GuangyaMockHTTPClient(responses: [
            (200, Data(#"{"data":{"taskId":"task"}}"#.utf8)),
            (200, Data(#"{"data":{"status":"success"}}"#.utf8))
        ])
        let service = GuangyaDriveService(client: client, authorizationProvider: StaticGuangyaAuthorization())
        let task = try await service.restore(fileIDs: ["file"], shareAccessToken: "share-token", parentID: "target")
        XCTAssertEqual(task, "task")
        try await service.waitForTask(try XCTUnwrap(task))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(client.requests[0].httpBody)) as? [String: Any])
        XCTAssertEqual(body["fileIds"] as? [String], ["file"])
        XCTAssertEqual(body["accessToken"] as? String, "share-token")
        XCTAssertEqual(body["parentId"] as? String, "target")
    }

    func testPlaybackExtractsCompatibleURLAndReturnsAndroidHeaders() async throws {
        let client = GuangyaMockHTTPClient(responses: [(200, Data(#"{"data":{"signedUrl":"https://example.com/video.m3u8"}}"#.utf8))])
        let playback = try await GuangyaDriveService(client: client, authorizationProvider: StaticGuangyaAuthorization()).myPlayback(fileID: "file")
        XCTAssertEqual(playback.url.absoluteString, "https://example.com/video.m3u8")
        XCTAssertEqual(playback.headers["Referer"], "https://www.guangyapan.com/")
        XCTAssertNotNil(playback.headers["User-Agent"])
        XCTAssertEqual(client.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer dynamic")
    }
}

private struct StaticGuangyaAuthorization: GuangyaAuthorizationProviding {
    func authorizationHeader() async throws -> String { "Bearer dynamic" }
}
