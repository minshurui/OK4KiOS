import SwiftUI

struct LiveView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var source = ""
    @State private var searchText = ""
    @State private var groups: [LiveGroup] = []
    @State private var selectedGroup: String?
    @State private var selectedChannel: LiveChannel?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showingSourcePicker = false
    private let service = LiveService()

    private var visibleChannels: [LiveChannel] {
        var channels: [LiveChannel]
        if let selectedGroup, let group = groups.first(where: { $0.id == selectedGroup }) {
            channels = group.channels
        } else {
            channels = groups.flatMap(\.channels)
        }
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            channels = channels.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
        }
        return channels
    }

    private var totalChannelCount: Int { groups.reduce(0) { $0 + $1.channels.count } }

    private let columns = [GridItem(.adaptive(minimum: 148), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title2).foregroundColor(.red)
                    TextField("M3U / TXT / JSON 直播源地址", text: $source)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textFieldStyle(.roundedBorder)
                    Button(action: { Task { await load() } }) {
                        Label(isLoading ? "加载中" : "加载", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                    if !settings.liveSources.isEmpty {
                        Menu {
                            ForEach(settings.liveSources, id: \.self) { saved in
                                Button(saved) { source = saved; Task { await load() } }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("已保存直播源")
                    }
                }

                HStack {
                    if !groups.isEmpty {
                        Text("\(totalChannelCount) 个频道 · \(groups.count) 个分组")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if !groups.isEmpty {
                        TextField("搜索频道", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                            .autocorrectionDisabled(true)
                    }
                }

                if !groups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            groupButton("全部", id: nil)
                            ForEach(groups) { group in groupButton(group.name, id: group.id) }
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(visibleChannels) { channel in
                            Button { selectedChannel = channel } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.16))
                                        if let logoURL = channel.logoURL {
                                            AsyncImage(url: logoURL) { image in
                                                image.resizable().scaledToFit()
                                            } placeholder: {
                                                Image(systemName: "play.tv.fill").foregroundColor(.red)
                                            }
                                            .padding(4)
                                        } else {
                                            Image(systemName: "play.tv.fill").foregroundColor(.red)
                                        }
                                    }
                                    .frame(width: 46, height: 46)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(channel.name).font(.headline).lineLimit(2)
                                        Text(channel.group).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                                .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if !isLoading {
                    EmptyStateView(icon: "play.tv", title: "还没有直播频道", detail: "粘贴 M3U / TXT / JSON 地址并点击加载")
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding()
        }
        .background(OKTheme.background.ignoresSafeArea())
        .navigationTitle("直播")
        .onAppear {
            if source.isEmpty { source = settings.liveSource }
            if groups.isEmpty && !source.isEmpty { Task { await load() } }
        }
        .alert("直播加载失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .fullScreenCover(item: $selectedChannel) { channel in
            PlayerView(
                urlString: channel.url.absoluteString,
                headers: channel.headers,
                episodeName: channel.name,
                isLive: true,
                onClose: { selectedChannel = nil }
            )
            .background(Color.black)
        }
    }

    private func groupButton(_ title: String, id: String?) -> some View {
        Button(title) { selectedGroup = id }
            .buttonStyle(.bordered)
            .tint(selectedGroup == id ? .red : .secondary)
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard URL(string: value) != nil else { throw LiveService.LiveError.invalidURL }
            settings.liveSource = value
            if !settings.liveSources.contains(value) {
                settings.liveSources = [value] + settings.liveSources
                if settings.liveSources.count > 20 { settings.liveSources = Array(settings.liveSources.prefix(20)) }
            }
            groups = try await service.load(urlString: value)
            selectedGroup = nil
            if groups.isEmpty { throw LiveService.LiveError.invalidPlaylist }
        } catch { errorMessage = error.localizedDescription }
    }
}
