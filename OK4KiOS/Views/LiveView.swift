import SwiftUI

struct LiveView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var source = ""
    @State private var groups: [LiveGroup] = []
    @State private var selectedGroup: String?
    @State private var selectedChannel: LiveChannel?
    @State private var errorMessage: String?
    @State private var isLoading = false
    private let service = LiveService()

    private var visibleChannels: [LiveChannel] {
        guard let selectedGroup, let group = groups.first(where: { $0.id == selectedGroup }) else {
            return groups.flatMap(\.channels)
        }
        return group.channels
    }

    private let columns = [GridItem(.adaptive(minimum: 148), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title2).foregroundColor(.red)
                    TextField("M3U / M3U8 地址", text: $source)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textFieldStyle(.roundedBorder)
                    Button(action: { Task { await load() } }) {
                        Label(isLoading ? "加载中" : "加载", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
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
                                        Image(systemName: "play.tv.fill").foregroundColor(.red)
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
                    EmptyStateView(icon: "play.tv", title: "还没有直播频道", detail: "粘贴 M3U 地址并点击加载")
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
                episodeName: channel.name,
                forceSystemPlayer: true,
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
            groups = try await service.load(urlString: value)
            selectedGroup = nil
            if groups.isEmpty { throw LiveService.LiveError.invalidPlaylist }
        } catch { errorMessage = error.localizedDescription }
    }
}
