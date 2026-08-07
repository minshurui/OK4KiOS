import Foundation

struct LiveChannel: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let group: String
    let headers: [String: String]
    let logoURL: URL?

    init(id: String? = nil, name: String, url: URL, group: String = "未分组", headers: [String: String] = [:], logoURL: URL? = nil) {
        self.id = id ?? "\(name)|\(url.absoluteString)"
        self.name = name
        self.url = url
        self.group = group.isEmpty ? "未分组" : group
        self.headers = headers
        self.logoURL = logoURL
    }
}

struct LiveGroup: Identifiable {
    let id: String
    let name: String
    var channels: [LiveChannel]
}
