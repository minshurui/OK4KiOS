import Foundation

/// 协议取证未完成的网盘（9 个）——诚实实现：
/// - status：读取 Keychain 凭据存在性，如实报告“未登录/协议未完成”，不伪造网络状态；
/// - beginLogin/poll/refresh：抛 protocolPending，绝不假装能扫码（硬性规则）；
/// - logout：真实删除本地凭据（Android 清除语义 = 删除本地存储）；
/// - 线程：本地偏好，与协议无关，正常可用。
/// 各网盘端点来自 PROTOCOL.md 第 9 节（baksmali short-array XOR 批量解码，已取证）。
struct PendingFishDriveService: FishDriveService {
    let driveKey: String
    let displayName: String
    let protocolEvidence: String
    private let store: FishCredentialStore

    var supportsScanLogin: Bool { false }
    var threadOptions: [FishThreadOption] { FishThreadOption.all }

    init(driveKey: String, store: FishCredentialStore = FishSecureStore.shared) {
        let normalized = driveKey.lowercased()
        self.driveKey = normalized
        self.displayName = Self.names[normalized] ?? normalized
        self.protocolEvidence = Self.evidence[normalized] ?? "协议仍在取证"
        self.store = store
    }

    func status() async throws -> FishDriveStatus {
        guard let data = try? store.data(for: driveKey), !data.isEmpty else {
            return FishDriveStatus.notLoggedIn("未登录 · 登录协议取证未完成")
        }
        return FishDriveStatus(state: .stale, detail: "已保存凭据（登录协议未完成，凭据暂不可用于业务）", displayName: nil)
    }

    func beginLogin() async throws -> FishScanSession {
        throw FishDriveError.protocolPending("“\(displayName)”登录协议仍在取证，暂时无法扫码；已定位的端点：\(Self.endpoints[driveKey] ?? "待解码")")
    }

    func poll(_ session: FishScanSession) async throws -> FishScanResult {
        throw FishDriveError.protocolPending("“\(displayName)”轮询协议未取证，不能伪造授权结果")
    }

    func refresh() async throws {
        throw FishDriveError.protocolPending("“\(displayName)”刷新协议未取证，不能伪造刷新结果")
    }

    func logout() async throws {
        try store.remove(driveKey)
    }

    func currentThread() -> String { FishThreadStore.shared.value(for: driveKey) }
    func setThread(_ id: String) { FishThreadStore.shared.set(id, for: driveKey) }

    // MARK: - 证据目录（PROTOCOL.md §9，2026-08-08 批量解码）

    private static let names: [String: String] = [
        "quark": "夸克网盘", "uc": "UC网盘", "tianyi": "天翼云盘", "yidong": "移动云盘",
        "baidu": "百度网盘", "xunlei": "迅雷网盘", "pan123": "123网盘", "pan115": "115网盘", "ali": "阿里云盘"
    ]

    private static let endpoints: [String: String] = [
        "quark": "扫码创建 uop.quark.cn/cas/ajax/getTokenForQrcodeLogin；账号 pan.quark.cn/account/info",
        "uc": "扫码创建 api.open.uc.cn/cas/ajax/getTokenForQrcodeLogin",
        "tianyi": "账号 api.cloud.189.cn/api/portal/v2/getUserBriefInfo.action；登录入口 L1.l1()（扫码/账号密码/短信）",
        "yidong": "扫码 yun.139.com/w/#/qrcLogin；用户 user-njs.yun.139.com/user/getUser",
        "baidu": "扫码(K2(17)) / 手动Cookie；百度端点待补充（C0243g 委托 W0/A）",
        "xunlei": "auth xluser-ssl.xunlei.com/v1/auth/token；扫码(K2(10)) / Token JSON(K2(11))",
        "pan123": "OAuth open-api.123pan.com/api/v1/oauth2/user/authorize；litepan 中转 oauth.litepan.top",
        "pan115": "扫码创建 passportapi.115.com/app/1.0/alipaymini/1.0/login/qrcode/；轮询 qrcodeapi.115.com/api/1.0/alipaymini/1.0/token/",
        "ali": "OAuth open.aliyundrive.com/oauth/users/authorize；Token auth.aliyundrive.com/v2/account/token；刷新 auth.xiaoya.pro/api/ali_open/refresh"
    ]

    private static let evidence: [String: String] = {
        var result: [String: String] = [:]
        for (key, name) in names {
            result[key] = "Android 协议取证未完成：\(endpoints[key] ?? "端点待解码")；轮询/保存字段待 smali 方法级分析"
        }
        return result
    }()
}
