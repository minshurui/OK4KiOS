import SwiftUI

/// Add or edit a TVBox site entry (Android 设置 → 站点管理 equivalent).
struct SiteEditSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    let site: TVBoxSite?
    let onSave: (TVBoxSite) -> Void

    @State private var key = ""
    @State private var name = ""
    @State private var type = 1
    @State private var api = ""
    @State private var extValue = ""
    @State private var jar = ""
    @State private var message: String?

    private let typeOptions = [(0, "XML · type 0"), (1, "JSON · type 1"), (3, "Spider · type 3"), (4, "规则 · type 4")]

    init(site: TVBoxSite?, onSave: @escaping (TVBoxSite) -> Void) {
        self.site = site
        self.onSave = onSave
        _key = State(initialValue: site?.key ?? "")
        _name = State(initialValue: site?.name ?? "")
        _type = State(initialValue: site?.type ?? 1)
        _api = State(initialValue: site?.api ?? "")
        _extValue = State(initialValue: site?.ext?.encodedString ?? "")
        _jar = State(initialValue: site?.jar ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("站点信息") {
                    TextField("key（唯一标识）", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                    TextField("名称", text: $name)
                    Picker("类型", selection: $type) {
                        ForEach(typeOptions, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }
                }
                Section("接口") {
                    TextField("api 地址 / csp_ 名称", text: $api)
                        .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                    if type == 3 {
                        TextField("ext（JSON，可选）", text: $extValue, axis: .vertical)
                            .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                            .lineLimit(2...4)
                        TextField("jar 地址（可选）", text: $jar)
                            .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                    }
                }
                Section {
                    Button("保存") { save() }
                }
            }
            .navigationTitle(site == nil ? "添加站点" : "编辑站点")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .alert("站点", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("确定", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAPI = api.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { message = "key 不能为空"; return }
        guard !cleanName.isEmpty else { message = "名称不能为空"; return }
        guard !cleanAPI.isEmpty else { message = "api 不能为空"; return }
        let ext: JSONValue? = {
            let value = extValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            if let data = value.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(JSONValue.self, from: data) {
                return parsed
            }
            return JSONValue.string(value)
        }()
        let created = TVBoxSite(
            key: cleanKey,
            name: cleanName,
            type: type,
            api: cleanAPI,
            searchable: true,
            quickSearch: true,
            filterable: false,
            ext: ext,
            jar: jar.trimmingCharacters(in: .whitespacesAndNewlines),
            headers: [:]
        )
        onSave(created)
        presentationMode.wrappedValue.dismiss()
    }
}
