import SwiftUI

/// Native iPhone/iPad counterpart of the TVBox FishConfig entry.
/// FishConfig remains in imported configurations and opens this control page
/// instead of being treated as a movie catalogue.
struct FishFeatureCenterView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var settings = AppSettings.shared
    @State private var vodAPI = ""
    @State private var configURL = ""
    @State private var liveSource = ""
    @State private var gateway = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section("点播接口") {
                Picker("接口格式", selection: $settings.vodAPIType) {
                    Text("JSON · type 1").tag(1)
                    Text("XML · type 0").tag(0)
                }
                .pickerStyle(.segmented)
                TextField("点播 API 地址", text: $vodAPI)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button("保存点播接口") { saveVodAPI() }
            }

            Section("TVBox 与直播") {
                TextField("TVBox 配置地址", text: $configURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button("保存配置地址") { saveURL(configURL, title: "配置地址") { settings.configURL = $0 } }
                TextField("M3U/M3U8 直播源", text: $liveSource)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button("保存直播源") { saveURL(liveSource, title: "直播源", allowEmpty: true) { settings.liveSource = $0 } }
            }

            Section("播放能力") {
                Toggle("点播默认使用 FFmpeg", isOn: $settings.preferFFmpeg)
                feature("直播播放", detail: "AVPlayer · 后台音频 · AirPlay · 画中画", icon: "play.tv")
                feature("音频兼容", detail: "MP2、AC3、E-AC3、DTS/DTS-HD", icon: "speaker.wave.3")
            }

            Section("Spider 兼容") {
                TextField("Spider 网关（可选）", text: $gateway)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button("保存兼容地址") { saveURL(gateway, title: "Spider 网关", allowEmpty: true) { settings.spiderGateway = $0 } }
                Text("iPhone/iPad 优先使用原生适配器。网关仅用于尚未完成原生移植的个别站点，留空不会影响原生接口。")
                    .font(.caption).foregroundColor(.secondary)
            }

        }
        .navigationTitle("设置中心")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { presentationMode.wrappedValue.dismiss() }
            }
        }
        .onAppear {
            vodAPI = settings.vodAPI
            configURL = settings.configURL
            liveSource = settings.liveSource
            gateway = settings.spiderGateway
        }
        .alert("设置中心", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func saveVodAPI() {
        guard let value = validatedURL(vodAPI, allowEmpty: false) else {
            message = "请输入有效的 HTTP 或 HTTPS 点播地址"
            return
        }
        settings.vodAPI = value
        settings.selectedSite = nil
        message = "点播接口已保存"
    }

    private func saveURL(_ draft: String, title: String, allowEmpty: Bool = false, apply: (String) -> Void) {
        guard let value = validatedURL(draft, allowEmpty: allowEmpty) else {
            message = "请输入有效的 HTTP 或 HTTPS \(title)"
            return
        }
        apply(value)
        message = value.isEmpty ? "已清空\(title)" : "\(title)已保存"
    }

    private func validatedURL(_ draft: String, allowEmpty: Bool) -> String? {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return allowEmpty ? "" : nil }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return value
    }

    private func feature(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(OKTheme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

}
