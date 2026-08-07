import Foundation
import SwiftSoup
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct NativeSpiderService: VodServiceProtocol {
    let site: TVBoxSite
    private let client: APIClientProtocol
    private let baseURL: URL

    init(site: TVBoxSite, client: APIClientProtocol = APIClient()) throws {
        guard let url = site.nativeBaseURLs.first else { throw SpiderError.noUsableHost }
        self.site = site
        self.client = client
        self.baseURL = url
    }

    func home(page: Int) async throws -> VodResult {
        try await listing(url: pageURL(baseURL, page: page), page: page, includeClasses: true)
    }

    func search(_ keyword: String, page: Int) async throws -> VodResult {
        var components = URLComponents(url: baseURL.appendingPathComponent("vodsearch/-------------.html"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "wd", value: keyword)]
        guard let url = components?.url else { throw SpiderError.invalidResponse }
        return try await listing(url: url, page: page, includeClasses: false)
    }

    func category(id: String, page: Int) async throws -> VodResult {
        let clean = id.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let first = absoluteURL(clean.hasPrefix("http") ? clean : "/vodtype/\(clean).html", relativeTo: baseURL)
        guard let first else { throw SpiderError.invalidResponse }
        return try await listing(url: pageURL(first, page: page), page: page, includeClasses: false)
    }

    func detail(id: String) async throws -> Vod {
        guard let url = absoluteURL(id, relativeTo: baseURL) else { throw SpiderError.invalidResponse }
        let document = try await html(url)
        let name = firstText(document, selectors: ["h1", ".module-info-heading h1", ".page-title", ".video-info-header h3"], fallback: "未命名")
        let picture = firstAttribute(document, selectors: [".module-info-poster img", ".video-cover img", ".detail-pic img", ".lazy"], attributes: ["data-src", "data-original", "src"])
        let content = firstText(document, selectors: [".module-info-introduction-content", ".video-info-content", ".vod_content", ".detail-content"], fallback: "")
        let remark = firstText(document, selectors: [".module-info-item-content", ".video-info-aux", ".module-info-tag"], fallback: "")
        let groups = try episodeGroups(document, pageURL: url)
        let playFrom = groups.map(\.0).joined(separator: "$$$")
        let playURL = groups.map { group in group.1.map { "\($0.name)$\($0.url)" }.joined(separator: "#") }.joined(separator: "$$$")
        return Vod(vodID: LossyString(url.absoluteString), vodName: LossyString(name), typeName: nil,
                   vodPic: LossyString(absoluteURL(picture, relativeTo: url)?.absoluteString ?? picture),
                   vodRemarks: LossyString(remark), vodYear: nil, vodArea: nil, vodDirector: nil, vodActor: nil,
                   vodContent: LossyString(content), vodPlayFrom: LossyString(playFrom), vodPlayURL: LossyString(playURL))
    }

    func player(flag: String, id: String) async throws -> SpiderPlayback {
        guard let url = absoluteURL(id, relativeTo: baseURL) else { throw SpiderError.noPlayableURL }
        if isMediaURL(url) { return SpiderPlayback(url: url.absoluteString, headers: defaultHeaders(referer: baseURL)) }
        let document = try await html(url)
        let sourceSelectors = ["video source", "video", "audio source", "audio"]
        if let media = try? document.select(sourceSelectors.joined(separator: ",")).first(),
           let source = try? firstNonemptyAttribute(media, ["src", "data-src"]),
           let resolved = absoluteURL(source, relativeTo: url), isMediaURL(resolved) {
            return SpiderPlayback(url: resolved.absoluteString, headers: defaultHeaders(referer: url))
        }
        let raw = try document.html()
        for pattern in [#"https?:\\?/\\?/[^\"'\\s]+?\\.(?:m3u8|mp4|mkv|flv|mpd)(?:\?[^\"'\\s]*)?"#,
                        #"[\"']url[\"']\s*:\s*[\"']([^\"']+)[\"']"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            for match in regex.matches(in: raw, range: range) {
                let index = match.numberOfRanges > 1 ? 1 : 0
                guard let matchRange = Range(match.range(at: index), in: raw) else { continue }
                let value = String(raw[matchRange]).replacingOccurrences(of: "\\/", with: "/")
                if let resolved = absoluteURL(value, relativeTo: url), isMediaURL(resolved) {
                    return SpiderPlayback(url: resolved.absoluteString, headers: defaultHeaders(referer: url))
                }
            }
        }
        throw SpiderError.noPlayableURL
    }

    private func listing(url: URL, page: Int, includeClasses: Bool) async throws -> VodResult {
        let document = try await html(url)
        var items: [Vod] = []
        let selectors = [".module-item", ".module-card-item", ".vodlist li", ".myui-vodlist__box", ".stui-vodlist__box", ".video-item"]
        for element in try document.select(selectors.joined(separator: ",")) {
            guard let link = try? element.select("a[href]").first(), let href = try? link.attr("href"),
                  href.contains("detail") || href.contains("vod") else { continue }
            let title = (try? link.attr("title")).flatMap { $0.isEmpty ? nil : $0 } ?? (try? link.text()) ?? ""
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let detailURL = absoluteURL(href, relativeTo: url) else { continue }
            let image = (try? element.select("img").first()).flatMap { try? firstNonemptyAttribute($0, ["data-src", "data-original", "src"]) } ?? ""
            let remark = firstText(element, selectors: [".module-item-text", ".pic-text", ".text-right", ".remarks"], fallback: "")
            let vod = Vod(vodID: LossyString(detailURL.absoluteString), vodName: LossyString(title), typeName: nil,
                          vodPic: LossyString(absoluteURL(image, relativeTo: url)?.absoluteString ?? image), vodRemarks: LossyString(remark),
                          vodYear: nil, vodArea: nil, vodDirector: nil, vodActor: nil, vodContent: nil, vodPlayFrom: nil, vodPlayURL: nil)
            if !items.contains(where: { $0.id == vod.id }) { items.append(vod) }
        }
        let types = includeClasses ? try classes(document, pageURL: url) : []
        let hasNext = (try? document.select("a").array().contains { element in
            let text = (try? element.text()) ?? ""
            return text.contains("下一页") || text.lowercased().contains("next")
        }) ?? false
        return VodResult(code: LossyInt(1), msg: nil, page: LossyInt(page), pagecount: LossyInt(hasNext ? page + 1 : page), limit: nil, total: nil, list: items, class: types)
    }

    private func classes(_ document: Document, pageURL: URL) throws -> [VodClass] {
        var result: [VodClass] = []
        for link in try document.select("a[href*=/vodtype/], a[href*=/vodshow/]") {
            let name = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let href = try link.attr("href")
            guard !name.isEmpty else { continue }
            let pattern = #"/(?:vodtype|vodshow)/([^/.-]+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: href, range: NSRange(href.startIndex..<href.endIndex, in: href)),
                  let range = Range(match.range(at: 1), in: href) else { continue }
            let id = String(href[range])
            let item = VodClass(typeID: LossyString(id), typeName: LossyString(name), typeFlag: nil)
            if !result.contains(where: { $0.id == item.id }) { result.append(item) }
        }
        return Array(result.prefix(30))
    }

    private func episodeGroups(_ document: Document, pageURL: URL) throws -> [(String, [Episode])] {
        let listSelectors = [".module-play-list", ".anthology-list-play", ".content_playlist", ".playlist", ".stui-content__playlist", ".myui-content__list"]
        var groups: [(String, [Episode])] = []
        for (index, list) in try document.select(listSelectors.joined(separator: ",")).enumerated() {
            var episodes: [Episode] = []
            for link in try list.select("a[href]") {
                let href = try link.attr("href")
                guard let resolved = absoluteURL(href, relativeTo: pageURL) else { continue }
                let name = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
                episodes.append(Episode(name: name.isEmpty ? "播放" : name, url: resolved.absoluteString))
            }
            if !episodes.isEmpty { groups.append(("线路\(index + 1)", episodes)) }
        }
        if groups.isEmpty {
            var episodes: [Episode] = []
            for link in try document.select("a[href]") {
                let href = try link.attr("href")
                guard href.contains("play") || isMediaString(href), let resolved = absoluteURL(href, relativeTo: pageURL) else { continue }
                let name = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
                episodes.append(Episode(name: name.isEmpty ? "播放" : name, url: resolved.absoluteString))
            }
            if !episodes.isEmpty { groups = [("在线播放", episodes)] }
        }
        return groups
    }

    private func html(_ url: URL) async throws -> Document {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        defaultHeaders(referer: baseURL).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, _) = try await client.data(for: request)
        let encoding = String.Encoding.utf8
        guard let text = String(data: data, encoding: encoding) ?? String(data: data, encoding: .isoLatin1) else { throw SpiderError.invalidResponse }
        return try SwiftSoup.parse(text, url.absoluteString)
    }

    private func pageURL(_ url: URL, page: Int) -> URL {
        guard page > 1 else { return url }
        let value = url.absoluteString
        if value.hasSuffix(".html") { return URL(string: value.replacingOccurrences(of: ".html", with: "-\(page).html")) ?? url }
        return url
    }

    private func absoluteURL(_ value: String, relativeTo url: URL) -> URL? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let absolute = URL(string: clean), absolute.scheme != nil { return absolute }
        return URL(string: clean, relativeTo: url)?.absoluteURL
    }

    private func defaultHeaders(referer: URL) -> [String: String] {
        ["User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 15_4 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", "Referer": referer.absoluteString]
    }

    private func isMediaString(_ value: String) -> Bool { [".m3u8", ".mp4", ".mkv", ".flv", ".mpd", ".ts"].contains { value.lowercased().contains($0) } }
    private func isMediaURL(_ url: URL) -> Bool { isMediaString(url.absoluteString) }

    private func firstText(_ element: Element, selectors: [String], fallback: String) -> String {
        for selector in selectors {
            if let node = try? element.select(selector).first(), let value = try? node.text(), !value.isEmpty { return value }
        }
        return fallback
    }

    private func firstAttribute(_ element: Element, selectors: [String], attributes: [String]) -> String {
        for selector in selectors {
            if let node = try? element.select(selector).first(), let value = try? firstNonemptyAttribute(node, attributes), !value.isEmpty { return value }
        }
        return ""
    }

    private func firstNonemptyAttribute(_ element: Element, _ attributes: [String]) throws -> String {
        for attribute in attributes { let value = try element.attr(attribute); if !value.isEmpty { return value } }
        return ""
    }
}
