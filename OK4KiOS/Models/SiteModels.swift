import Foundation

struct TVBoxConfig: Decodable {
    let spider: String
    let sites: [TVBoxSite]

    enum CodingKeys: String, CodingKey { case spider, sites }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spider = (try? container.decode(String.self, forKey: .spider)) ?? ""
        var decodedSites = (try? container.decode([TVBoxSite].self, forKey: .sites)) ?? []
        for index in decodedSites.indices where decodedSites[index].jar.isEmpty {
            decodedSites[index].jar = spider
        }
        sites = decodedSites
    }
}

struct TVBoxSite: Codable, Identifiable, Hashable, Sendable {
    let key: String
    let name: String
    let type: Int
    let api: String
    let searchable: Bool
    let quickSearch: Bool
    let filterable: Bool
    let ext: JSONValue?
    var jar: String
    let headers: [String: String]

    var id: String { key.isEmpty ? name + api : key }
    var apiURL: URL? { URL(string: api.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var nativeBaseURLs: [URL] { ext?.candidateURLs ?? [] }
    var isBrowsableVodSite: Bool {
        // TVBox configurations also expose Android-only utility entries as
        // type 3 sites. They are actions/settings, not VOD catalogues.
        let utilityKeys: Set<String> = ["fishconfig", "config", "push_agent", "proxy"]
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedAPI = api.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !utilityKeys.contains(normalizedKey)
            && !normalizedAPI.contains("csp_fishconfig")
    }
    var canRunNatively: Bool { isBrowsableVodSite && (type == 0 || type == 1 || (type == 3 && !nativeBaseURLs.isEmpty)) }
    var kindLabel: String {
        switch type {
        case 0: return "XML"
        case 1: return "JSON"
        case 3: return nativeBaseURLs.isEmpty ? "Spider 网关" : "Spider 原生/网关"
        case 4: return "规则网关"
        default: return "Type \(type)"
        }
    }

    enum CodingKeys: String, CodingKey {
        case key, name, type, api, searchable, quickSearch = "quickSearch", filterable, ext, jar, header, headers
    }

    init(key: String, name: String, type: Int, api: String, searchable: Bool = true, quickSearch: Bool = true, filterable: Bool = false, ext: JSONValue? = nil, jar: String = "", headers: [String: String] = [:]) {
        self.key = key
        self.name = name
        self.type = type
        self.api = api
        self.searchable = searchable
        self.quickSearch = quickSearch
        self.filterable = filterable
        self.ext = ext
        self.jar = jar
        self.headers = headers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decode(String.self, forKey: .key)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? key
        type = (try? container.decode(Int.self, forKey: .type)) ?? 0
        api = (try? container.decode(String.self, forKey: .api)) ?? ""
        searchable = Self.bool(container, .searchable, default: true)
        quickSearch = Self.bool(container, .quickSearch, default: true)
        filterable = Self.bool(container, .filterable, default: false)
        ext = try? container.decode(JSONValue.self, forKey: .ext)
        jar = (try? container.decode(String.self, forKey: .jar)) ?? ""
        headers = (try? container.decode([String: String].self, forKey: .header))
            ?? (try? container.decode([String: String].self, forKey: .headers))
            ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(api, forKey: .api)
        try container.encode(searchable, forKey: .searchable)
        try container.encode(quickSearch, forKey: .quickSearch)
        try container.encode(filterable, forKey: .filterable)
        try container.encodeIfPresent(ext, forKey: .ext)
        try container.encode(jar, forKey: .jar)
        try container.encode(headers, forKey: .header)
    }

    private static func bool(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, default fallback: Bool) -> Bool {
        if let value = try? container.decode(Bool.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? container.decode(String.self, forKey: key) { return value == "1" || value.lowercased() == "true" }
        return fallback
    }
}
