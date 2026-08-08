import Foundation

/// 天翼云盘服务适配器：把 TianyiAuthService（用户信息 / 空间信息 / 家庭列表）与
/// TianyiSession（Keychain 持久化）包装成统一的 FishDriveService。
/// 登录交互与 Android 一致：扫码页走 FishScanLoginView（FishConfigSectionView 已接 scanLogin action）。
/// 注意：扫码创建/轮询端点尚未从 Android 完整取证，beginLogin/poll 诚实抛 protocolPending。
struct TianyiDriveServiceAdapter: FishDriveService {
    let driveKey = "tianyi"
    let displayName = "天翼云盘"
    let supportsScanLogin = false
    let protocolEvidence = "部分取证：用户信息 /api/portal/v2/getUserBriefInfo.action、空间 /api/portal/getUserSizeInfo.action、家庭 /family/manage/getFamilyList.action；扫码创建/轮询端点待 smali 方法级分析（L1.l1() 已定位 F2(27)/K2(7)/K2(16)）"
    let threadOptions: [FishThreadOption] = FishThreadOption.all

    private let session: TianyiSession
    private let auth: TianyiAuthService
    private let threadStore: FishThreadStore

    init(session: TianyiSession = .shared, auth: TianyiAuthService = TianyiAuthService(),
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
        } catch TianyiAuthError.notLoggedIn {
            return FishDriveStatus.notLoggedIn("需要扫码登录")
        } catch {
            return FishDriveStatus(state: .stale, detail: "登录已失效，请重新扫码", displayName: nil)
        }
    }

    func beginLogin() async throws -> FishScanSession {
        throw FishDriveError.protocolPending("天翼云盘扫码创建端点未完整取证（L1.l1() 已定位 F2(27) 扫码入口，但请求体/响应字段待 smali 分析），暂时无法扫码")
    }

    func poll(_ session: FishScanSession) async throws -> FishScanResult {
        throw FishDriveError.protocolPending("天翼云盘轮询端点未完整取证，不能伪造授权结果")
    }

    /// 刷新：validatedCredential 内部按 Android 顺序执行用户信息校验 → 刷新 → 再次校验，并在 Keychain 持久化。
    func refresh() async throws {
        _ = try await session.validatedCredential()
    }

    func logout() async throws {
        try await session.logout()
    }

    func currentThread() -> String { threadStore.value(for: driveKey) }
    func setThread(_ id: String) { threadStore.set(id, for: driveKey) }
}
