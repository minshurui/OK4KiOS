import AVFoundation
import Foundation

#if os(iOS)
final class AudioSessionController {
    static let shared = AudioSessionController()
    private init() {}

    func activate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true, options: [])
        } catch {
            // The player will retry when playback resumes or an interruption ends.
        }
    }

    func deactivateIfIdle() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
#else
final class AudioSessionController {
    static let shared = AudioSessionController()
    private init() {}
    func activate() {}
    func deactivateIfIdle() {}
}
#endif
