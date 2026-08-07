import AVKit
import SwiftUI

struct PlayerView: View {
    let urlString: String
    let headers: [String: String]
    let vod: Vod?
    let episodeName: String?
    @StateObject private var model: PlayerViewModel

    init(urlString: String, headers: [String: String] = [:], vod: Vod? = nil, episodeName: String? = nil) {
        let request = PlaybackRequest.parse(urlString, additionalHeaders: headers)
        self.urlString = request.urlString
        self.headers = request.headers
        self.vod = vod
        self.episodeName = episodeName
        _model = StateObject(wrappedValue: PlayerViewModel(urlString: request.urlString, headers: request.headers, vod: vod, episodeName: episodeName))
    }

    var body: some View {
        PlayerControllerView(player: model.player)
            .ignoresSafeArea()
            .navigationTitle(episodeName ?? vod?.name ?? "播放")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(PlayerViewModel.supportedRates, id: \.self) { rate in
                            Button(rateLabel(rate)) { model.setRate(rate) }
                        }
                    } label: { Image(systemName: "speedometer") }
                }
            }
            .onAppear { model.play() }
            .onDisappear { model.pause() }
            .alert("播放失败", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("确定", role: .cancel) { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }

    private func rateLabel(_ rate: Float) -> String {
        let value = rate == floor(rate) ? String(format: "%.0fx", rate) : String(format: "%.2gx", rate)
        return rate == model.rate ? "✓ " + value : value
    }
}

#if os(iOS)
struct PlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
#else
struct PlayerControllerView: View {
    let player: AVPlayer
    var body: some View { Text("播放器仅支持 iOS") }
}
#endif

@MainActor
final class PlayerViewModel: ObservableObject {
    static let supportedRates: [Float] = [0.5, 1, 1.25, 1.5, 2]

    let player = AVPlayer()
    @Published var errorMessage: String?
    @Published private(set) var rate: Float = 1
    private let urlString: String
    private let vod: Vod?
    private let episodeName: String?

    init(urlString: String, headers: [String: String] = [:], vod: Vod? = nil, episodeName: String? = nil) {
        self.urlString = urlString
        self.vod = vod
        self.episodeName = episodeName
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil else {
            errorMessage = "播放地址无效"
            return
        }
        let options: [String: Any] = headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        player.replaceCurrentItem(with: AVPlayerItem(asset: AVURLAsset(url: url, options: options)))
    }

    func play() {
        player.playImmediately(atRate: rate)
        if let vod, let episodeName {
            LibraryStore.shared.record(vod, episode: Episode(name: episodeName, url: urlString))
        }
    }

    func pause() { player.pause() }

    func setRate(_ value: Float) {
        rate = value
        if player.timeControlStatus != .paused { player.rate = value }
    }
}
