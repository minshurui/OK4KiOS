import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var apiDraft = ""
    @State private var configDraft = ""
    @State private var gatewayDraft = ""
    @State private var sites: [TVBoxSite] = []
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("点播接口") {
                TextField("AppleCMS API 地址", text: $apiDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button("保存接口") { saveAPI() }
            }
            Section("TVBox 配置") {
                TextField("配置 JSON 地址", text: $configDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button(isLoading ? "加载中…" : "导入配置") { Task { await importConfig() } }
                    .disabled(isLoading)
                ForEach(sites) { site in
                    Button {
                        settings.selectedSite = site
                        if site.type == 0 || site.type == 1 { apiDraft = site.api; settings.vodAPI = site.api }
                        message = "已启用：\(site.name)"
                    } label: {
                        VStack(alignment: .leading) {
                            Text((settings.selectedSite?.id == site.id ? "✓ " : "") + site.name)
                            Text(site.type == 3 ? "Spider · \(site.nativeBaseURLs.first?.host ?? "网关执行")" : site.api)
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
                Text("带站点网址的 type 3 规则由 App 内置 Swift Spider 直接运行；加密 JAR 规则通过兼容网关调用同一套 home/category/detail/search/player 协议。")
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
                    configDraft = ""
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
        }
        .alert("设置", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
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
            let loaded = try await ConfigService().load(urlString: value)
            settings.configURL = value
            sites = loaded
            message = loaded.isEmpty ? "配置中没有可用站点" : "已导入 \(loaded.count) 个接口（含 type 3 Spider），请点击一个启用"
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
