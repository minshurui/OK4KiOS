import Foundation

struct TVBoxConfig: Decodable {
    let spider: String
    let sites: [TVBoxSite]

    enum CodingKeys: String, CodingKey { case spider, sites }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spider = (try? container.decode(String.self, forKey: .spider)) ?? ""
        sites = (try? container.decode([TVBoxSite].self, forKey: .sites)) ?? []
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

    var id: String { key.isEmpty ? name + api : key }
    var apiURL: URL? { URL(string: api.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var nativeBaseURLs: [URL] { ext?.candidateURLs ?? [] }
    var canRunNatively: Bool { type == 0 || type == 1 || (type == 3 && !nativeBaseURLs.isEmpty) }

    enum CodingKeys: String, CodingKey {
        case key, name, type, api, searchable, quickSearch = "quickSearch", filterable, ext
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
    }

    private static func bool(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, default fallback: Bool) -> Bool {
        if let value = try? container.decode(Bool.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? container.decode(String.self, forKey: key) { return value == "1" || value.lowercased() == "true" }
        return fallback
    }
}
