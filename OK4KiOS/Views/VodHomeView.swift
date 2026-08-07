import SwiftUI

struct VodHomeView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var items: [Vod] = []
    @State private var types: [VodClass] = []
    @State private var selectedType: String?
    @State private var keyword = ""
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var service: VodServiceProtocol { VodServiceFactory.current(settings: settings) }

    var body: some View {
        List {
            if !types.isEmpty && keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Picker("分类", selection: $selectedType) {
                    Text("全部").tag(String?.none)
                    ForEach(types) { type in Text(type.name).tag(Optional(type.id)) }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedType) { _ in Task { await reload() } }
            }
            ForEach(items) { vod in
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
            if hasMore && !items.isEmpty {
                Button(isLoading ? "加载中…" : "加载更多") { Task { await loadNextPage() } }
                    .disabled(isLoading)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("点播")
        .searchable(text: $keyword, prompt: "搜索影片")
        .onSubmit(of: .search) { Task { await reload() } }
        .overlay { if isLoading && items.isEmpty { ProgressView() } }
        .alert("加载失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .task { if items.isEmpty { await reload() } }
    }

    private func reload() async {
        page = 1
        hasMore = true
        items = []
        await load(append: false)
    }

    private func loadNextPage() async {
        guard hasMore else { return }
        page += 1
        await load(append: true)
    }

    private func load(append: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let cleanKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            let result: VodResult
            if !cleanKeyword.isEmpty {
                result = try await service.search(cleanKeyword, page: page)
            } else if let selectedType {
                result = try await service.category(id: selectedType, page: page)
            } else {
                result = try await service.home(page: page)
            }
            if types.isEmpty { types = result.types }
            items = append ? items + result.list : result.list
            let pageCount = result.pagecount?.value ?? page
            hasMore = !result.list.isEmpty && page < pageCount
        } catch {
            if append { page = max(1, page - 1) }
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
    @State private var selectedFlag = 0

    init(vod: Vod, service: VodServiceProtocol? = nil) {
        self.vod = vod
        self.service = service ?? VodServiceFactory.current()
        _detail = State(initialValue: vod)
    }

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
                    let flag = detail.flags[min(max(selectedFlag, 0), detail.flags.count - 1)]
                    ForEach(flag.episodes) { episode in
                        NavigationLink(episode.name) {
                            ResolvingPlayerView(service: service, flag: flag.name, episode: episode, vod: detail)
                        }
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
