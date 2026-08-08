import Foundation

/// 移动云盘适配器：扫码登录协议未完整取证（诚实 pending），凭证导入（Authorization/Cookie）、
/// 状态、清除、线程为真实实现。凭据经 FishCredentialStore 持久化。
struct YiDongDriveServiceAdapter: FishDriveService {
    let driveKey = "yidong"
    let displayName = "移动云盘"
    let supportsScanLogin = false
    let protocolEvidence = "已取证：user/getUser、quota/detail、queryContentList、qrcLogin 扫码页（Docs/NetdiskEndpointsEvidence.md §9）；扫码 API 创建/轮询未完整取证，登录支持凭证导入"
    let threadOptions: [FishThreadOption] = FishThreadOption.all

    private let service: YiDongDriveService
    private let store: FishCredentialStore
    private let threadStore: FishThreadStore

    init(service: YiDongDriveService = YiDongDriveService(), store: FishCredentialStore = FishSecureStore.shared,
         threadStore: FishThreadStore = .shared) {
        self.service = service
        self.store = store
        self.threadStore = threadStore
    }

    private var credentialKey: String { "yidong" }

    private func storedCredential() throws -> YiDongCredential? {
        guard let data = try store.data(for: credentialKey) else { return nil }
        return try YiDongCredential(responseData: data)
    }

    private func persist(_ credential: YiDongCredential) throws {
        try store.set(credential.raw, for: credentialKey)
    }

    /// 凭证导入：Authorization/Cookie JSON 存入（与 Android 导入凭证行为一致）。
    func importCredential(jsonData: Data) throws {
        let credential = try YiDongCredential(responseData: jsonData)
        try persist(credential)
    }

    func status() async throws -> FishDriveStatus {
        guard let credential = try storedCredential() else {
            return FishDriveStatus.notLoggedIn("需要登录：App扫码 / 账号密码 / 导入凭证")
        }
        do {
            let info = try await service.userInfo(credential: credential)
            try persist(info)
            let name = info.displayName
            return FishDriveStatus(state: .loggedIn, detail: "已登录" + (name.map { " · \($0)" } ?? ""), displayName: name)
        } catch {
            return FishDriveStatus(state: .stale, detail: "登录已失效，请重新登录", displayName: nil)
        }
    }

    func beginLogin() async throws -> FishScanSession {
        throw FishDriveError.protocolPending(protocolEvidence + "；扫码动作不会伪装为可用，请使用凭证导入。")
    }

    func poll(_ session: FishScanSession) async throws -> FishScanResult {
        throw FishDriveError.protocolPending(protocolEvidence)
    }

    func refresh() async throws {
        // 移动云盘凭据为长时 Authorization/Cookie，无 refresh 端点证据；本地校验用户信息。
        guard let credential = try storedCredential() else { throw FishDriveError.notLoggedIn }
        _ = try await service.userInfo(credential: credential)
    }

    func logout() async throws {
        try store.remove(credentialKey)
    }

    func currentThread() -> String { threadStore.value(for: driveKey) }
    func setThread(_ id: String) { threadStore.set(id, for: driveKey) }
}
