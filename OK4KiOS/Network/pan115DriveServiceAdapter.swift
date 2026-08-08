import Foundation

/// 115网盘服务适配器：把 Pan115AuthService（扫码创建 / 轮询 / profile）与
/// Pan115Session（Keychain 持久化）包装成统一的 FishDriveService。
/// 完整生命周期：创建二维码→轮询（间隔 3s，超时 180s）→授权保存→刷新→退出。
/// 动态 JSON 无损保留未知字段（Pan115Credential 深合并），Keychain 只替代 Android
/// 存储层，不改变 Android 登录交互。
struct Pan115DriveServiceAdapter: FishDriveService {
    let driveKey = "pan115"
    let displayName = "115网盘"
    let supportsScanLogin = true
    let protocolEvidence = "完整取证：扫码创建 passportapi.115.com/app/1.0/alipaymini/1.0/login/qrcode/ → 轮询 qrcodeapi.115.com/api/1.0/alipaymini/1.0/token/ → 存储 115.com/index.php?ct=ajax&ac=get_storage_info → 文件 web.api.115.com/files → 下载 proapi.115.com/app/chrome/downurl?t= → 上传 .../app/uploadinfo → 分享快照 115cdn.com/webapi/share/snap → 分享 115cdn.com/s/（Docs/NetdiskEndpointsEvidence.md）"
    let threadOptions: [FishThreadOption] = FishThreadOption.all

    private let session: Pan115Session
    private let auth: Pan115AuthService
    private let threadStore: FishThreadStore

    init(session: Pan115Session = .shared, auth: Pan115AuthService = Pan115AuthService(),
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
        } catch Pan115AuthError.notLoggedIn {
            return FishDriveStatus.notLoggedIn("需要扫码登录")
        } catch {
            return FishDriveStatus(state: .stale, detail: "登录已失效，请重新扫码", displayName: nil)
        }
    }

    func beginLogin() async throws -> FishScanSession {
        let qr = try await auth.begin()
        return FishScanSession(
            qrPayload: qr.qrCode,
            deviceCode: qr.uid,
            expiresIn: TimeInterval(qr.time),
            interval: 3,
            openURL: URL(string: qr.qrCode)
        )
    }

    func poll(_ session: FishScanSession) async throws -> FishScanResult {
        let qr = try await auth.begin()
        switch try await auth.poll(uid: session.deviceCode, time: qr.time, sign: qr.sign) {
        case .pending:
            return .pending
        case .authorized(let credential):
            _ = try await self.session.finishLogin(credential)
            return .authorized
        }
    }

    /// 刷新：validatedCredential 内部按 Android 顺序执行 profile 校验 → 刷新 → 再次 profile。
    func refresh() async throws {
        _ = try await session.validatedCredential()
    }

    func logout() async throws {
        try await session.logout()
    }

    func currentThread() -> String { threadStore.value(for: driveKey) }
    func setThread(_ id: String) { threadStore.set(id, for: driveKey) }
}
