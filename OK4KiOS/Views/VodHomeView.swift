import SwiftUI

struct VodHomeView: View {
    @State private var items: [Vod] = []
    @State private var keyword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    private var service: VodService {
        VodService(baseURL: AppSettings.shared.vodAPIURL ?? VodService.defaultBaseURL)
    }

    var body: some View {
        List(items) { vod in
            NavigationLink(destination: VodDetailView(vod: vod, service: service)) {
                HStack(spacing: 12) {
                    AsyncImage(url: vod.imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { Color.gray.opacity(0.25) }
                    .frame(width: 72, height: 100)
                    .clipped()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(vod.name).font(.headline)
                        Text(vod.remark).font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("点播")
        .searchable(text: $keyword, prompt: "搜索影片")
        .onSubmit(of: .search) { Task { await load() } }
        .overlay { if isLoading { ProgressView() } }
        .alert("加载失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .task { await load() }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? try await service.home()
                : try await service.search(keyword)
            items = result.list
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct VodDetailView: View {
    let vod: Vod
    let service: VodServiceProtocol
    @ObservedObject private var library = LibraryStore.shared
    @State private var detail: Vod
    @State private var loadError: String?

    init(vod: Vod, service: VodServiceProtocol? = nil) {
        self.vod = vod
        self.service = service ?? VodService(baseURL: AppSettings.shared.vodAPIURL ?? VodService.defaultBaseURL)
        _detail = State(initialValue: vod)
    }
    @State private var selectedFlag = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    AsyncImage(url: detail.imageURL) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.25) }
                        .frame(width: 120, height: 168).clipped()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detail.name).font(.title2).bold()
                        Text(detail.remark).foregroundColor(.secondary)
                        if !detail.content.isEmpty { Text(detail.content).font(.body).lineLimit(6) }
                    }
                }
                if !detail.flags.isEmpty {
                    Picker("线路", selection: $selectedFlag) {
                        ForEach(Array(detail.flags.enumerated()), id: \.offset) { index, flag in Text(flag.name).tag(index) }
                    }.pickerStyle(.segmented)
                    ForEach(detail.flags[min(max(selectedFlag, 0), detail.flags.count - 1)].episodes) { episode in
                        NavigationLink(episode.name) { PlayerView(urlString: episode.url, vod: detail, episodeName: episode.name) }
                    }
                }
            }.padding()
        }
        .navigationTitle(detail.name)
        .toolbar {
            Button(action: { library.toggleFavorite(detail) }) {
                Image(systemName: library.isFavorite(detail) ? "heart.fill" : "heart")
            }
        }
        .task {
            guard !vod.id.isEmpty else { return }
            do {
                let loaded = try await service.detail(id: vod.id)
                await MainActor.run {
                    detail = loaded
                    selectedFlag = 0
                }
            } catch {
                loadError = error.localizedDescription
            }
        }
        .alert("详情加载失败", isPresented: Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } })) {
            Button("继续使用列表信息", role: .cancel) { loadError = nil }
        } message: { Text(loadError ?? "") }
    }
}
