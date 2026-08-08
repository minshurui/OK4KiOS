import Foundation

/// 百度网盘服务适配器：实现 FishDriveService 协议。
///
/// 取证状态（Docs/NetdiskEndpointsEvidence.md 百度小节）：
/// - Android 登录：扫码登录 K2(17) + 手动 Cookie (r1)
/// - 存储方式：Cookie 持久化（非 OAuth token）
/// - 扫码协议端点已按 Go 参考实现补齐：
///   - 创建二维码 GET https://passport.baidu.com/v2/api/getqrcode?lp=pc&apiver=v3
///   - 轮询 GET https://passport.baidu.com/v2/api/qrcode/{sign}?lp=pc&apiver=v3
///   - 登录 GET https://passport.baidu.com/v3/api/login?sign=..&u=http://pan.baidu.com/disk/home
///
/// 实现策略：
/// - status：读取本地 Cookie 凭据，存在则尝试获取用户信息验证有效性
/// - beginLogin：创建二维码并返回 FishScanSession
/// - poll：轮询二维码状态，确认后完成登录并持久化凭据
/// - refresh：使用 Cookie 重新获取用户信息（百度无 refresh_token 语义）
/// - logout：删除本地凭据
/// - 手动 Cookie 登录：通过 setCookie 方法支持（对应 Android r1 手动 Cookie 入口）
struct BaiduDriveServiceAdapter: FishDriveService {
    let driveKey = "baidu"
    let displayName = "百度网盘"
    let supportsScanLogin = true
    let protocolEvidence = "已取证：扫码登录 K2(17) + 手动 Cookie (r1)；扫码端点已按 Go 参考实现（getqrcode → qrcode/{sign} → v3/api/login）"
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
            return FishDriveStatus.notLoggedIn("需要扫码登录")
        } catch {
            return FishDriveStatus(state: .stale, detail: "登录已失效，请重新登录", displayName: nil)
        }
    }

    func beginLogin() async throws -> FishScanSession {
        let qrSession = try await auth.createQRCode()
        
        // 将 BaiduQRCodeSession 打包到 deviceCode 中，qrPayload 存二维码内容
        let sessionData = try JSONSerialization.data(withJSONObject: qrSession.dictionary)
        let deviceCode = sessionData.base64EncodedString()
        
        return FishScanSession(
            qrPayload: qrSession.qrImage,
            deviceCode: deviceCode,
            expiresIn: qrSession.timeout,
            interval: max(1, qrSession.interval),
            openURL: nil
        )
    }

    func poll(_ session: FishScanSession) async throws -> FishScanResult {
        // 从 deviceCode 解包 BaiduQRCodeSession
        guard let data = Data(base64Encoded: session.deviceCode),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let qrSession = BaiduQRCodeSession(dictionary: dict) else {
            throw FishDriveError.invalidSession("百度扫码会话无效")
        }
        
        let status = try await auth.pollQRCode(sign: qrSession.sign)
        
        switch status {
        case .pending:
            return FishScanResult(status: .pending, message: "等待扫码...")
        case .confirmed:
            // 完成登录，获取 BDUSS Cookie
            let credential = try await auth.finishLogin(sign: qrSession.sign)
            
            // 获取用户信息
            let userInfo = try await auth.fetchUserInfo(cookie: credential.cookieHeader)
            
            // 持久化凭据
            try session.saveCredential(userInfo)
            
            let name = userInfo.displayName ?? ""
            return FishScanResult(
                status: .success,
                message: "登录成功" + (name.isEmpty ? "" : " · \(name)"),
                credential: FishCredential(
                    driveKey: driveKey,
                    displayName: name,
                    rawData: userInfo.raw
                )
            )
        case .expired:
            return FishScanResult(status: .expired, message: "二维码已过期，请重新扫码")
        case .unknown(let code):
            throw FishDriveError.unknownStatus("百度扫码未知状态: \(code)")
        }
    }

    /// 刷新：使用 Cookie 重新获取用户信息（百度无 refresh_token 语义）
    func refresh() async throws {
        _ = try await session.validatedCredential()
    }

    func logout() async throws {
        session.clearCredential()
    }

    /// 手动 Cookie 登录入口（对应 Android r1）
    func setCookie(_ cookieString: String) async throws {
        let credential = try BaiduCredential(cookieString: cookieString)
        let userInfo = try await auth.fetchUserInfo(cookie: credential.cookieHeader)
        try session.saveCredential(userInfo)
    }
}
