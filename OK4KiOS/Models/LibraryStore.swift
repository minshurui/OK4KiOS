import Combine
import Foundation

struct LibraryEntry: Codable, Identifiable, Hashable {
    let vod: Vod
    var episodeName: String?
    var episodeURL: String?
    var updatedAt: Date

    var id: String { vod.id }
}

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var favorites: [LibraryEntry] = []
    @Published private(set) var history: [LibraryEntry] = []

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Keys {
        static let favorites = "library.favorites"
        static let history = "library.history"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = Self.load(Keys.favorites, defaults: defaults, decoder: decoder)
        history = Self.load(Keys.history, defaults: defaults, decoder: decoder)
    }

    func isFavorite(_ vod: Vod) -> Bool {
        favorites.contains { $0.vod.id == vod.id }
    }

    func toggleFavorite(_ vod: Vod) {
        if let index = favorites.firstIndex(where: { $0.vod.id == vod.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(LibraryEntry(vod: vod, updatedAt: Date()), at: 0)
        }
        save(favorites, key: Keys.favorites)
    }

    func record(_ vod: Vod, episode: Episode) {
        history.removeAll { $0.vod.id == vod.id }
        history.insert(LibraryEntry(vod: vod, episodeName: episode.name, episodeURL: episode.url, updatedAt: Date()), at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        save(history, key: Keys.history)
    }

    func clearHistory() {
        history.removeAll()
        save(history, key: Keys.history)
    }

    func removeFavorite(_ entry: LibraryEntry) {
        favorites.removeAll { $0.id == entry.id }
        save(favorites, key: Keys.favorites)
    }

    private func save(_ entries: [LibraryEntry], key: String) {
        if let data = try? encoder.encode(entries) { defaults.set(data, forKey: key) }
    }

    private static func load(_ key: String, defaults: UserDefaults, decoder: JSONDecoder) -> [LibraryEntry] {
        guard let data = defaults.data(forKey: key), let value = try? decoder.decode([LibraryEntry].self, from: data) else { return [] }
        return value
    }
}
