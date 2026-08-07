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
    private let columns = [GridItem(.adaptive(minimum: 112, maximum: 170), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !types.isEmpty && keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            typeButton("全部", id: nil)
                            ForEach(types) { type in typeButton(type.name, id: type.id) }
                        }
                        .padding(.horizontal)
                    }
                }

                if items.isEmpty && !isLoading {
                    EmptyStateView(icon: "film.stack", title: "暂无影片", detail: "请在设置中导入 TVBox 配置并选择站点")
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(items) { vod in
                            NavigationLink(destination: VodDetailView(vod: vod, service: service)) {
                                VStack(alignment: .leading, spacing: 7) {
                                    ZStack(alignment: .bottomTrailing) {
                                        AsyncImage(url: vod.imageURL) { phase in
                                            switch phase {
                                            case .success(let image): image.resizable().scaledToFill()
                                            default: PosterPlaceholder()
                                            }
                                        }
                                        .aspectRatio(0.7, contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                        .clipped()
                                        if !vod.remark.isEmpty {
                                            Text(vod.remark)
                                                .font(.caption2).bold().foregroundColor(.white)
                                                .padding(.horizontal, 6).padding(.vertical, 4)
                                                .background(Color.black.opacity(0.65), in: Capsule())
                                                .padding(6)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Text(vod.name).font(.subheadline.weight(.semibold)).foregroundColor(.primary).lineLimit(1)
                                    Text(vod.typeName?.value ?? "").font(.caption).foregroundColor(.secondary).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                if hasMore && !items.isEmpty {
                    Button(isLoading ? "加载中…" : "加载更多") { Task { await loadNextPage() } }
                        .disabled(isLoading)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                        .padding(.bottom, 20)
                }
            }
            .padding(.top, 10)
        }
        .background(OKTheme.background.ignoresSafeArea())
        .navigationTitle(settings.selectedSite?.name ?? "OK影视4K")
        .searchable(text: $keyword, prompt: "搜索影片")
        .onSubmit(of: .search) { Task { await reload() } }
        .overlay { if isLoading && items.isEmpty { ProgressView("加载中…") } }
        .alert("加载失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .task { if items.isEmpty { await reload() } }
        .onChange(of: settings.selectedSite?.id) { _ in
            types = []
            selectedType = nil
            Task { await reload() }
        }
    }

    private func typeButton(_ title: String, id: String?) -> some View {
        Button(title) {
            selectedType = id
            Task { await reload() }
        }
        .buttonStyle(.bordered)
        .tint(selectedType == id ? OKTheme.accent : .secondary)
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
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    AsyncImage(url: detail.imageURL) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: PosterPlaceholder()
                        }
                    }
                    .frame(width: 120, height: 172).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detail.name).font(.title2).bold()
                        Text(detail.remark).foregroundColor(OKTheme.accent)
                        if !detail.content.isEmpty { Text(detail.content).font(.body).foregroundColor(.secondary).lineLimit(7) }
                    }
                }
                if !detail.flags.isEmpty {
                    Picker("线路", selection: $selectedFlag) {
                        ForEach(Array(detail.flags.enumerated()), id: \.offset) { index, flag in Text(flag.name).tag(index) }
                    }
                    .pickerStyle(.segmented)
                    let flag = detail.flags[min(max(selectedFlag, 0), detail.flags.count - 1)]
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 10)], spacing: 10) {
                        ForEach(flag.episodes) { episode in
                            NavigationLink(episode.name) {
                                ResolvingPlayerView(service: service, flag: flag.name, episode: episode, vod: detail)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding()
        }
        .background(OKTheme.background.ignoresSafeArea())
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
                await MainActor.run { detail = loaded; selectedFlag = 0 }
            } catch { loadError = error.localizedDescription }
        }
        .alert("详情加载失败", isPresented: Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } })) {
            Button("继续使用列表信息", role: .cancel) { loadError = nil }
        } message: { Text(loadError ?? "") }
    }
}
