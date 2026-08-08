import SwiftUI

/// 下载线程选择页（普通/会员）。
/// Android FishConfig 的 thread action 是本地偏好选择（SharedPreferences），
/// 不涉及网盘协议；iOS 以 UserDefaults 替代存储层，保持同样的本地语义。
struct FishThreadPickerView: View {
    let driveKey: String
    let title: String

    @Environment(\.presentationMode) private var presentationMode
    @State private var selected = FishThreadOption.normal.id

    private let store = FishThreadStore.shared

    var body: some View {
        NavigationView {
            Form {
                Section("下载线程") {
                    ForEach(FishThreadOption.all) { option in
                        Button {
                            selected = option.id
                            store.set(option.id, for: driveKey)
                        } label: {
                            HStack {
                                Text(option.title).foregroundColor(.primary)
                                Spacer()
                                if selected == option.id {
                                    Image(systemName: "checkmark").foregroundColor(OKTheme.accent)
                                }
                            }
                        }
                    }
                }
                Text("线程偏好与 Android FishConfig 同语义（普通/会员），仅保存在本机，不涉及网盘协议。")
                    .font(.caption).foregroundColor(.secondary)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .onAppear { selected = store.value(for: driveKey) }
        }
        .navigationViewStyle(.stack)
    }
}
