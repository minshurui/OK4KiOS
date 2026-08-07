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

    var vodAPIURL: URL? {
        URL(string: vodAPI.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let vodAPI = "settings.vodAPI"
        static let liveSource = "settings.liveSource"
        static let configURL = "settings.configURL"
        static let preferFFmpeg = "settings.preferFFmpeg"
        static let selectedSite = "settings.selectedSite"
        static let spiderGateway = "settings.spiderGateway"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        vodAPI = defaults.string(forKey: Keys.vodAPI)
            ?? "https://tv.789056.xyz/api.php/provide/vod/"
        liveSource = defaults.string(forKey: Keys.liveSource) ?? ""
        configURL = defaults.string(forKey: Keys.configURL) ?? ""
        preferFFmpeg = defaults.bool(forKey: Keys.preferFFmpeg)
        selectedSite = defaults.data(forKey: Keys.selectedSite).flatMap { try? JSONDecoder().decode(TVBoxSite.self, from: $0) }
        spiderGateway = defaults.string(forKey: Keys.spiderGateway) ?? ""
    }

    func reset() {
        vodAPI = "https://tv.789056.xyz/api.php/provide/vod/"
        liveSource = ""
        configURL = ""
        preferFFmpeg = false
        selectedSite = nil
        spiderGateway = ""
    }
}
