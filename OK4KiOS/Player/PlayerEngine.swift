import AVFoundation
import Foundation

@MainActor
protocol PlayerEngine: AnyObject {
    var player: AVPlayer { get }
    func load(url: URL, headers: [String: String])
    func play()
    func pause()
    func seek(to seconds: Double) async
}

@MainActor
final class AVPlayerEngine: PlayerEngine {
    let player = AVPlayer()

    func load(url: URL, headers: [String: String] = [:]) {
        let options: [String: Any] = headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: options)
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(to seconds: Double) async {
        await player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
    }
}
