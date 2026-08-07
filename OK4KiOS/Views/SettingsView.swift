import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var draft = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section("点播接口") {
                TextField("AppleCMS API 地址", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Button("保存") { save() }
                Button("恢复默认", role: .destructive) {
                    settings.reset()
                    draft = settings.vodAPI
                }
            }
            Section("兼容范围") {
                Text("最低 iOS 15.0")
                Text("重点设备：iPhone 12 / iOS 15.4")
            }
        }
        .navigationTitle("设置")
        .onAppear { draft = settings.vodAPI }
        .alert("设置", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func save() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            message = "请输入有效的 HTTP 或 HTTPS 接口地址"
            return
        }
        settings.vodAPI = value
        message = "已保存"
    }
}
