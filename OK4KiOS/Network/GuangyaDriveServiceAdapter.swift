import Foundation

/// 光鸭网盘服务适配器：把已有的 GuangyaAuthService（device code 创建 / 3s 轮询 /
/// refresh_token 刷新 / /user/me 资料）与 GuangyaSession（Keychain 持久化）包装成
/// 统一的 FishDriveService。完整生命周期：创建→轮询→授权保存→刷新→退出。
/// 动态 JSON 无损保留未知字段（GuangyaCredential 深合并），Keychain 只替代 Android
/// C0109g1 存储层，不改变 Android 登录交互。
struct GuangyaDriveServiceAdapter: FishDriveService {
    let driveKey = "guangya"
    let displayName = "光鸭网盘"
    let supportsScanLogin = true
    let protocolEvidence = "完整取证：device code 创建 → 3s 轮询（180s 超时）→ refresh_token 刷新 → Keychain 持久化（PROTOCOL.md §4）"
    let threadOptions: [FishThreadOption] = FishThreadOption.all

    private let session: GuangyaSession
    private let auth: GuangyaAuthService
    private let threadStore: FishThreadStore

    init(session: GuangyaSession = .shared, auth: GuangyaAuthService = GuangyaAuthService(),
         threadStore: FishThreadStore = .shared) {
        self.session = session
        self.auth = auth
        self.threadStore = threadStore
    }

    func status() async throws -> FishDriveStatus {
        do {
            let credential = try await session.validatedCredential()
            let name = credential.displayName.map { "已登录 · \($0)" } ?? "已登录"
            return FishDriveStatus(state: .loggedIn, detail: name, displayName: credential.displayName)
        } catch GuangyaAuthError.notLoggedIn {
            return FishDriveStatus.notLoggedIn("需要扫码登录")
        } catch {
            return FishDriveStatus(state: .stale, detail: "登录已失效，请重新扫码", displayName: nil)
        }
    }

    func beginLogin() async throws -> FishScanSession {
        let authorization = try await auth.begin()
        return FishScanSession(
            qrPayload: authorization.verificationURL.absoluteString,
            deviceCode: authorization.deviceCode,
            expiresIn: authorization.expiresIn,
            interval: max(1, authorization.interval),
            openURL: authorization.verificationURL
        )
    }

    func poll(_ session: FishScanSession) async throws -> FishScanResult {
        switch try await auth.poll(deviceCode: session.deviceCode) {
        case .pending:
            return .pending
        case .authorized(let credential):
            _ = try await self.session.finishLogin(credential)
            return .authorized
        }
    }

    /// 刷新：validatedCredential 内部按 Android 顺序执行 profile 校验 → refresh_token
    /// 刷新 → 再次 profile，并在 Keychain 持久化刷新后的凭据。
    func refresh() async throws {
        _ = try await session.validatedCredential()
    }

    func logout() async throws {
        try await session.logout()
    }

    func currentThread() -> String { threadStore.value(for: driveKey) }
    func setThread(_ id: String) { threadStore.set(id, for: driveKey) }
}
