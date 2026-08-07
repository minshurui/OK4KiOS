import KSPlayer
import SwiftUI

struct FFmpegPlayerView: UIViewRepresentable {
    let urlString: String
    let headers: [String: String]
    let onError: (() -> Void)?
    let onProgress: (Double, Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError, onProgress: onProgress)
    }

    func makeUIView(context: Context) -> IOSVideoPlayerView {
        let view = IOSVideoPlayerView()
        guard let url = URL(string: urlString) else { return view }
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSAVPlayer.self
        KSOptions.hardwareDecode = true
        let options = KSOptions()
        if !headers.isEmpty { options.appendHeader(headers) }
        view.delegate = context.coordinator
        view.playTimeDidChange = { current, total in context.coordinator.onProgress(current, total) }
        view.set(url: url, options: options)
        view.play()
        return view
    }

    func updateUIView(_ view: IOSVideoPlayerView, context: Context) {
        view.delegate = context.coordinator
    }

    static func dismantleUIView(_ view: IOSVideoPlayerView, coordinator: Coordinator) {
        view.pause()
        view.resetPlayer()
    }

    final class Coordinator: NSObject, PlayerControllerDelegate {
        let onError: (() -> Void)?
        let onProgress: (Double, Double) -> Void
        private var didReportError = false

        init(onError: (() -> Void)?, onProgress: @escaping (Double, Double) -> Void) {
            self.onError = onError
            self.onProgress = onProgress
        }

        func playerController(state: KSPlayerState) {
            if state == .error { reportErrorOnce() }
        }

        func playerController(currentTime: TimeInterval, totalTime: TimeInterval) {
            onProgress(currentTime, totalTime)
        }

        func playerController(finish error: Error?) {
            if error != nil { reportErrorOnce() }
        }

        func playerController(maskShow: Bool) {}
        func playerController(action: PlayerButtonType) {}
        func playerController(bufferedCount: Int, consumeTime: TimeInterval) {}
        func playerController(seek: TimeInterval) {}

        private func reportErrorOnce() {
            guard !didReportError else { return }
            didReportError = true
            DispatchQueue.main.async { self.onError?() }
        }
    }
}
