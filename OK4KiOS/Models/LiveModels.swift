import Foundation

struct LiveChannel: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let group: String
}

struct LiveGroup: Identifiable {
    let id: String
    let name: String
    let channels: [LiveChannel]
}
