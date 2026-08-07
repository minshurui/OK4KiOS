import AVKit
import SwiftUI

struct PlayerView: View {
    let urlString: String
    let headers: [String: String]
    let vod: Vod?
    let episodeName: String?
    @StateObject private var model: PlayerViewModel
    @State private var useFFmpeg = false

    init(urlString: String, headers: [String: String] = [:], vod: Vod? = nil, episodeName: String? = nil) {
        let request = PlaybackRequest.parse(urlString, additionalHeaders: headers)
        let remoteURL = URL(string: request.urlString)
        let needsProxy = !request.headers.isEmpty && remoteURL?.pathExtension.lowercased() == "m3u8"
        let effectiveURL = needsProxy ? (remoteURL.flatMap { LocalProxyServer.shared.url(for: $0, headers: request.headers) }?.absoluteString ?? request.urlString) : request.urlString
        self.urlString = effectiveURL
        self.headers = needsProxy ? [:] : request.headers
        self.vod = vod
        self.episodeName = episodeName
        _model = StateObject(wrappedValue: PlayerViewModel(urlString: effectiveURL, headers: needsProxy ? [:] : request.headers, vod: vod, episodeName: episodeName))
        _useFFmpeg = State(initialValue: AppSettings.shared.preferFFmpeg)
    }

    var body: some View {
        Group {
            if useFFmpeg {
                FFmpegPlayerView(urlString: urlString, headers: headers) { current, total in
                    model.reportProgress(position: current, duration: total)
                }
            } else {
                PlayerControllerView(player: model.player)
            }
        }
            .ignoresSafeArea()
            .navigationTitle(episodeName ?? vod?.name ?? "播放")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        useFFmpeg.toggle()
                        AppSettings.shared.preferFFmpeg = useFFmpeg
                        if useFFmpeg { model.pause() } else { model.play() }
                    } label: {
                        Image(systemName: useFFmpeg ? "waveform.badge.plus" : "play.rectangle")
                    }
                    .accessibilityLabel(useFFmpeg ? "切换系统播放器" : "切换 FFmpeg 播放器")
                    Menu {
                        ForEach(PlayerViewModel.supportedRates, id: \.self) { rate in
                            Button(rateLabel(rate)) { model.setRate(rate) }
                        }
                    } label: { Image(systemName: "speedometer") }
                }
            }
            .onAppear { if !useFFmpeg { model.play() } }
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
final class PlayerViewModel: ObservableObject, @unchecked Sendable {
    static let supportedRates: [Float] = [0.5, 1, 1.25, 1.5, 2]

    let player = AVPlayer()
    @Published var errorMessage: String?
    @Published private(set) var rate: Float = 1
    private let urlString: String
    private let vod: Vod?
    private let episodeName: String?
    private var timeObserver: Any?

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
        if let vod, let position = LibraryStore.shared.resumePosition(vod: vod, episodeURL: urlString) {
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 1), queue: .main) { [weak self] _ in
            self?.saveProgress()
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    func play() {
        player.playImmediately(atRate: rate)
        if let vod, let episodeName {
            LibraryStore.shared.record(vod, episode: Episode(name: episodeName, url: urlString))
        }
    }

    func pause() {
        saveProgress()
        player.pause()
    }

    private func saveProgress() {
        reportProgress(position: player.currentTime().seconds, duration: player.currentItem?.duration.seconds ?? 0)
    }

    func reportProgress(position: Double, duration: Double) {
        guard let vod, let episodeName, position.isFinite, position >= 0 else { return }
        LibraryStore.shared.record(vod, episode: Episode(name: episodeName, url: urlString), position: position, duration: duration.isFinite ? duration : nil)
    }

    func setRate(_ value: Float) {
        rate = value
        if player.timeControlStatus != .paused { player.rate = value }
    }
}
