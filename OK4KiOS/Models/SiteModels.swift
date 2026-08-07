import Foundation

struct TVBoxConfig: Decodable {
    let sites: [TVBoxSite]

    enum CodingKeys: String, CodingKey { case sites }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sites = (try? container.decode([TVBoxSite].self, forKey: .sites)) ?? []
    }
}

struct TVBoxSite: Decodable, Identifiable, Hashable {
    let key: String
    let name: String
    let type: Int
    let api: String
    let searchable: Bool
    let quickSearch: Bool
    let filterable: Bool

    var id: String { key.isEmpty ? name + api : key }
    var apiURL: URL? { URL(string: api.trimmingCharacters(in: .whitespacesAndNewlines)) }

    enum CodingKeys: String, CodingKey {
        case key, name, type, api, searchable, quickSearch = "quickSearch", filterable
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
    }

    private static func bool(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, default fallback: Bool) -> Bool {
        if let value = try? container.decode(Bool.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? container.decode(String.self, forKey: key) { return value == "1" || value.lowercased() == "true" }
        return fallback
    }
}
