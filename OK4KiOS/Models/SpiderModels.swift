import Foundation

struct SpiderPlayback: Sendable {
    let url: String
    let headers: [String: String]

    init(url: String, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }
}

enum SpiderError: LocalizedError {
    case noUsableHost
    case invalidResponse
    case noPlayableURL
    case nativeMigrationPending(String)

    var errorDescription: String? {
        switch self {
        case .noUsableHost: return "该站点没有可访问的网址"
        case .invalidResponse: return "站点返回内容无法解析"
        case .noPlayableURL: return "没有解析到可播放地址"
        case .nativeMigrationPending(let name): return "\(name) 已保留，iPhone/iPad 原生适配正在移植；Spider 网关仅作为可选兼容方式"
        }
    }
}
