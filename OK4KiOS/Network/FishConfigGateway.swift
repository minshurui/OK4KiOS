import Foundation

/// 一次配置动作的结果信封（与 GoSpider/API.md 对齐的本地实现）。
struct FishConfigActionResult: Equatable, Sendable {
    let message: String
    let status: FishDriveStatus?
    let thread: String?
}

/// FishConfig 设置中心数据层网关。
///
/// 路由规则：
/// 1. 若 Go 引擎导出了 ok4k_fishconfig 符号（worker-A 网关就绪），走 Go；
///    请求信封 {"action","section","drive","params"}，响应信封见 GoSpiderBridge。
/// 2. 否则本地执行：光鸭走完整生命周期适配器，其余网盘按协议取证状态诚实响应。
enum FishConfigGateway {
    static func perform(actionID: String, section: FishConfigSection) async throws -> FishConfigActionResult {
        if GoSpiderBridge.supportsFishConfig {
            return try await performThroughGo(actionID: actionID, section: section)
        }
        return try await performLocally(actionID: actionID, section: section)
    }

    // MARK: - 本地执行

    static func performLocally(actionID: String, section: FishConfigSection) async throws -> FishConfigActionResult {
        guard let driveKey = section.driveKey else {
            return FishConfigActionResult(message: "“\(section.title)”的 Android action 已定位，原生协议仍在移植；当前不会用手动导入或空结果代替。", status: nil, thread: nil)
        }
        let service = FishDriveRegistry.service(for: driveKey)
        switch actionID.fishConfigActionKind {
        case .status:
            let status = try await service.status()
            return FishConfigActionResult(message: status.detail, status: status, thread: nil)
        case .clean:
            try await service.logout()
            return FishConfigActionResult(message: "\(service.displayName)凭据已清除", status: nil, thread: nil)
        case .thread:
            return FishConfigActionResult(message: "当前线程：\(threadTitle(service.currentThread()))", status: nil, thread: service.currentThread())
        case .scanLogin:
            guard service.supportsScanLogin else {
                throw FishDriveError.protocolPending(service.protocolEvidence + "；扫码动作不会伪装为可用。")
            }
            // 扫码登录是长生命周期（创建→轮询→授权），由 FishScanLoginView 直接驱动服务。
            return FishConfigActionResult(message: service.displayName, status: nil, thread: nil)
        case .other:
            return FishConfigActionResult(message: "“\(actionID)”的 Android action 已定位，原生协议仍在移植；当前不会用手动导入或空结果代替。", status: nil, thread: nil)
        }
    }

    // MARK: - Go 网关（接口对齐后启用）

    private static func performThroughGo(actionID: String, section: FishConfigSection) async throws -> FishConfigActionResult {
        let request: [String: Any] = [
            "action": actionID,
            "section": section.rawValue,
            "drive": section.driveKey ?? "",
            "params": [:]
        ]
        let data = try JSONSerialization.data(withJSONObject: request)
        let response = try GoSpiderBridge.fishconfig(actionJSON: String(data: data, encoding: .utf8) ?? "{}")
        guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            throw FishDriveError.invalidResponse
        }
        if let error = object["error"] as? String, !error.isEmpty {
            throw FishDriveError.server(error)
        }
        let message = (object["message"] as? String) ?? "已执行"
        var status: FishDriveStatus?
        if let statusObject = object["status"] as? [String: Any],
           let detail = statusObject["detail"] as? String {
            let state: FishDriveStatus.State = (statusObject["state"] as? String) == "loggedIn" ? .loggedIn : .notLoggedIn
            status = FishDriveStatus(state: state, detail: detail, displayName: statusObject["displayName"] as? String)
        }
        return FishConfigActionResult(message: message, status: status, thread: object["thread"] as? String)
    }

    private static func threadTitle(_ id: String) -> String {
        FishThreadOption.all.first { $0.id == id }?.title ?? id
    }
}
