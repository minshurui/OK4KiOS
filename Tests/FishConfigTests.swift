import XCTest
@testable import OK4KiOS

final class FishConfigTests: XCTestCase {
    func testAndroidSectionOrderAndIDsArePreserved() {
        XCTAssertEqual(FishConfigSection.allCases.map(\.rawValue), ["10", "5", "15", "7", "16", "13", "1", "2", "3", "14", "6", "8", "11", "9", "12", "4"])
    }

    func testDriveActionsUseAndroidActionIDs() {
        XCTAssertEqual(FishConfigCatalog.actions(for: .guangya).map(\.id), [
            "guangya_status", "guangya_login", "guangya_community_cookie", "guangya_magnet_switch", "magnet_cloud_help", "guangya_clean"
        ])
        XCTAssertTrue(FishConfigCatalog.actions(for: .uc).contains { $0.id == "uc_token_scan" })
        XCTAssertTrue(FishConfigCatalog.actions(for: .ali).contains { $0.id == "ali_token" })
    }

    func testGuangyaCredentialPreservesRawResponse() throws {
        let raw = Data(#"{"data":{"access_token":"a","refresh_token":"r","token_type":"Bearer","unknown":{"keep":true}}}"#.utf8)
        let value = try GuangyaCredential(responseData: raw)
        XCTAssertEqual(value.accessToken, "a")
        XCTAssertEqual(value.refreshToken, "r")
        XCTAssertEqual(value.tokenType, "Bearer")
        let preserved = try XCTUnwrap(JSONSerialization.jsonObject(with: value.raw) as? [String: Any])
        XCTAssertNotNil((preserved["data"] as? [String: Any])?["unknown"])
    }
}
