import Foundation

/// Swift bridge to the Go spider engine (libok4kspider.a, c-archive).
/// Built in CI from GoSpider/cmd/ok4kspider with -buildmode=c-archive.
enum GoSpiderBridge {
    @_silgen_name("ok4k_version") static func version() -> UnsafeMutablePointer<CChar>?
    @_silgen_name("ok4k_home") static func home(_ siteJSON: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
    @_silgen_name("ok4k_category") static func category(_ siteJSON: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
    @_silgen_name("ok4k_search") static func search(_ siteJSON: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
    @_silgen_name("ok4k_detail") static func detail(_ siteJSON: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
    @_silgen_name("ok4k_play") static func play(_ siteJSON: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
    @_silgen_name("ok4k_free") static func free(_ p: UnsafeMutablePointer<CChar>?)

    enum GoSpiderError: LocalizedError {
        case callFailed
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .callFailed: return "Go 引擎调用失败"
            case .emptyResult: return "Go 引擎没有返回数据"
            }
        }
    }

    static var isAvailable: Bool {
        guard let version = version() else { return false }
        defer { free(version) }
        return String(cString: version).hasPrefix("ok4kspider")
    }

    private static func run(_ call: (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?, siteJSON: String) throws -> Data {
        var json = siteJSON.utf8CString
        let output = json.withUnsafeBufferPointer { buffer -> UnsafeMutablePointer<CChar>? in
            guard let base = buffer.baseAddress else { return nil }
            return call(base)
        }
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

    static func home(siteJSON: String) throws -> Data { try run(home, siteJSON: siteJSON) }
    static func category(siteJSON: String) throws -> Data { try run(category, siteJSON: siteJSON) }
    static func search(siteJSON: String) throws -> Data { try run(search, siteJSON: siteJSON) }
    static func detail(siteJSON: String) throws -> Data { try run(detail, siteJSON: siteJSON) }
    static func play(siteJSON: String) throws -> Data { try run(play, siteJSON: siteJSON) }
}
