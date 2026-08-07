import Foundation

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode([String: JSONValue].self) { self = .object(item) }
        else if let item = try? value.decode([JSONValue].self) { self = .array(item) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .bool(let item): try value.encode(item)
        case .object(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .null: try value.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var encodedString: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    var candidateURLs: [URL] {
        var values: [String] = []
        collectStrings(into: &values)
        return values.compactMap { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: clean), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return url
        }
    }

    private func collectStrings(into values: inout [String]) {
        switch self {
        case .string(let value):
            values.append(contentsOf: value.components(separatedBy: ","))
        case .object(let object):
            for key in ["site", "url", "host", "api"] { object[key]?.collectStrings(into: &values) }
        case .array(let array):
            array.forEach { $0.collectStrings(into: &values) }
        default: break
        }
    }
}
