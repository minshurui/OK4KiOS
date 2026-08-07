import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct LiveService {
    private let client: APIClientProtocol
    private let maxNestedDepth = 4

    init(client: APIClientProtocol = APIClient()) {
        self.client = client
    }

    enum LiveError: LocalizedError {
        case invalidURL
        case invalidPlaylist
        case tooDeep

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "直播源地址无效"
            case .invalidPlaylist: return "无法解析直播源，请确认是 M3U/TXT/JSON 或 TVBox 配置地址"
            case .tooDeep: return "直播源嵌套过深，已停止展开"
            }
        }
    }

    // MARK: - Public API

    func load(urlString: String) async throws -> [LiveGroup] {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw LiveError.invalidURL
        }
        return try await load(url: url, depth: 0)
    }

    /// Synchronous parse for tests and local strings (no network / no nested expansion).
    func parse(_ text: String) -> [LiveGroup] {
        parse(text, baseURL: URL(string: "https://local.invalid/")!)
    }

    func parse(_ text: String, baseURL: URL) -> [LiveGroup] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return parseJSON(trimmed, baseURL: baseURL)
        }
        if trimmed.hasPrefix("<"), trimmed.contains("EXTM3U") {
            return parsePlaylist(trimmed, baseURL: baseURL)
        }
        return parsePlaylist(trimmed, baseURL: baseURL)
    }

    // MARK: - Loading

    private func load(url: URL, depth: Int) async throws -> [LiveGroup] {
        guard depth <= maxNestedDepth else { throw LiveError.tooDeep }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("VLC/3.0.21 LibVLC/3.0.21", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await client.data(for: request)
        let baseURL = response.url ?? url
        guard let text = decode(data) else { throw LiveError.invalidPlaylist }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return try await loadJSONAsync(trimmed, baseURL: baseURL, depth: depth)
        }
        let groups = parse(text, baseURL: baseURL)
        var result = groups
        for nested in collectNestedURLs(text, baseURL: baseURL) {
            result = mergeGroups(result, try await load(url: nested, depth: depth + 1))
        }
        return result
    }

    private func loadJSONAsync(_ text: String, baseURL: URL, depth: Int) async throws -> [LiveGroup] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            throw LiveError.invalidPlaylist
        }
        var result: [LiveGroup] = []
        if let dictionary = object as? [String: Any] {
            if let lives = dictionary["lives"] as? [[String: Any]] {
                for live in lives {
                    guard let name = live["name"] as? String, !name.isEmpty,
                          let urlString = live["url"] as? String, !urlString.isEmpty else { continue }
                    let type = live["type"] as? Int ?? 0
                    let ua = live["ua"] as? String ?? ""
                    let headers: [String: String] = ua.isEmpty ? [:] : ["User-Agent": ua]
                    let resolved = resolvedURL(urlString, baseURL: baseURL)
                    if isPlaylistURL(urlString) || type == 1 {
                        result = mergeGroups(result, try await load(url: resolved, depth: depth + 1))
                    } else if URL(string: urlString) != nil {
                        result = appendChannel([LiveChannel(name: name, url: resolved, group: "直播", headers: headers)], to: result)
                    }
                }
            } else if let urls = dictionary["urls"] as? [[String: Any]] {
                for entry in urls {
                    guard let name = entry["name"] as? String, !name.isEmpty,
                          let urlString = entry["url"] as? String, !urlString.isEmpty else { continue }
                    let ua = entry["ua"] as? String ?? ""
                    let headers: [String: String] = ua.isEmpty ? [:] : ["User-Agent": ua]
                    let resolved = resolvedURL(urlString, baseURL: baseURL)
                    if isPlaylistURL(urlString) {
                        result = mergeGroups(result, try await load(url: resolved, depth: depth + 1))
                    } else {
                        result = appendChannel([LiveChannel(name: name, url: resolved, group: "直播", headers: headers)], to: result)
                    }
                }
            } else if let list = dictionary["list"] as? [[String: Any]] {
                result = parseGenericList(list, baseURL: baseURL)
            } else if let source = dictionary["url"] as? String {
                let resolved = resolvedURL(source, baseURL: baseURL)
                if resolved != baseURL {
                    result = mergeGroups(result, try await load(url: resolved, depth: depth + 1))
                }
            }
        } else if let array = object as? [[String: Any]] {
            result = parseGenericList(array, baseURL: baseURL)
        }
        return result
    }

    private func collectNestedURLs(_ text: String, baseURL: URL) -> [URL] {
        var result: [URL] = []
        for line in text.components(separatedBy: .newlines) {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty, !clean.hasPrefix("#"), isPlaylistURL(clean),
               let nested = absoluteURL(clean, relativeTo: baseURL) {
                result.append(nested)
            }
        }
        return result
    }

    // MARK: - Parsing

    private func parsePlaylist(_ text: String, baseURL: URL) -> [LiveGroup] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var channels: [LiveChannel] = []
        var pendingName = ""
        var pendingGroup = "未分组"
        var pendingLogo: String?
        var pendingHeaders: [String: String] = [:]

        for line in lines {
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#EXTINF") {
                pendingName = nameFromEXTINF(line)
                pendingGroup = groupFromEXTINF(line)
                pendingLogo = logoFromEXTINF(line)
                pendingHeaders = [:]
                if let headers = headersFromLine(line, baseURL: baseURL) { pendingHeaders = headers }
            } else if line.hasPrefix("#EXTGRP:") {
                let value = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { pendingGroup = value }
            } else if line.hasPrefix("#KODIPROP") {
                if let headers = headersFromLine(line, baseURL: baseURL) { pendingHeaders.merge(headers) { $1 } }
            } else if line.hasPrefix("#") {
                continue
            } else if isPlaylistURL(line) {
                continue
            } else if !pendingName.isEmpty, let entry = streamEntry(from: line) {
                var merged = pendingHeaders
                for (key, value) in entry.headers { merged[key] = value }
                channels.append(LiveChannel(name: pendingName, url: entry.url, group: pendingGroup, headers: merged, logoURL: pendingLogo.flatMap { URL(string: $0) }))
                pendingName = ""
            } else if line.contains(","), let entry = txtEntry(from: line) {
                channels.append(LiveChannel(name: entry.name, url: entry.url, group: pendingGroup))
            } else if !line.contains("://") {
                continue
            } else if let entry = streamEntry(from: line) {
                let name = entry.url.lastPathComponent.isEmpty ? "直播 \(channels.count + 1)" : entry.url.lastPathComponent
                channels.append(LiveChannel(name: name, url: entry.url, group: pendingGroup, headers: entry.headers))
            }
        }
        return makeGroups(channels)
    }

    private func parseJSON(_ text: String, baseURL: URL) -> [LiveGroup] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return []
        }
        if let dictionary = object as? [String: Any] {
            if let lives = dictionary["lives"] as? [[String: Any]] {
                return parseTVBoxLives(lives, baseURL: baseURL)
            }
            if let urls = dictionary["urls"] as? [[String: Any]] {
                return parseTVBoxURLs(urls, baseURL: baseURL)
            }
            if let list = dictionary["list"] as? [[String: Any]] {
                return parseGenericList(list, baseURL: baseURL)
            }
            if let source = dictionary["url"] as? String {
                let resolved = resolvedURL(source, baseURL: baseURL)
                guard resolved != baseURL else { return [] }
                return [LiveGroup(id: "直播", name: "直播", channels: [LiveChannel(name: "直播", url: resolved)])]
            }
        }
        if let array = object as? [[String: Any]] {
            return parseGenericList(array, baseURL: baseURL)
        }
        return []
    }

    private func parseTVBoxLives(_ lives: [[String: Any]], baseURL: URL) -> [LiveGroup] {
        var result: [LiveGroup] = []
        for live in lives {
            guard let name = live["name"] as? String, !name.isEmpty,
                  let urlString = live["url"] as? String, !urlString.isEmpty else { continue }
            let ua = live["ua"] as? String ?? ""
            let headers: [String: String] = ua.isEmpty ? [:] : ["User-Agent": ua]
            // Playlist URLs are expanded by async loading; sync parse keeps direct streams only.
            if !isPlaylistURL(urlString), let url = URL(string: urlString), url.scheme != nil {
                result = appendChannel([LiveChannel(name: name, url: url, group: "直播", headers: headers)], to: result)
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func parseTVBoxURLs(_ urls: [[String: Any]], baseURL: URL) -> [LiveGroup] {
        var result: [LiveGroup] = []
        for entry in urls {
            guard let name = entry["name"] as? String, !name.isEmpty,
                  let urlString = entry["url"] as? String, !urlString.isEmpty else { continue }
            let ua = entry["ua"] as? String ?? ""
            let headers: [String: String] = ua.isEmpty ? [:] : ["User-Agent": ua]
            if let url = URL(string: urlString), url.scheme != nil {
                result = appendChannel([LiveChannel(name: name, url: url, group: "直播", headers: headers)], to: result)
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func parseGenericList(_ list: [[String: Any]], baseURL: URL) -> [LiveGroup] {
        var result: [LiveGroup] = []
        for entry in list {
            let name = (entry["name"] as? String) ?? (entry["title"] as? String) ?? ""
            let urlString = (entry["url"] as? String) ?? ""
            guard !name.isEmpty, !urlString.isEmpty else { continue }
            let group = (entry["group"] as? String) ?? (entry["group-title"] as? String) ?? "未分组"
            if let url = URL(string: urlString), url.scheme != nil {
                result = appendChannel([LiveChannel(name: name, url: url, group: group)], to: result)
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Helpers

    private func makeGroups(_ channels: [LiveChannel]) -> [LiveGroup] {
        Dictionary(grouping: channels, by: { $0.group })
            .map { LiveGroup(id: $0.key, name: $0.key, channels: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func appendChannel(_ channels: [LiveChannel], to groups: [LiveGroup]) -> [LiveGroup] {
        var result = groups
        for channel in channels {
            if let index = result.firstIndex(where: { $0.id == channel.group }) {
                result[index].channels.append(channel)
            } else {
                result.append(LiveGroup(id: channel.group, name: channel.group, channels: [channel]))
            }
        }
        return result
    }

    private func mergeGroups(_ base: [LiveGroup], _ extra: [LiveGroup]) -> [LiveGroup] {
        var result = base
        for group in extra {
            if let index = result.firstIndex(where: { $0.id == group.id }) {
                var merged = result[index]
                merged.channels.append(contentsOf: group.channels)
                result[index] = merged
            } else {
                result.append(group)
            }
        }
        return result
    }

    private func isPlaylistURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.contains(".m3u8") { return false }
        if lower.contains(".m3u") || lower.contains(".txt") || lower.contains("m3u") { return true }
        return false
    }

    private func resolvedURL(_ value: String, baseURL: URL) -> URL {
        if let url = URL(string: value), url.scheme != nil { return url }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL ?? baseURL
    }

    private func absoluteURL(_ value: String, relativeTo baseURL: URL) -> URL? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: clean), url.scheme != nil { return url }
        return URL(string: clean, relativeTo: baseURL)?.absoluteURL
    }

    private func decode(_ data: Data) -> String? {
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return nil
    }

    private func txtEntry(from line: String) -> (name: String, url: URL)? {
        let parts = line.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let name = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let url = URL(string: value), url.scheme != nil else { return nil }
        return (name, url)
    }

    private func nameFromEXTINF(_ line: String) -> String {
        let tail = line.split(separator: ",", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        return tail.isEmpty ? "未命名频道" : tail
    }

    private func groupFromEXTINF(_ line: String) -> String {
        guard let range = line.range(of: "group-title=\"") else { return "未分组" }
        let tail = line[range.upperBound...]
        let value = String(tail.split(separator: "\"", maxSplits: 1).first ?? "")
        return value.isEmpty ? "未分组" : value.replacingOccurrences(of: ";", with: ",")
    }

    private func logoFromEXTINF(_ line: String) -> String? {
        guard let range = line.range(of: "tvg-logo=\"") else { return nil }
        let tail = line[range.upperBound...]
        return String(tail.split(separator: "\"", maxSplits: 1).first ?? "")
    }

    private func streamEntry(from line: String) -> (url: URL, headers: [String: String])? {
        let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let urlPart = parts.first else { return nil }
        let urlString = String(urlPart).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString) else { return nil }
        var headers: [String: String] = [:]
        if parts.count > 1 {
            headers = parseHeaderSuffix(String(parts[1]))
        }
        return (url, headers)
    }

    private func headersFromLine(_ line: String, baseURL: URL) -> [String: String]? {
        guard let range = line.range(of: "|") else { return nil }
        let headers = parseHeaderSuffix(String(line[range.upperBound...]))
        return headers.isEmpty ? nil : headers
    }

    private func parseHeaderSuffix(_ suffix: String) -> [String: String] {
        var headers: [String: String] = [:]
        for pair in suffix.split(separator: "&", omittingEmptySubsequences: true) {
            let fields = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { continue }
            let rawKey = String(fields[0]).replacingOccurrences(of: "+", with: " ")
            let rawValue = String(fields[1]).replacingOccurrences(of: "+", with: " ")
            let key = rawKey.removingPercentEncoding ?? rawKey
            let value = rawValue.removingPercentEncoding ?? rawValue
            if !key.isEmpty, !value.isEmpty { headers[normalizedHeader(key)] = value }
        }
        return headers
    }

    private func normalizedHeader(_ key: String) -> String {
        switch key.lowercased() {
        case "user-agent", "user_agent": return "User-Agent"
        case "referer", "referrer": return "Referer"
        case "origin": return "Origin"
        case "cookie": return "Cookie"
        default: return key
        }
    }
}
