import Combine
import Foundation

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var vodAPI: String {
        didSet { defaults.set(vodAPI, forKey: Keys.vodAPI) }
    }

    @Published var liveSource: String {
        didSet { defaults.set(liveSource, forKey: Keys.liveSource) }
    }

    @Published var liveSources: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(liveSources) { defaults.set(data, forKey: Keys.liveSources) }
        }
    }

    @Published var vodAPIType: Int {
        didSet { defaults.set(vodAPIType, forKey: Keys.vodAPIType) }
    }

    @Published var configURL: String {
        didSet { defaults.set(configURL, forKey: Keys.configURL) }
    }

    @Published var preferFFmpeg: Bool {
        didSet { defaults.set(preferFFmpeg, forKey: Keys.preferFFmpeg) }
    }

    @Published var selectedSite: TVBoxSite? {
        didSet {
            if let selectedSite, let data = try? JSONEncoder().encode(selectedSite) { defaults.set(data, forKey: Keys.selectedSite) }
            else { defaults.removeObject(forKey: Keys.selectedSite) }
        }
    }

    @Published var spiderGateway: String {
        didSet { defaults.set(spiderGateway, forKey: Keys.spiderGateway) }
    }

    @Published var savedSites: [TVBoxSite] {
        didSet {
            if let data = try? JSONEncoder().encode(savedSites) { defaults.set(data, forKey: Keys.savedSites) }
        }
    }

    var vodAPIURL: URL? {
        URL(string: vodAPI.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let vodAPI = "settings.vodAPI"
        static let liveSource = "settings.liveSource"
        static let liveSources = "settings.liveSources"
        static let vodAPIType = "settings.vodAPIType"
        static let configURL = "settings.configURL"
        static let preferFFmpeg = "settings.preferFFmpeg"
        static let selectedSite = "settings.selectedSite"
        static let spiderGateway = "settings.spiderGateway"
        static let savedSites = "settings.savedSites"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        vodAPI = defaults.string(forKey: Keys.vodAPI)
            ?? "https://tv.789056.xyz/api.php/provide/vod/"
        liveSource = defaults.string(forKey: Keys.liveSource) ?? ""
        liveSources = defaults.data(forKey: Keys.liveSources).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        vodAPIType = defaults.object(forKey: Keys.vodAPIType) == nil ? 1 : defaults.integer(forKey: Keys.vodAPIType)
        configURL = defaults.string(forKey: Keys.configURL) ?? "https://tv.789056.xyz/tvbox.json"
        preferFFmpeg = defaults.bool(forKey: Keys.preferFFmpeg)
        let storedSelected = defaults.data(forKey: Keys.selectedSite).flatMap { try? JSONDecoder().decode(TVBoxSite.self, from: $0) }
        // FishConfig stays in savedSites as a first-class feature entry, but
        // older builds may have persisted it as the active movie catalogue.
        // Clear only that invalid selection so the VOD tab uses the manual API.
        selectedSite = storedSelected?.isFeatureCenter == true ? nil : storedSelected
        spiderGateway = defaults.string(forKey: Keys.spiderGateway) ?? ""
        savedSites = defaults.data(forKey: Keys.savedSites).flatMap { try? JSONDecoder().decode([TVBoxSite].self, from: $0) } ?? []
    }

    func reset() {
        vodAPI = "https://tv.789056.xyz/api.php/provide/vod/"
        liveSource = ""
        liveSources = []
        vodAPIType = 1
        configURL = "https://tv.789056.xyz/tvbox.json"
        preferFFmpeg = false
        selectedSite = nil
        spiderGateway = ""
        savedSites = []
    }
}
