import SwiftUI

struct ResolvingPlayerView: View {
    let service: VodServiceProtocol
    let flag: String
    let episode: Episode
    let vod: Vod
    @State private var playback: SpiderPlayback?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let playback {
                PlayerView(urlString: playback.url, headers: playback.headers, vod: vod, episodeName: episode.name)
            } else if let errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(errorMessage).multilineTextAlignment(.center)
                    Button("重试") { Task { await resolve() } }
                }.padding()
            } else {
                ProgressView("正在调用 Spider 解析播放地址…")
            }
        }
        .navigationTitle(episode.name)
        .task { if playback == nil { await resolve() } }
    }

    private func resolve() async {
        errorMessage = nil
        do { playback = try await service.player(flag: flag, id: episode.url) }
        catch { errorMessage = error.localizedDescription }
    }
}
