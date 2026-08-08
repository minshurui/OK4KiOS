import Foundation

// MARK: - 网盘状态

struct FishDriveStatus: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case notLoggedIn
        case loggedIn
        case stale
    }

    let state: State
    let detail: String
    let displayName: String?

    var isLoggedIn: Bool { state == .loggedIn }

    static func notLoggedIn(_ detail: String = "需要登录") -> FishDriveStatus {
        FishDriveStatus(state: .notLoggedIn, detail: detail, displayName: nil)
    }
}

// MARK: - 扫码会话（创建/轮询生命周期句柄）

struct FishScanSession: Equatable, Sendable {
    /// 二维码内容：通常是授权 URL（光鸭 verification_uri_complete）。
    let qrPayload: String
    /// 轮询句柄（device_code / 会话 id），仅用于 poll()。
    let deviceCode: String
    let expiresIn: TimeInterval
    let interval: TimeInterval
    /// 可选的本机打开链接（扫码页展示）。
    let openURL: URL?
}

enum FishScanResult: Equatable, Sendable {
    case pending
    case authorized
}

// MARK: - 线程偏好（Android “普通/会员下载线程”同语义，仅本地偏好）

struct FishThreadOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String

    static let normal = FishThreadOption(id: "normal", title: "普通线程")
    static let vip = FishThreadOption(id: "vip", title: "会员线程")
    static let all: [FishThreadOption] = [.normal, .vip]
}

// MARK: - 错误

enum FishDriveError: LocalizedError, Equatable {
    /// Android 协议取证未完成：诚实报告，绝不伪装为可用。
    case protocolPending(String)
    case notLoggedIn
    case timeout
    case cancelled
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .protocolPending(let reason): return reason
        case .notLoggedIn: return "网盘未登录，请先扫码登录"
        case .timeout: return "扫码等待已超时，请重试"
        case .cancelled: return "扫码已取消"
        case .invalidResponse: return "网盘授权响应无效"
        case .server(let text): return "网盘请求失败：\(text)"
        }
    }
}

// MARK: - 设置中心数据层协议

/// 一个网盘栏目的完整生命周期：状态 / 扫码创建 / 轮询 / 刷新 / 退出 / 线程偏好。
/// 本地实现按 PROTOCOL.md 各网盘协议取证状态逐盘落地；网关就绪后由
/// FishConfigGateway 统一路由，接口按 GoSpider/API.md 信封对齐。
protocol FishDriveService: Sendable {
    var driveKey: String { get }
    var displayName: String { get }
    /// 扫码登录是否可用（仅协议完整取证的网盘为 true）。
    var supportsScanLogin: Bool { get }
    /// 当前取证状态摘要（诚实展示给用户）。
    var protocolEvidence: String { get }

    /// 账号状态：读取本地凭据并按需刷新；未登录不抛错，返回 .notLoggedIn。
    func status() async throws -> FishDriveStatus
    /// 创建扫码会话（二维码 + 轮询句柄）。
    func beginLogin() async throws -> FishScanSession
    /// 轮询授权结果。
    func poll(_ session: FishScanSession) async throws -> FishScanResult
    /// 刷新凭据（refresh_token 生命周期；光鸭在 validatedCredential 内自动完成）。
    func refresh() async throws
    /// 退出登录：删除本地凭据（Keychain 仅替代 Android 存储层，无远端 revoke 语义变更）。
    func logout() async throws

    var threadOptions: [FishThreadOption] { get }
    func currentThread() -> String
    func setThread(_ id: String)
}

// MARK: - 网盘服务注册表

enum FishDriveRegistry {
    /// 测试/网关可注入的替身服务（Keychain 在无 entitlement 环境不可用）。
    static var override: [String: FishDriveService] = [:]

    static func service(for key: String) -> FishDriveService {
        let normalized = key.lowercased()
        if let injected = override[normalized] {
            return injected
        }
        switch normalized {
        case "guangya": return GuangyaDriveServiceAdapter()
        default: return PendingFishDriveService(driveKey: normalized)
        }
    }
}
