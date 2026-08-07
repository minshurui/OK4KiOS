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
    case gatewayRequired(String)

    var errorDescription: String? {
        switch self {
        case .noUsableHost: return "该站点没有可访问的网址"
        case .invalidResponse: return "站点返回内容无法解析"
        case .noPlayableURL: return "没有解析到可播放地址"
        case .gatewayRequired(let name): return "\(name) 使用加密 Spider，请在设置中填写 Spider 网关，或选择带网址的原生兼容站点"
        }
    }
}
