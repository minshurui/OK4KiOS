import Foundation
import Darwin

/// Swift bridge to the Go spider engine (libok4kspider.a, c-archive).
/// Symbols are resolved at runtime with dlsym so simulator/test builds that
/// do not link the Go library degrade gracefully (isAvailable == false).
enum GoSpiderBridge {
    private typealias CStringFn = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    private typealias VersionFn = @convention(c) () -> UnsafeMutablePointer<CChar>?
    private typealias FreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    enum GoSpiderError: LocalizedError {
        case notLinked
        case callFailed
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .notLinked: return "Go 引擎未链接到当前构建"
            case .callFailed: return "Go 引擎调用失败"
            case .emptyResult: return "Go 引擎没有返回数据"
            }
        }
    }

    static var isAvailable: Bool {
        guard let fn = resolve("ok4k_version", as: VersionFn.self) else { return false }
        guard let version = fn() else { return false }
        defer { resolve("ok4k_free", as: FreeFn.self)?(version) }
        return String(cString: version).hasPrefix("ok4kspider")
    }

    static func home(siteJSON: String) throws -> Data { try call("ok4k_home", siteJSON: siteJSON) }
    static func category(siteJSON: String) throws -> Data { try call("ok4k_category", siteJSON: siteJSON) }
    static func search(siteJSON: String) throws -> Data { try call("ok4k_search", siteJSON: siteJSON) }
    static func detail(siteJSON: String) throws -> Data { try call("ok4k_detail", siteJSON: siteJSON) }
    static func play(siteJSON: String) throws -> Data { try call("ok4k_play", siteJSON: siteJSON) }

    // MARK: - Private

    private static func resolve<T>(_ name: String, as type: T.Type) -> T? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    private static func call(_ name: String, siteJSON: String) throws -> Data {
        guard let fn = resolve(name, as: CStringFn.self) else { throw GoSpiderError.notLinked }
        guard let free = resolve("ok4k_free", as: FreeFn.self) else { throw GoSpiderError.notLinked }
        let output = siteJSON.withCString { fn($0) }
        guard let output else { throw GoSpiderError.callFailed }
        defer { free(output) }
        let text = String(cString: output)
        guard !text.isEmpty, text != "null" else { throw GoSpiderError.emptyResult }
        if let errorData = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
           let message = object["error"] as? String {
            throw NSError(domain: "GoSpider", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard let data = text.data(using: .utf8) else { throw GoSpiderError.callFailed }
        return data
    }
}
