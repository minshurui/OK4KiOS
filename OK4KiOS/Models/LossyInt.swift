import Foundation

struct LossyInt: Codable, Hashable, Sendable {
    let value: Int

    init(_ value: Int = 0) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self.value = value
        } else if let value = try? container.decode(String.self), let int = Int(value) {
            self.value = int
        } else {
            self.value = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
