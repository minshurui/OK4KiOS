import Foundation

/// 百度网盘服务适配器：实现 FishDriveService 协议。
///
/// 取证状态（Docs/NetdiskEndpointsEvidence.md 百度小节）：
/// - Android 登录：扫码登录 K2(17) + 手动 Cookie (r1)
/// - 存储方式：Cookie 持久化（非 OAuth token）
/// - 扫码/轮询端点无法从 smali 完整取证（g.smali 仅 242 行，核心委托 C0243g + W0/A 类）
///
/// 诚实实现策略：
/// - status：读取本地 Cookie 凭据，存在则尝试获取用户信息验证有效性
/// - beginLogin：抛 protocolPending（扫码端点未取证）
/// - poll：抛 protocolPending（轮询端点未取证）
/// - refresh：使用 Cookie 重新获取用户信息（无 refresh_token 语义）
/// - logout：删除本地凭据
/// - 手动 Cookie 登录：通过 setCookie 方法支持（对应 Android r1 手动 Cookie 入口）
struct BaiduDriveServiceAdapter: FishDriveService {
    let driveKey = "baidu"
    let displayName = "百度网盘"
    let supportsScanLogin = false
    let protocolEvidence = "部分取证：扫码登录 K2(17) + 手动 Cookie (r1)；扫码/轮询端点待补充（C0243g 委托 W0/A），Cookie 用户信息端点已取证"
    let threadOptions: [FishThreadOption] = FishThreadOption.all

    private let session: BaiduSession
    private let auth: BaiduAuthService
    private let threadStore: FishThreadStore

    init(session: BaiduSession = .shared, auth: BaiduAuthService = BaiduAuthService(),
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
        } catch BaiduAuthError.notLoggedIn {
            return FishDriveStatus.notLoggedIn("需要登录（扫码协议取证中，暂支持手动 Cookie）")
        } catch {
            return FishDriveStatus(state: .stale, detail: "登录已失效，请重新登录", displayName: nil)
        }
    }

    func beginLogin() async throws -> FishScanSession {
        throw FishDriveError.protocolPending("百度网盘扫码登录协议仍在取证（C0243g 委托 W0/A 类），暂时无法扫码；可先使用手动 Cookie 登录")
    }

    func poll(_ session: FishScanSession) async throws -> FishScanResult {
        throw FishDriveError.protocolPending("百度网盘轮询协议未取证，不能伪造授权结果")
    }

    /// 刷新：使用 Cookie 重新获取用户信息（百度无 refresh_token 语义）
    func refresh() async throws {
        _ = try await session.validatedCredential()
    }

    func logout() async throws {
        try await session.logout()
    }

    /// 手动 Cookie 登录（对应 Android r1 入口）
    /// - Parameter cookieString: 百度网盘 Cookie 字符串（如 "BDUSS=xxx; PANWAP=yyy"）
    func loginWithCookie(_ cookieString: String) async throws {
        let credential = try BaiduCredential(cookieString: cookieString)
        _ = try await session.finishLogin(credential)
    }

    func currentThread() -> String { threadStore.value(for: driveKey) }
    func setThread(_ id: String) { threadStore.set(id, for: driveKey) }
}
