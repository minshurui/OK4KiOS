import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Native TVBox HTTP API adapter.
/// type 0 uses the legacy XML `videolist` protocol; type 1 uses JSON `detail`.
struct TVBoxAPIService: VodServiceProtocol {
    let site: TVBoxSite
    private let client: APIClientProtocol

    init(site: TVBoxSite, client: APIClientProtocol = APIClient()) {
        self.site = site
        self.client = client
    }

    func home(page: Int) async throws -> VodResult {
        try await request([])
    }

    func search(_ keyword: String, page: Int) async throws -> VodResult {
        try await request([
            URLQueryItem(name: "ac", value: action),
            URLQueryItem(name: "wd", value: keyword),
            URLQueryItem(name: "pg", value: String(page))
        ])
    }

    func category(id: String, page: Int) async throws -> VodResult {
        try await request([
            URLQueryItem(name: "ac", value: action),
            URLQueryItem(name: "t", value: id),
            URLQueryItem(name: "pg", value: String(page))
        ])
    }

    func detail(id: String) async throws -> Vod {
        let result = try await request([
            URLQueryItem(name: "ac", value: action),
            URLQueryItem(name: "ids", value: id)
        ])
        guard let vod = result.list.first else { throw VodServiceError.emptyDetail }
        return vod
    }

    func player(flag: String, id: String) async throws -> SpiderPlayback {
        SpiderPlayback(url: id, headers: site.headers)
    }

    private var action: String { site.type == 0 ? "videolist" : "detail" }

    private func request(_ queryItems: [URLQueryItem]) async throws -> VodResult {
        guard let baseURL = site.apiURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw VodServiceError.invalidURL
        }
        if !queryItems.isEmpty {
            var items = components.queryItems ?? []
            for item in queryItems {
                items.removeAll { $0.name == item.name }
                items.append(item)
            }
            components.queryItems = items
        }
        guard let url = components.url else { throw VodServiceError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("OK4KiOS/0.5", forHTTPHeaderField: "User-Agent")
        for (key, value) in site.headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, _) = try await client.data(for: request)
        if site.type == 0 { return try TVBoxXMLDecoder.decode(data) }
        return try JSONDecoder().decode(VodResult.self, from: data)
    }
}

private enum TVBoxXMLDecoder {
    static func decode(_ data: Data) throws -> VodResult {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? SpiderError.invalidResponse }
        return VodResult(
            code: LossyInt(1), msg: nil,
            page: LossyInt(delegate.page), pagecount: LossyInt(delegate.pageCount),
            limit: nil, total: nil, list: delegate.vods,
            class: delegate.classes
        )
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var classes: [VodClass] = []
        var vods: [Vod] = []
        var page = 1
        var pageCount = 1
        private var element = ""
        private var text = ""
        private var inClass = false
        private var inVideo = false
        private var classID = ""
        private var fields: [String: String] = [:]
        private var playURLs: [String] = []
        private var playFlags: [String] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            element = elementName.lowercased()
            text = ""
            if element == "class" {
                inClass = true
                classID = attributeDict["id"] ?? attributeDict["tid"] ?? ""
            } else if element == "video" {
                inVideo = true
                fields = [:]
                playURLs = []
                playFlags = []
            } else if element == "dd" && inVideo {
                playFlags.append(attributeDict["flag"] ?? "线路\(playFlags.count + 1)")
            } else if element == "list" {
                page = Int(attributeDict["page"] ?? "") ?? 1
                pageCount = Int(attributeDict["pagecount"] ?? attributeDict["pageCount"] ?? "") ?? 1
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            text += String(data: CDATABlock, encoding: .utf8) ?? ""
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let name = elementName.lowercased()
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if inVideo && name != "video" && !value.isEmpty {
                if name == "dd" { playURLs.append(value) }
                else { fields[name] = value }
            }
            if name == "class" && inClass {
                if !value.isEmpty { classes.append(VodClass(typeID: LossyString(classID), typeName: LossyString(value), typeFlag: nil)) }
                inClass = false
            } else if name == "video" {
                vods.append(Vod(
                    vodID: LossyString(fields["id"] ?? fields["vod_id"] ?? ""),
                    vodName: LossyString(fields["name"] ?? fields["vod_name"] ?? ""),
                    typeName: LossyString(fields["type"] ?? fields["type_name"] ?? ""),
                    vodPic: LossyString(fields["pic"] ?? fields["vod_pic"] ?? ""),
                    vodRemarks: LossyString(fields["note"] ?? fields["vod_remarks"] ?? ""),
                    vodYear: LossyString(fields["year"] ?? ""), vodArea: LossyString(fields["area"] ?? ""),
                    vodDirector: LossyString(fields["director"] ?? ""), vodActor: LossyString(fields["actor"] ?? ""),
                    vodContent: LossyString(fields["des"] ?? fields["content"] ?? ""),
                    vodPlayFrom: LossyString(playFlags.isEmpty ? (fields["dt"] ?? fields["from"] ?? fields["vod_play_from"] ?? "") : playFlags.joined(separator: "$$$")),
                    vodPlayURL: LossyString(playURLs.isEmpty ? (fields["dl"] ?? fields["url"] ?? fields["vod_play_url"] ?? "") : playURLs.joined(separator: "$$$"))
                ))
                inVideo = false
                fields = [:]
            }
            element = ""
            text = ""
        }
    }
}
