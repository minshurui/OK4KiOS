import Foundation

/// UC 网盘适配器：UCDriveService（getTokenForQrcodeLogin 扫码创建 → 轮询 → refresh → /account/info）
/// 包装成 FishDriveService。凭据经 FishCredentialStore 持久化（Keychain 替代 Android C0109g1，可注入测替身）。
struct UCDriveServiceAdapter: FishDriveService {
    let driveKey = "uc"
    let displayName = "UC网盘"
    let supportsScanLogin = true
    let protocolEvidence = "已取证：getTokenForQrcodeLogin 扫码创建 → 轮询 → refresh → /account/info（Docs/NetdiskEndpointsEvidence.md §9）；轮询成功判定与保存字段待真实样本确认"
    let threadOptions: [FishThreadOption] = FishThreadOption.all

    private let service: UCDriveService
    private let store: FishCredentialStore
    private let threadStore: FishThreadStore

    init(service: UCDriveService = UCDriveService(), store: FishCredentialStore = FishSecureStore.shared,
         threadStore: FishThreadStore = .shared) {
        self.service = service
        self.store = store
        self.threadStore = threadStore
    }

    private var credentialKey: String { "uc" }

    private func storedCredential() throws -> UCCredential? {
        guard let data = try store.data(for: credentialKey) else { return nil }
        return try UCCredential(responseData: data)
    }

    private func persist(_ credential: UCCredential) throws {
        try store.set(credential.raw, for: credentialKey)
    }

    func status() async throws -> FishDriveStatus {
        guard let credential = try storedCredential() else {
            return FishDriveStatus.notLoggedIn("需要扫码登录")
        }
        do {
            let info = try await service.accountInfo(credential: credential)
            try persist(info)
            let name = info.displayName.nonempty
            return FishDriveStatus(state: .loggedIn, detail: "已登录" + (name.map { " · \($0)" } ?? ""), displayName: name)
        } catch {
            return FishDriveStatus(state: .stale, detail: "登录已失效，请重新扫码", displayName: nil)
        }
    }

    func beginLogin() async throws -> FishScanSession {
        let authorization = try await service.createQrcodeLogin()
        return FishScanSession(
            qrPayload: authorization.qrContent,
            deviceCode: authorization.deviceCode,
            expiresIn: authorization.expiresIn,
            interval: max(1, authorization.interval),
            openURL: authorization.openURL
        )
    }

    func poll(_ session: FishScanSession) async throws -> FishScanResult {
        do {
            let credential = try await service.pollQrcodeLogin(deviceCode: session.deviceCode)
            try persist(credential)
            return .authorized
        } catch UCAuthError.server(let message) where message == "pending" {
            return .pending
        }
    }

    func refresh() async throws {
        guard let credential = try storedCredential() else { throw FishDriveError.notLoggedIn }
        let refreshed = try await service.refresh(credential: credential)
        try persist(refreshed)
    }

    func logout() async throws {
        try store.remove(credentialKey)
    }

    func currentThread() -> String { threadStore.value(for: driveKey) }
    func setThread(_ id: String) { threadStore.set(id, for: driveKey) }
}
