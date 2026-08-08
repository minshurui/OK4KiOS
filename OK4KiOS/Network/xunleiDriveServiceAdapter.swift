import Foundation

/// 迅雷网盘适配器：OAuth2 device-code 扫码登录（createQrcodeLogin → pollQrcodeLogin →
/// refresh → userInfo）。凭据经 XunleiSession（actor + store 注入）持久化。
struct XunleiDriveServiceAdapter: FishDriveService {
    let driveKey = "xunlei"
    let displayName = "迅雷网盘"
    let supportsScanLogin = true
    let protocolEvidence = "已取证：device/code 创建 → /auth/token 轮询（grant_type=device_code）→ refresh → /user/me（Docs/NetdiskEndpointsEvidence.md + Go 参考实现）"
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
        let uri = authorization.verificationURIComplete?.absoluteString ?? authorization.verificationURI.absoluteString
        return FishScanSession(
            qrPayload: uri,
            deviceCode: "\(authorization.deviceCode)|\(auth.clientID)",
            expiresIn: authorization.expiresIn,
            interval: max(1, authorization.interval),
            openURL: authorization.verificationURIComplete ?? authorization.verificationURI
        )
    }

    func poll(_ session: FishScanSession) async throws -> FishScanResult {
        let parts = session.deviceCode.split(separator: "|")
        guard parts.count == 2, let deviceCode = parts.first, let clientID = parts.last else {
            throw XunleiAuthError.invalidResponse
        }
        do {
            let credential = try await auth.pollQrcodeLogin(deviceCode: String(deviceCode), clientID: String(clientID))
            _ = try await self.session.finishLogin(credential)
            return .authorized
        } catch XunleiAuthError.pending {
            return .pending
        }
    }

    func refresh() async throws {
        _ = try await session.validatedCredential()
    }

    func logout() async throws {
        try await session.logout()
    }

    func currentThread() -> String { threadStore.value(for: driveKey) }
    func setThread(_ id: String) { threadStore.set(id, for: driveKey) }
}
