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

    var vodAPIURL: URL? {
        URL(string: vodAPI.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let vodAPI = "settings.vodAPI"
        static let liveSource = "settings.liveSource"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        vodAPI = defaults.string(forKey: Keys.vodAPI)
            ?? "https://tv.789056.xyz/api.php/provide/vod/"
        liveSource = defaults.string(forKey: Keys.liveSource) ?? ""
    }

    func reset() {
        vodAPI = "https://tv.789056.xyz/api.php/provide/vod/"
        liveSource = ""
    }
}
