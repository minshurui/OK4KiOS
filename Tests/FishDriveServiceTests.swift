import XCTest
@testable import OK4KiOS

// MARK: - 栏目与 action 分派

final class FishConfigModelsTests: XCTestCase {
    func testTenDriveSectionsExposeAndroidDriveKeys() {
        let expected: [(FishConfigSection, String)] = [
            (.quark, "quark"), (.uc, "uc"), (.tianyi, "tianyi"), (.yidong, "yidong"),
            (.baidu, "baidu"), (.xunlei, "xunlei"), (.pan123, "pan123"), (.pan115, "pan115"),
            (.guangya, "guangya"), (.ali, "ali")
        ]
        for (section, key) in expected {
            XCTAssertEqual(section.driveKey, key, "\(section.title) 应映射到 \(key)")
            XCTAssertTrue(section.isDriveSection)
        }
        for section in [FishConfigSection.console, .system, .poster, .danmaku, .media, .bili] {
            XCTAssertNil(section.driveKey)
            XCTAssertFalse(section.isDriveSection)
        }
    }

    func testActionKindClassifiesAndroidActionIDs() {
        XCTAssertEqual("quark_status".fishConfigActionKind, .status)
        XCTAssertEqual("guangya_login".fishConfigActionKind, .scanLogin)
        XCTAssertEqual("uc_token_scan".fishConfigActionKind, .scanLogin)
        XCTAssertEqual("ali_token".fishConfigActionKind, .other)
        XCTAssertEqual("quark_thread".fishConfigActionKind, .thread)
        XCTAssertEqual("pan115_clean".fishConfigActionKind, .clean)
        XCTAssertEqual("magnet_cloud_help".fishConfigActionKind, .other)
        XCTAssertEqual(FishConfigCatalog.actions(for: .guangya).first { $0.id == "guangya_clean" }?.kind, .clean)
    }
}

// MARK: - 注册表与诚实 pending

final class FishDriveRegistryTests: XCTestCase {
    func testGuangyaRoutesToFullLifecycleService() {
        let service = FishDriveRegistry.service(for: "guangya")
        XCTAssertTrue(service.supportsScanLogin)
        XCTAssertEqual(service.displayName, "光鸭网盘")
    }

    func testUnverifiedDrivesAreHonestAboutPendingProtocol() async throws {
        for key in ["quark", "uc", "tianyi", "yidong", "baidu", "xunlei", "pan123", "pan115", "ali"] {
            let service = FishDriveRegistry.service(for: key)
            XCTAssertFalse(service.supportsScanLogin, "\(key) 未完整取证不得支持扫码")
            XCTAssertFalse(service.protocolEvidence.contains("完整"), "\(key) 不应宣称协议完成")
            let status = try await service.status()
            XCTAssertEqual(status.state, .notLoggedIn)
            do {
                _ = try await service.beginLogin()
                XCTFail("\(key) beginLogin 必须诚实抛错")
            } catch FishDriveError.protocolPending(let reason) {
                XCTAssertTrue(reason.contains(key) || reason.contains(service.displayName))
            }
            do {
                _ = try await service.poll(FishScanSession(qrPayload: "x", deviceCode: "d", expiresIn: 1, interval: 1, openURL: nil))
                XCTFail("\(key) poll 必须诚实抛错")
            } catch FishDriveError.protocolPending { }
            do {
                try await service.refresh()
                XCTFail("\(key) refresh 必须诚实抛错")
            } catch FishDriveError.protocolPending { }
        }
    }

    func testPendingCleanRemovesStoredCredential() async throws {
        let store = MemoryCredentialStore()
        try store.set(Data(#"{"access_token":"legacy"}"#.utf8), for: "quark")
        let service = PendingFishDriveService(driveKey: "quark", store: store)
        try await service.logout()
        XCTAssertNil(try store.data(for: "quark"))
    }

    func testPendingStatusReportsStoredCredentialWithoutNetworkClaims() async throws {
        let store = MemoryCredentialStore()
        try store.set(Data(#"{"access_token":"legacy"}"#.utf8), for: "quark")
        let service = PendingFishDriveService(driveKey: "quark", store: store)
        let status = try await service.status()
        XCTAssertEqual(status.state, .stale)
        XCTAssertTrue(status.detail.contains("登录协议未完成"))
    }
}

// MARK: - 光鸭完整生命周期（创建/轮询/授权/刷新/退出）

final class GuangyaDriveAdapterTests: XCTestCase {
    private func makeAdapter(responses: [(Int, Data)], store: MemoryCredentialStore) -> (GuangyaDriveServiceAdapter, GuangyaMockHTTPClient) {
        let client = GuangyaMockHTTPClient(responses: responses)
        let auth = GuangyaAuthService(client: client)
        let session = GuangyaSession(store: store, service: auth)
        return (GuangyaDriveServiceAdapter(session: session, auth: auth, threadStore: FishThreadStore(defaults: UserDefaults(suiteName: "test.guangya.threads")!)), client)
    }

    func testBeginLoginCreatesSessionFromDeviceCodeResponse() async throws {
        let body = Data(#"{"device_code":"code","expires_in":180,"interval":3,"verification_uri_complete":"https://account.guangyapan.com/scan"}"#.utf8)
        let (adapter, client) = makeAdapter(responses: [(200, body)], store: MemoryCredentialStore())
        let session = try await adapter.beginLogin()
        XCTAssertEqual(session.deviceCode, "code")
        XCTAssertEqual(session.qrPayload, "https://account.guangyapan.com/scan")
        XCTAssertEqual(session.expiresIn, 180)
        XCTAssertEqual(session.interval, 3)
        XCTAssertEqual(client.requests[0].url?.absoluteString, "https://account.guangyapan.com/v1/auth/device/code")
    }

    func testPollPendingThenAuthorizedPersistsCredential() async throws {
        let store = MemoryCredentialStore()
        let deviceCode = Data(#"{"device_code":"code","expires_in":180,"interval":3,"verification_uri_complete":"https://account.guangyapan.com/scan"}"#.utf8)
        let pending = Data(#"{"error":"authorization_pending","error_description":"pending"}"#.utf8)
        let authorized = Data(#"{"data":{"access_token":"a","refresh_token":"r","token_type":"Bearer"},"unknown":{"keep":1}}"#.utf8)
        let profile = Data(#"{"data":{"nickname":"User"}}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, deviceCode), (400, pending), (200, authorized), (200, profile)], store: store)
        let session = try await adapter.beginLogin()
        XCTAssertEqual(session.deviceCode, "code")
        let first = try await adapter.poll(session)
        XCTAssertEqual(first, .pending)
        let second = try await adapter.poll(session)
        XCTAssertEqual(second, .authorized)
        let saved = try XCTUnwrap(try store.data(for: "guangya"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual((root["data"] as? [String: Any])?["access_token"] as? String, "a")
        // 未知字段深合并保留在响应原层级（根层），与 Android 动态 JSON 无损要求一致。
        XCTAssertNotNil(root["unknown"])
        XCTAssertEqual((root["unknown"] as? [String: Any])?["keep"] as? Int, 1)
    }

    func testPollAuthorizedDirectlyPersistsAndReportsLoggedInStatus() async throws {
        let store = MemoryCredentialStore()
        let deviceCode = Data(#"{"device_code":"code","expires_in":180,"interval":3,"verification_uri_complete":"https://account.guangyapan.com/scan"}"#.utf8)
        let authorized = Data(#"{"access_token":"a","refresh_token":"r"}"#.utf8)
        let profile = Data(#"{"data":{"nickname":"User"}}"#.utf8)
        let (adapter, _) = makeAdapter(responses: [(200, deviceCode), (200, authorized), (200, profile)], store: store)
        let session = try await adapter.beginLogin()
        let result = try await adapter.poll(session)
        XCTAssertEqual(result, .authorized)
        XCTAssertNotNil(try store.data(for: "guangya"))
    }

    func testRefreshValidatesRefreshesAndPersists() async throws {
        let store = MemoryCredentialStore()
        try store.set(Data(#"{"access_token":"expired","refresh_token":"refresh","unknown":{"keep":true}}"#.utf8), for: "guangya")
        let responses = [
            (401, Data(#"{"error":"expired"}"#.utf8)),
            (200, Data(#"{"data":{"access_token":"new-access"}}"#.utf8)),
            (200, Data(#"{"data":{"nickname":"User"}}"#.utf8))
        ]
        let (adapter, client) = makeAdapter(responses: responses, store: store)
        try await adapter.refresh()
        let persisted = try XCTUnwrap(try store.data(for: "guangya"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: persisted) as? [String: Any])
        XCTAssertEqual((root["data"] as? [String: Any])?["access_token"] as? String, "new-access")
        XCTAssertNotNil(root["unknown"])
        XCTAssertEqual(client.requests[0].url?.absoluteString, "https://account.guangyapan.com/v1/user/me")
        XCTAssertEqual(client.requests[1].url?.absoluteString, "https://account.guangyapan.com/v1/auth/token")
    }

    func testLogoutRemovesKeychainCredential() async throws {
        let store = MemoryCredentialStore()
        try store.set(Data(#"{"access_token":"a"}"#.utf8), for: "guangya")
        let (adapter, _) = makeAdapter(responses: [], store: store)
        try await adapter.logout()
        XCTAssertNil(try store.data(for: "guangya"))
    }

    func testStatusNotLoggedInDoesNotThrow() async throws {
        let (adapter, _) = makeAdapter(responses: [], store: MemoryCredentialStore())
        let status = try await adapter.status()
        XCTAssertEqual(status.state, .notLoggedIn)
        XCTAssertTrue(status.detail.contains("扫码"))
    }
}

// MARK: - 网关

final class FishConfigGatewayTests: XCTestCase {
    func testStatusActionReturnsHonestDetail() async throws {
        // Keychain 在 CI 模拟器无 entitlement：注入 memory-store quark 适配器后走网关。
        let store = MemoryCredentialStore()
        let client = QuarkMockHTTPClient(responses: [])
        let auth = QuarkAuthService(client: client)
        let session = QuarkSession(store: store, service: auth)
        FishDriveRegistry.override["quark"] = QuarkDriveServiceAdapter(session: session, auth: auth, threadStore: FishThreadStore(defaults: UserDefaults(suiteName: "test.gw.quark")!))
        defer { FishDriveRegistry.override["quark"] = nil }
        let result = try await FishConfigGateway.perform(actionID: "quark_status", section: .quark)
        XCTAssertEqual(result.status?.state, .notLoggedIn)
        XCTAssertTrue(result.message.contains("未登录"))
    }

    func testScanLoginForUnverifiedDriveThrowsPending() async throws {
        // 移动云盘扫码协议未取证，扫码动作必须诚实抛错。
        do {
            _ = try await FishConfigGateway.perform(actionID: "yidong_scan", section: .yidong)
            XCTFail("未取证的扫码必须抛错")
        } catch FishDriveError.protocolPending { }
    }

    func testCleanActionOnGuangyaIsIdempotent() async throws {
        // Keychain 在 CI 模拟器无 entitlement，注入 memory-store 适配器后再走网关。
        let store = MemoryCredentialStore()
        let client = GuangyaMockHTTPClient(responses: [])
        let auth = GuangyaAuthService(client: client)
        let session = GuangyaSession(store: store, service: auth)
        FishDriveRegistry.override["guangya"] = GuangyaDriveServiceAdapter(session: session, auth: auth, threadStore: FishThreadStore(defaults: UserDefaults(suiteName: "test.clean.guangya")!))
        defer { FishDriveRegistry.override["guangya"] = nil }
        let result = try await FishConfigGateway.perform(actionID: "guangya_clean", section: .guangya)
        XCTAssertTrue(result.message.contains("已清除"))
    }

    func testThreadActionReportsCurrentPreference() async throws {
        // 网关经 registry 创建服务，线程偏好读共享 store；测试直接写共享 store 并复原。
        let shared = FishThreadStore.shared
        let previous = shared.value(for: "quark")
        shared.set("vip", for: "quark")
        defer { shared.set(previous, for: "quark") }
        let result = try await FishConfigGateway.perform(actionID: "quark_thread", section: .quark)
        XCTAssertEqual(result.thread, "vip")
        XCTAssertTrue(result.message.contains("会员线程"))
    }

    func testNonDriveSectionKeepsHonestPendingMessage() async throws {
        let result = try await FishConfigGateway.perform(actionID: "danmu_toggle", section: .danmaku)
        XCTAssertTrue(result.message.contains("仍在移植"))
    }
}

// MARK: - 线程偏好

final class FishThreadStoreTests: XCTestCase {
    private func makeStore() -> FishThreadStore {
        FishThreadStore(defaults: UserDefaults(suiteName: "test.fish.threads")!)
    }

    func testDefaultsToNormalAndPersistsSelection() {
        let store = makeStore()
        XCTAssertEqual(store.value(for: "quark"), FishThreadOption.normal.id)
        store.set(FishThreadOption.vip.id, for: "quark")
        XCTAssertEqual(store.value(for: "quark"), FishThreadOption.vip.id)
        let reopened = makeStore()
        XCTAssertEqual(reopened.value(for: "quark"), FishThreadOption.vip.id)
    }
}

// MARK: - 设置中心永不作为点播执行

final class FishConfigSiteGuardTests: XCTestCase {
    func testFactoryNeverBuildsVODServiceForFishConfig() async {
        let site = TVBoxSite(key: "FishConfig", name: "🍼设置中心", type: 3, api: "csp_FishConfig")
        XCTAssertFalse(site.canRunNatively, "设置中心不是原生点播站点")
        XCTAssertTrue(site.isFeatureCenter)

        let settings = AppSettings.shared
        let previousSite = settings.selectedSite
        let previousGateway = settings.spiderGateway
        defer {
            settings.selectedSite = previousSite
            settings.spiderGateway = previousGateway
        }
        settings.selectedSite = site
        settings.spiderGateway = "http://127.0.0.1:9980"

        let service = VodServiceFactory.current(settings: settings)
        do {
            _ = try await service.home(page: 1)
            XCTFail("FishConfig 不得作为点播站点执行")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("设置中心"))
        }
    }
}

// MARK: - 工具

final class MemoryCredentialStore: FishCredentialStore {
    private var values: [String: Data] = [:]
    func data(for account: String) throws -> Data? { values[account] }
    func set(_ data: Data, for account: String) throws { values[account] = data }
    func remove(_ account: String) throws { values.removeValue(forKey: account) }
}
