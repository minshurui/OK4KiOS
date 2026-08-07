import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var apiDraft = ""
    @State private var configDraft = ""
    @State private var gatewayDraft = ""
    @State private var sites: [TVBoxSite] = []
    @State private var isLoading = false
    @State private var message: String?
    @State private var showingFeatureCenter = false

    var body: some View {
        Form {
            Section("点播接口") {
                Picker("接口格式", selection: $settings.vodAPIType) {
                    Text("JSON · type 1").tag(1)
                    Text("XML · type 0").tag(0)
                }
                .pickerStyle(.segmented)
                TextField("TVBox 点播 API 地址", text: $apiDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button("保存接口") { saveAPI() }
                Text("手动接口支持 TVBox type 0 XML 和 type 1 JSON；Spider/type 4 请通过下方 TVBox 配置导入。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("TVBox 配置") {
                TextField("配置 JSON 地址", text: $configDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button(isLoading ? "加载中…" : "导入配置") { Task { await importConfig() } }
                    .disabled(isLoading)
                ForEach(sites) { site in
                    Button {
                        if site.isFeatureCenter {
                            showingFeatureCenter = true
                        } else {
                            settings.selectedSite = site
                            if site.type == 0 || site.type == 1 { apiDraft = site.api; settings.vodAPI = site.api }
                            message = "已启用：\(site.name)"
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text((settings.selectedSite?.id == site.id && !site.isFeatureCenter ? "✓ " : "") + site.name)
                            Text(siteSubtitle(site))
                                .font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            Section("Spider 兼容层") {
                TextField("Spider 网关地址（可选）", text: $gatewayDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button("保存网关") { saveGateway() }
                Text("iPhone/iPad 优先运行原生 Spider 和规则适配；网关只是在个别尚未移植站点上的可选兼容方式。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("播放器") {
                Toggle("默认使用 FFmpeg 引擎", isOn: $settings.preferFFmpeg)
                Text("FFmpeg 适用于 MP2、AC3、E-AC3、DTS/DTS-HD；系统引擎功耗更低并支持原生画中画。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section {
                Button("恢复默认", role: .destructive) {
                    settings.reset()
                    apiDraft = settings.vodAPI
                    configDraft = settings.configURL
                    gatewayDraft = ""
                    sites = []
                }
            }
            Section("兼容范围") {
                Text("最低 iOS 15.0")
                Text("重点设备：iPhone 12 / iOS 15.4")
                Text("AVPlayer：HLS、MP4、AirPlay、画中画、后台音频")
            }
        }
        .navigationTitle("设置")
        .onAppear {
            apiDraft = settings.vodAPI
            configDraft = settings.configURL
            gatewayDraft = settings.spiderGateway
            if sites.isEmpty { sites = settings.savedSites }
        }
        .sheet(isPresented: $showingFeatureCenter) {
            NavigationView { FishFeatureCenterView() }
                .navigationViewStyle(.stack)
        }
        .alert("设置", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func siteSubtitle(_ site: TVBoxSite) -> String {
        if site.isFeatureCenter { return "打开 iOS 功能中心（保留 FishConfig 入口）" }
        if site.type == 3 { return "\(site.kindLabel) · \(site.nativeBaseURLs.first?.host ?? "需兼容执行")" }
        return "\(site.kindLabel) · \(site.api)"
    }

    private func saveAPI() {
        let value = apiDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validHTTPURL(value) else {
            message = "请输入有效的 HTTP 或 HTTPS 接口地址"
            return
        }
        settings.vodAPI = value
        settings.selectedSite = nil
        message = "点播接口已保存"
    }

    private func importConfig() async {
        let value = configDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validHTTPURL(value) else {
            message = "请输入有效的配置地址"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let service = ConfigService()
            let loaded = try await service.load(urlString: value)
            settings.configURL = value
            sites = loaded
            settings.savedSites = loaded
            let lives = try await service.loadLives(urlString: value)
            if !lives.isEmpty {
                var merged = settings.liveSources
                for url in lives.values where !merged.contains(url) { merged.insert(url, at: 0) }
                settings.liveSources = Array(merged.prefix(20))
                if settings.liveSource.isEmpty { settings.liveSource = lives.values.first ?? "" }
            }
            message = loaded.isEmpty ? "已导入配置（含 \(lives.count) 个直播源），没有可用站点" : "已导入 \(loaded.count) 个接口、\(lives.count) 个直播源，请点击一个启用"
        } catch {
            message = "配置导入失败：\(error.localizedDescription)"
        }
    }

    private func saveGateway() {
        let value = gatewayDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty && !validHTTPURL(value) {
            message = "请输入有效的 HTTP 或 HTTPS 网关地址"
            return
        }
        settings.spiderGateway = value
        message = value.isEmpty ? "已关闭 Spider 网关" : "Spider 网关已保存"
    }

    private func validHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }
}
