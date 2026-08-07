import Foundation
import Swifter

final class LocalProxyServer {
    static let shared = LocalProxyServer()
    private let server = HttpServer()
    private let session: URLSession
    private(set) var port: UInt16 = 0

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration)
    }

    func start() {
        guard port == 0 else { return }
        server.listenAddressIPv4 = "127.0.0.1"
        server["/health"] = { _ in .ok(.json(["status": "ok"])) }
        server["/proxy"] = { [weak self] request in self?.proxy(request) ?? .internalServerError }
        for candidate in UInt16(9978)...UInt16(9998) {
            do {
                try server.start(in_port_t(candidate), forceIPv4: true)
                port = candidate
                return
            } catch { continue }
        }
    }

    func stop() {
        server.stop()
        port = 0
    }

    func url(for remoteURL: URL, headers: [String: String] = [:]) -> URL? {
        guard port != 0 else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/proxy"
        var items = [URLQueryItem(name: "url", value: remoteURL.absoluteString)]
        if let data = try? JSONSerialization.data(withJSONObject: headers), let json = String(data: data, encoding: .utf8), !headers.isEmpty {
            items.append(URLQueryItem(name: "headers", value: json))
        }
        components.queryItems = items
        return components.url
    }

    private func proxy(_ incoming: HttpRequest) -> HttpResponse {
        let query = Dictionary(uniqueKeysWithValues: incoming.queryParams)
        guard let value = query["url"], let remoteURL = URL(string: value), ["http", "https"].contains(remoteURL.scheme?.lowercased() ?? "") else {
            return .badRequest(.text("Invalid proxy URL"))
        }
        var request = URLRequest(url: remoteURL)
        request.httpMethod = incoming.method == "HEAD" ? "HEAD" : "GET"
        if let range = incoming.headers["range"] { request.setValue(range, forHTTPHeaderField: "Range") }
        if let json = query["headers"], let data = json.data(using: .utf8), let headers = try? JSONDecoder().decode([String: String].self, from: data) {
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil { request.setValue("OK4KiOS/0.4", forHTTPHeaderField: "User-Agent") }

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, HTTPURLResponse, URL), Error>?
        session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error { result = .failure(error); return }
            guard let data, let response = response as? HTTPURLResponse else { result = .failure(URLError(.badServerResponse)); return }
            result = .success((data, response, response.url ?? remoteURL))
        }.resume()
        guard semaphore.wait(timeout: .now() + 125) == .success else { return .raw(504, "Gateway Timeout", nil, nil) }
        guard case .success(let payload) = result else { return .raw(502, "Bad Gateway", nil, nil) }

        var data = payload.0
        var headers: [String: String] = [:]
        for (key, value) in payload.1.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
        let contentType = payload.1.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("mpegurl") || remoteURL.pathExtension.lowercased() == "m3u8" {
            data = rewritePlaylist(data, baseURL: payload.2, requestHeaders: request.allHTTPHeaderFields ?? [:])
            headers.removeValue(forKey: "Content-Length")
            headers["Content-Type"] = "application/vnd.apple.mpegurl"
        }
        headers.removeValue(forKey: "Transfer-Encoding")
        headers["Access-Control-Allow-Origin"] = "*"
        return .raw(payload.1.statusCode, HTTPURLResponse.localizedString(forStatusCode: payload.1.statusCode), headers) { writer in try writer.write(data) }
    }

    private func rewritePlaylist(_ data: Data, baseURL: URL, requestHeaders: [String: String]) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        let output = text.components(separatedBy: .newlines).map { line -> String in
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty { return line }
            if clean.hasPrefix("#") { return rewriteURIAttributes(line, baseURL: baseURL, requestHeaders: requestHeaders) }
            guard let remote = URL(string: clean, relativeTo: baseURL)?.absoluteURL else { return line }
            return url(for: remote, headers: requestHeaders)?.absoluteString ?? line
        }.joined(separator: "\n")
        return output.data(using: .utf8) ?? data
    }

    private func rewriteURIAttributes(_ line: String, baseURL: URL, requestHeaders: [String: String]) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"URI=\"([^\"]+)\""#) else { return line }
        let range = NSRange(line.startIndex..., in: line)
        let matches = expression.matches(in: line, range: range).reversed()
        var output = line
        for match in matches {
            guard let valueRange = Range(match.range(at: 1), in: output) else { continue }
            let value = String(output[valueRange])
            guard let remote = URL(string: value, relativeTo: baseURL)?.absoluteURL,
                  let proxied = url(for: remote, headers: requestHeaders)?.absoluteString else { continue }
            output.replaceSubrange(valueRange, with: proxied)
        }
        return output
    }
}
