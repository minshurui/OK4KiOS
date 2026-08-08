import Foundation

/// 迅雷网盘服务适配器：把 XunleiAuthService（扫码创建 / 轮询 / refresh_token 刷新 /
/// /user/me 资料）与 XunleiSession（Keychain 持久化）包装成统一的 FishDriveService。
/// 完整生命周期：创建→轮询→授权保存→刷新→退出。
/// 动态 JSON 无损保留未知字段（XunleiCredential 深合并），Keychain 只替代 Android
/// 存储层，不改变 Android 登录交互。
/// 注意：扫码创建/轮询/刷新/资料端点已取证，但请求体与响应字段未完整取证，
/// 因此 beginLogin/poll/refresh 诚实抛 protocolPending，不伪造可用。
struct XunleiDriveServiceAdapter: FishDriveService {
    let driveKey = "xunlei"
    let displayName = "迅雷网盘"
    let supportsScanLogin = false
    let protocolEvidence = "端点已取证：auth xluser-ssl.xunlei.com/v1/auth/token；扫码(K2(10)) / Token JSON(K2(11))；用户 /drive/v1/user/me；文件 /drive/v1/files?parent_id=；转存 /drive/v1/share/restore；验证码 /v1/shield/captcha/init。请求体与响应字段未完整取证，登录协议 pending"
    let threadOptions: [FishThreadOption] = FishThreadOption.all

    private let session: XunleiSession
    private let auth: XunleiAuthService
    private let threadStore: FishThreadStore

    init(session: XunleiSession = .shared, auth: XunleiAuthService = XunleiAuthService(),
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
        } catch XunleiAuthError.notLoggedIn {
            return FishDriveStatus.notLoggedIn("需要扫码登录")
        } catch {
            return FishDriveStatus(state: .stale, detail: "登录已失效，请重新扫码", displayName: nil)
        }
    }

    func beginLogin() async throws -> FishScanSession {
        // Android L1.p1() 扫码创建：K2(10) 表示扫码登录方式
        // 请求体字段未完整取证，诚实抛 protocolPending
        throw FishDriveError.protocolPending("迅雷扫码创建请求体字段未完整取证（Android L1.p1() K2(10)），无法构造请求")
    }

    func poll(_ session: FishScanSession) async throws -> FishScanResult {
        // Android L1.p1() 轮询：K2(10) 扫码登录轮询
        // 轮询端点与成功判定字段未完整取证，诚实抛 protocolPending
        throw FishDriveError.protocolPending("迅雷扫码轮询端点与成功判定字段未完整取证（Android L1.p1() K2(10)），无法构造请求")
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
