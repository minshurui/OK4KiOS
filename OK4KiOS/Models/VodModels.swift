import Foundation

struct VodResult: Codable, Sendable {
    let code: LossyInt?
    let msg: String?
    let page: LossyInt?
    let pagecount: LossyInt?
    let limit: LossyInt?
    let total: LossyInt?
    let list: [Vod]
    let `class`: [VodClass]?

    var types: [VodClass] { `class` ?? [] }
}

struct VodClass: Codable, Identifiable, Hashable, Sendable {
    let typeID: LossyString?
    let typeName: LossyString?
    let typeFlag: LossyString?

    var id: String {
        let value = typeID?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "class-\(name)" : value
    }
    var name: String {
        let value = typeName?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "未命名" : value
    }

    enum CodingKeys: String, CodingKey {
        case typeID = "type_id"
        case typeName = "type_name"
        case typeFlag = "type_flag"
    }
}

struct Vod: Codable, Identifiable, Hashable, Sendable {
    let vodID: LossyString?
    let vodName: LossyString?
    let typeName: LossyString?
    let vodPic: LossyString?
    let vodRemarks: LossyString?
    let vodYear: LossyString?
    let vodArea: LossyString?
    let vodDirector: LossyString?
    let vodActor: LossyString?
    let vodContent: LossyString?
    let vodPlayFrom: LossyString?
    let vodPlayURL: LossyString?

    var id: String {
        let value = vodID?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !value.isEmpty { return value }
        return "vod-\(name)-\(vodPic?.value.hashValue ?? 0)"
    }
    var name: String {
        let value = vodName?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "未命名" : value
    }
    var imageURL: URL? { URL(string: vodPic?.value ?? "") }
    var remark: String { vodRemarks?.value ?? "" }
    var content: String { (vodContent?.value ?? "").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) }

    var flags: [PlayFlag] {
        let names = (vodPlayFrom?.value ?? "").components(separatedBy: "$$$").filter { !$0.isEmpty }
        let groups = (vodPlayURL?.value ?? "").components(separatedBy: "$$$").filter { !$0.isEmpty }
        return groups.enumerated().compactMap { index, value in
            let episodes = value.components(separatedBy: "#").filter { !$0.isEmpty }.enumerated().compactMap { episodeIndex, part -> Episode? in
                let separator = part.firstIndex(of: "$")
                let rawName = separator.map { String(part[..<$0]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                let rawURL = separator.map { String(part[part.index(after: $0)...]) } ?? part
                let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedURL.isEmpty else { return nil }
                return Episode(name: rawName.isEmpty ? "第\(episodeIndex + 1)集" : rawName, url: trimmedURL)
            }
            guard !episodes.isEmpty else { return nil }
            let name = index < names.count && !names[index].isEmpty ? names[index] : "线路\(index + 1)"
            return PlayFlag(name: name, episodes: episodes)
        }
    }

    enum CodingKeys: String, CodingKey {
        case vodID = "vod_id", vodName = "vod_name", typeName = "type_name"
        case vodPic = "vod_pic", vodRemarks = "vod_remarks", vodYear = "vod_year"
        case vodArea = "vod_area", vodDirector = "vod_director", vodActor = "vod_actor"
        case vodContent = "vod_content", vodPlayFrom = "vod_play_from", vodPlayURL = "vod_play_url"
    }
}

struct PlayFlag: Identifiable, Hashable, Sendable {
    let name: String
    let episodes: [Episode]
    var id: String { name + "|" + (episodes.first?.url ?? "") }
}

struct Episode: Identifiable, Hashable, Sendable {
    let name: String
    let url: String
    var id: String { name + "|" + url }
}
