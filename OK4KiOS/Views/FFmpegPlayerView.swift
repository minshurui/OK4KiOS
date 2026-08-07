import KSPlayer
import SwiftUI

struct FFmpegPlayerView: UIViewRepresentable {
    let urlString: String
    let headers: [String: String]
    let onProgress: (Double, Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onProgress: onProgress) }

    func makeUIView(context: Context) -> IOSVideoPlayerView {
        let view = IOSVideoPlayerView()
        guard let url = URL(string: urlString) else { return view }
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSAVPlayer.self
        KSOptions.hardwareDecode = true
        let options = KSOptions()
        if !headers.isEmpty { options.appendHeader(headers) }
        view.playTimeDidChange = { current, total in context.coordinator.onProgress(current, total) }
        view.set(url: url, options: options)
        view.play()
        return view
    }

    func updateUIView(_ view: IOSVideoPlayerView, context: Context) {}

    static func dismantleUIView(_ view: IOSVideoPlayerView, coordinator: Coordinator) {
        view.pause()
        view.resetPlayer()
    }

    final class Coordinator {
        let onProgress: (Double, Double) -> Void
        init(onProgress: @escaping (Double, Double) -> Void) { self.onProgress = onProgress }
    }
}
