import Foundation

/// 天翼云盘服务适配器：把 TianyiAuthService（扫码创建/轮询/用户信息）与
/// TianyiSession（Keychain 持久化）包装成统一的 FishDriveService。
/// 登录交互与 Android 一致：扫码页走 FishScanLoginView（FishConfigSectionView 已接 scanLogin action）。
/// 端点/请求体/响应字段严格按 Go 参考实现（fishconfig.Tianyi）。
struct TianyiDriveServiceAdapter: FishDriveService {
    let driveKey = "tianyi"
    let displayName = "天翼云盘"
    let supportsScanLogin = true
    let protocolEvidence = "已取证：GET /open/user/getQrCode.action 创建二维码 → POST /open/user/qrCodeLogin.action 轮询 → GET /open/user/getUserBriefInfo.action?token= 完成登录（Docs/NetdiskEndpointsEvidence.md + Go 参考实现）"
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
        let qrSession = try await auth.createQRCode()
        
        // 将轮询必需参数打包进 deviceCode（JSON 编码）
        let sessionPayload: [String: String] = [
            "session_key": qrSession.sessionKey,
            "short_token": qrSession.shortToken,
            "app_id": qrSession.appId
        ]
        guard let payloadData = try? JSONSerialization.data(withJSONObject: sessionPayload),
              let deviceCode = String(data: payloadData, encoding: .utf8) else {
            throw FishDriveError.protocolPending("无法编码扫码会话参数")
        }
        
        return FishScanSession(
            qrPayload: qrSession.qrContent,
            deviceCode: deviceCode,
            expiresIn: qrSession.timeout,
            interval: max(1, qrSession.interval),
            openURL: nil
        )
    }

    func poll(_ session: FishScanSession) async throws -> FishScanResult {
        // 从 deviceCode 解码轮询参数
        guard let payloadData = session.deviceCode.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: String],
              let sessionKey = payload["session_key"],
              let shortToken = payload["short_token"],
              let appId = payload["app_id"] else {
            throw FishDriveError.protocolPending("扫码会话参数无效")
        }
        
        let pollResponse = try await auth.pollQRCodeLogin(sessionKey: sessionKey, shortToken: shortToken, appId: appId)
        
        if pollResponse.isSuccess {
            guard let token = pollResponse.token else {
                throw FishDriveError.protocolPending("扫码成功但缺少 token")
            }
            
            // 完成登录：用 token 换取会话 Cookie
            let (cookie, userInfo) = try await auth.finishLogin(token: token)
            
            // 构造凭据数据
            var credentialData: [String: Any] = [
                "session_key": sessionKey,
                "token": token
            ]
            if !cookie.isEmpty {
                credentialData["cookie"] = cookie
            }
            // 合并用户信息
            for (key, value) in userInfo {
                credentialData[key] = value
            }
            
            let data = try JSONSerialization.data(withJSONObject: credentialData)
            let credential = try TianyiCredential(responseData: data)
            _ = try await self.session.finishLogin(credential)
            return .authorized
        } else if pollResponse.isPending {
            return .pending
        } else if pollResponse.isExpired {
            throw TianyiAuthError.qrCodeExpired
        } else {
            let message = pollResponse.message ?? pollResponse.errorDescription ?? "扫码失败"
            throw TianyiAuthError.invalidResponse
        }
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
