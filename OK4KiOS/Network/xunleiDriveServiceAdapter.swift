import Foundation

/// 迅雷网盘服务适配器：把 XunleiAuthService（扫码创建 / 轮询 / refresh_token 刷新 /
/// /user/me 资料）与 XunleiSession（Keychain 持久化）包装成统一的 FishDriveService。
/// 完整生命周期：创建→轮询→授权保存→刷新→退出。
/// 动态 JSON 无损保留未知字段（XunleiCredential 深合并），Keychain 只替代 Android
/// 存储层，不改变 Android 登录交互。
/// 扫码创建/轮询/刷新/资料端点已取证，请求体与响应字段严格按 Go 参考实现。
struct XunleiDriveServiceAdapter: FishDriveService {
    let driveKey = "xunlei"
    let displayName = "迅雷网盘"
    let supportsScanLogin = true
    let protocolEvidence = "端点已取证：auth xluser-ssl.xunlei.com/v1/auth/token；扫码(K2(10)) / Token JSON(K2(11))；用户 /v1/user/me；文件 /drive/v1/files?parent_id=；转存 /drive/v1/share/restore；验证码 /v1/shield/captcha/init。请求体与响应字段严格按 Go 参考实现"
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
        let authorization = try await auth.createQrcodeLogin()
        let qrContent = authorization.verificationURIComplete?.absoluteString ?? authorization.verificationURI.absoluteString
        return FishScanSession(
            qrPayload: qrContent,
            deviceCode: authorization.deviceCode,
            expiresIn: authorization.expiresIn,
            interval: max(1, authorization.interval),
            openURL: authorization.verificationURIComplete ?? authorization.verificationURI
        )
    }

    func poll(_ session: FishScanSession) async throws -> FishScanResult {
        guard let deviceCode = session.deviceCode else {
            throw FishDriveError.protocolPending("缺少 device_code，无法轮询")
        }

        do {
            let credential = try await auth.pollQrcodeLogin(deviceCode: deviceCode, clientID: auth.clientID)
            // 获取用户信息完善资料
            let fullCredential = try await auth.userInfo(credential: credential)
            try await self.session.save(fullCredential)
            let name = fullCredential.displayName
            return FishScanResult(
                success: true,
                credential: FishCredential(
                    driveKey: driveKey,
                    accessToken: fullCredential.accessToken,
                    refreshToken: fullCredential.refreshToken,
                    displayName: name,
                    raw: fullCredential.raw
                ),
                displayName: name
            )
        } catch XunleiAuthError.pending {
            return FishScanResult(success: false, pending: true, displayName: nil)
        } catch XunleiAuthError.expired {
            return FishScanResult(success: false, pending: false, displayName: nil, errorMessage: "扫码已过期，请重新扫码")
        } catch XunleiAuthError.serverError(let message) {
            return FishScanResult(success: false, pending: false, displayName: nil, errorMessage: "扫码失败：\(message)")
        } catch {
            return FishScanResult(success: false, pending: false, displayName: nil, errorMessage: "扫码失败，请重试")
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
}
