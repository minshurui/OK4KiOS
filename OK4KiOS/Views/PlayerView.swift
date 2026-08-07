import AVKit
import SwiftUI

struct PlayerView: View {
    let urlString: String
    let headers: [String: String]
    let vod: Vod?
    let episodeName: String?
    let isLive: Bool
    let onClose: (() -> Void)?
    @StateObject private var model: PlayerViewModel
    @State private var useFFmpeg: Bool
    @State private var fallbackAttempts = 0

    init(urlString: String, headers: [String: String] = [:], vod: Vod? = nil, episodeName: String? = nil, isLive: Bool = false, onClose: (() -> Void)? = nil) {
        let request = PlaybackRequest.parse(urlString, additionalHeaders: headers)
        let remoteURL = URL(string: request.urlString)
        let isHLS = remoteURL?.pathExtension.lowercased() == "m3u8" || request.urlString.lowercased().contains(".m3u8")
        let needsProxy = isLive && !request.headers.isEmpty && isHLS
        let effectiveURL = needsProxy ? (remoteURL.flatMap { LocalProxyServer.shared.url(for: $0, headers: request.headers) }?.absoluteString ?? request.urlString) : request.urlString
        self.urlString = effectiveURL
        self.headers = needsProxy ? [:] : request.headers
        self.vod = vod
        self.episodeName = episodeName
        self.isLive = isLive
        self.onClose = onClose
        _model = StateObject(wrappedValue: PlayerViewModel(urlString: effectiveURL, headers: needsProxy ? [:] : request.headers, vod: vod, episodeName: episodeName, isLive: isLive))
        _useFFmpeg = State(initialValue: isLive ? false : AppSettings.shared.preferFFmpeg)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if useFFmpeg {
                    FFmpegPlayerView(urlString: urlString, headers: headers, onError: {
                        fallbackToSystem()
                    }) { current, total in
                        model.reportProgress(position: current, duration: total)
                    }
                } else {
                    PlayerControllerView(player: model.player)
                }
            }
            .background(Color.black)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(Color.black.opacity(0.65), in: Circle())
                }
                .padding(.top, 12)
                .padding(.leading, 12)
                .accessibilityLabel("关闭全屏播放")
            }
        }
        .ignoresSafeArea()
        .navigationTitle(episodeName ?? vod?.name ?? "播放")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    useFFmpeg.toggle()
                    if !isLive { AppSettings.shared.preferFFmpeg = useFFmpeg }
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
        .onAppear {
            AudioSessionController.shared.activate()
            if !useFFmpeg { model.play() }
        }
        .onDisappear { model.pause() }
        .onChange(of: model.didFail) { failed in
            guard failed, !useFFmpeg else { return }
            if fallbackAttempts == 0 {
                fallbackAttempts += 1
                useFFmpeg = true
            } else {
                model.errorMessage = "播放失败：系统与 FFmpeg 引擎均无法播放此流"
            }
        }
        .alert("播放失败", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("确定", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func fallbackToSystem() {
        guard useFFmpeg else { return }
        fallbackAttempts += 1
        useFFmpeg = false
        model.errorMessage = "播放失败：FFmpeg 与系统引擎均无法播放此流"
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
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        controller.showsPlaybackControls = true
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
    @Published private(set) var didFail = false
    private let urlString: String
    private let vod: Vod?
    private let episodeName: String?
    private let isLive: Bool
    private var timeObserver: Any?
    private var observers: [NSObjectProtocol] = []
    private var statusObserver: NSKeyValueObservation?

    init(urlString: String, headers: [String: String] = [:], vod: Vod? = nil, episodeName: String? = nil, isLive: Bool = false) {
        self.urlString = urlString
        self.vod = vod
        self.episodeName = episodeName
        self.isLive = isLive
        player.automaticallyWaitsToMinimizeStalling = true
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil else {
            errorMessage = "播放地址无效"
            return
        }
        let options: [String: Any] = headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        player.replaceCurrentItem(with: AVPlayerItem(asset: AVURLAsset(url: url, options: options)))
        if !isLive, let vod, let position = LibraryStore.shared.resumePosition(vod: vod, episodeURL: urlString) {
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 1), queue: .main) { [weak self] _ in
            self?.saveProgress()
        }
        installRecoveryObservers()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        statusObserver?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func play() {
        AudioSessionController.shared.activate()
        player.playImmediately(atRate: rate)
        if let vod, let episodeName {
            LibraryStore.shared.record(vod, episode: Episode(name: episodeName, url: urlString))
        }
    }

    func pause() {
        saveProgress()
        player.pause()
    }

    private func installRecoveryObservers() {
        #if os(iOS)
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self.play()
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.player.timeControlStatus != .paused else { return }
            AudioSessionController.shared.activate()
        })
        #endif
        if let item = player.currentItem {
            statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard let self, item.status == .failed else { return }
                self.didFail = true
                if !self.isLive {
                    self.errorMessage = item.error?.localizedDescription ?? "播放失败"
                }
            }
            observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] note in
                guard let self else { return }
                self.didFail = true
                if !self.isLive {
                    self.errorMessage = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "直播流中断"
                }
            })
            observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
                guard let self else { return }
                AudioSessionController.shared.activate()
                if self.isLive { self.player.play() }
            })
        }
    }

    private func saveProgress() {
        guard !isLive else { return }
        reportProgress(position: player.currentTime().seconds, duration: player.currentItem?.duration.seconds ?? 0)
    }

    func reportProgress(position: Double, duration: Double) {
        guard !isLive, let vod, let episodeName, position.isFinite, position >= 0 else { return }
        LibraryStore.shared.record(vod, episode: Episode(name: episodeName, url: urlString), position: position, duration: duration.isFinite ? duration : nil)
    }

    func setRate(_ value: Float) {
        rate = value
        if player.timeControlStatus != .paused { player.rate = value }
    }
}
