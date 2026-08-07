import SwiftUI

struct LiveView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var source = ""
    @State private var groups: [LiveGroup] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    private let service = LiveService()

    var body: some View {
        List {
            Section("直播源") {
                TextField("M3U / M3U8 地址", text: $source)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button("加载直播源") { Task { await load() } }
            }
            ForEach(groups) { group in
                Section(group.name) {
                    ForEach(group.channels) { channel in
                        NavigationLink(channel.name) {
                            PlayerView(urlString: channel.url.absoluteString)
                        }
                    }
                }
            }
        }
        .navigationTitle("直播")
        .onAppear { if source.isEmpty { source = settings.liveSource } }
        .alert("直播加载失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .overlay { if isLoading { ProgressView() } }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            guard URL(string: source.trimmingCharacters(in: .whitespacesAndNewlines)) != nil else {
                throw LiveService.LiveError.invalidURL
            }
            settings.liveSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
            groups = try await service.load(urlString: settings.liveSource)
            if groups.isEmpty { throw LiveService.LiveError.invalidPlaylist }
        } catch { errorMessage = error.localizedDescription }
    }
}
