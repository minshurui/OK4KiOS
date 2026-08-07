import SwiftUI

struct LibraryView: View {
    @ObservedObject private var store = LibraryStore.shared

    var body: some View {
        List {
            Section("收藏") {
                if store.favorites.isEmpty { Text("暂无收藏").foregroundColor(.secondary) }
                ForEach(store.favorites) { entry in
                    NavigationLink(entry.vod.name) { VodDetailView(vod: entry.vod) }
                }
                .onDelete { offsets in
                    for index in offsets { store.removeFavorite(store.favorites[index]) }
                }
            }
            Section {
                if store.history.isEmpty { Text("暂无播放历史").foregroundColor(.secondary) }
                ForEach(store.history) { entry in
                    if let url = entry.episodeURL {
                        NavigationLink(destination: PlayerView(urlString: url, vod: entry.vod, episodeName: entry.episodeName)) {
                            VStack(alignment: .leading) {
                                Text(entry.vod.name)
                                Text(entry.episodeName ?? "继续播放").font(.caption).foregroundColor(.secondary)
                                if entry.progress > 0 {
                                    ProgressView(value: entry.progress)
                                }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("播放历史")
                    Spacer()
                    if !store.history.isEmpty { Button("清空") { store.clearHistory() } }
                }
            }
        }
        .navigationTitle("收藏与历史")
    }
}
