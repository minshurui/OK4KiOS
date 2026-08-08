import Foundation

/// 百度网盘适配器：扫码登录（getqrcode → qrcode/{sign} 轮询 → v3/api/login 取 BDUSS）+
/// 手动 Cookie。凭据经 BaiduSession（actor + store 注入）持久化。
struct BaiduDriveServiceAdapter: FishDriveService {
    let driveKey = "baidu"
    let displayName = "百度网盘"
    let supportsScanLogin = true
    let protocolEvidence = "已取证：扫码登录 K2(17) + 手动 Cookie (r1)；扫码端点按 Go 参考实现（getqrcode → qrcode/{sign} → v3/api/login 取 BDUSS）"
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
            return FishDriveStatus.notLoggedIn("需要扫码登录或手动 Cookie")
        } catch {
            return FishDriveStatus(state: .stale, detail: "登录已失效，请重新登录", displayName: nil)
        }
    }

    func beginLogin() async throws -> FishScanSession {
        let qr = try await auth.createQRCode()
        return FishScanSession(
            qrPayload: qr.qrImage,
            deviceCode: qr.sign,
            expiresIn: qr.timeout,
            interval: max(1, qr.interval),
            openURL: nil
        )
    }

    func poll(_ session: FishScanSession) async throws -> FishScanResult {
        switch try await auth.pollQRCode(sign: session.deviceCode) {
        case .pending:
            return .pending
        case .confirmed:
            let credential = try await auth.finishLogin(sign: session.deviceCode)
            _ = try await self.session.finishLogin(credential)
            return .authorized
        case .expired:
            throw BaiduAuthError.qrExpired
        case .unknown(let code):
            throw BaiduAuthError.networkError("百度扫码未知状态: \(code)")
        }
    }

    func refresh() async throws {
        _ = try await session.validatedCredential()
    }

    func logout() async throws {
        try await session.logout()
    }

    /// 手动 Cookie 登录（对应 Android r1 入口）
    func loginWithCookie(_ cookieString: String) async throws {
        let credential = try BaiduCredential(cookieString: cookieString)
        _ = try await session.finishLogin(credential)
    }

    func currentThread() -> String { threadStore.value(for: driveKey) }
    func setThread(_ id: String) { threadStore.set(id, for: driveKey) }
}
