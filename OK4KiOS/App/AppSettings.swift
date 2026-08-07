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
        vodAPIType = defaults.object(forKey: Keys.vodAPIType) == nil ? 1 : defaults.integer(forKey: Keys.vodAPIType)
        configURL = defaults.string(forKey: Keys.configURL) ?? "https://tv.789056.xyz/tvbox.json"
        preferFFmpeg = defaults.bool(forKey: Keys.preferFFmpeg)
        let storedSelected = defaults.data(forKey: Keys.selectedSite).flatMap { try? JSONDecoder().decode(TVBoxSite.self, from: $0) }
        let storedSites = defaults.data(forKey: Keys.savedSites).flatMap { try? JSONDecoder().decode([TVBoxSite].self, from: $0) } ?? []
        // Older builds persisted Android-only utility entries such as
        // FishConfig as the selected VOD site. Sanitize them on startup so
        // iOS never routes a settings action into the VOD Spider resolver.
        selectedSite = storedSelected?.isBrowsableVodSite == true ? storedSelected : nil
        spiderGateway = defaults.string(forKey: Keys.spiderGateway) ?? ""
        savedSites = storedSites.filter(\.isBrowsableVodSite)
    }

    func reset() {
        vodAPI = "https://tv.789056.xyz/api.php/provide/vod/"
        liveSource = ""
        vodAPIType = 1
        configURL = "https://tv.789056.xyz/tvbox.json"
        preferFFmpeg = false
        selectedSite = nil
        spiderGateway = ""
        savedSites = []
    }
}
