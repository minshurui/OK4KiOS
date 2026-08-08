import SwiftUI

/// FishConfig 栏目页：10 个网盘入口 + 控制台/系统等栏目。
/// 所有 action 经 FishConfigGateway 分派：
/// - status：本地协议状态（光鸭读 Keychain+刷新；其余网盘如实报告取证状态）
/// - scanLogin：支持扫码的网盘进入 FishScanLoginView（创建/轮询/退出）；
///   协议未完成的网盘诚实提示，绝不伪装为可用
/// - thread：线程偏好页（普通/会员，本地存储，与 Android 同语义）
/// - clean：真实删除本地凭据（Keychain）
/// - other：Android action 已定位但协议仍在移植 → 诚实提示
struct FishConfigSectionView: View {
    let section: FishConfigSection

    @State private var message: String?
    @State private var statusDetails: [String: String] = [:]
    @State private var scanLoginDriveKey: String?
    @State private var threadDriveKey: String?
    @State private var pendingCleanActionID: String?
    @State private var revision = 0

    var body: some View {
        List {
            ForEach(FishConfigCatalog.actions(for: section)) { action in
                Button { run(action) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(action.title).foregroundColor(.primary)
                            Text(detail(for: action)).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: chevron(for: action))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            if FishConfigCatalog.actions(for: section).isEmpty {
                Text("该栏目正在按 Android FishConfig 协议逐项移植，尚未完成的动作不会伪装为可用。")
                    .font(.caption).foregroundColor(.secondary)
            }
            if section.isDriveSection {
                Text("凭据仅保存在本机 Keychain；登录协议以 Android FishConfig 取证为准，未完成取证的网盘不会假装能扫码。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle(section.title)
        .task(id: revision) { await refreshStatuses() }
        .sheet(isPresented: scanLoginBinding) {
            if let driveKey = scanLoginDriveKey {
                NavigationView {
                    FishScanLoginView(driveKey: driveKey) {
                        revision += 1
                        scanLoginDriveKey = nil
                    }
                }
                .navigationViewStyle(.stack)
            }
        }
        .sheet(isPresented: threadBinding) {
            if let driveKey = threadDriveKey {
                FishThreadPickerView(driveKey: driveKey, title: section.title)
            }
        }
        .alert(section.title, isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            if let pendingCleanActionID {
                Button("取消", role: .cancel) { self.pendingCleanActionID = nil }
                Button("清除", role: .destructive) {
                    let actionID = pendingCleanActionID
                    self.pendingCleanActionID = nil
                    performClean(actionID)
                }
            } else {
                Button("确定", role: .cancel) { pendingCleanActionID = nil }
            }
        } message: { Text(message ?? "") }
    }

    private var scanLoginBinding: Binding<Bool> {
        Binding(get: { scanLoginDriveKey != nil }, set: { if !$0 { scanLoginDriveKey = nil } })
    }

    private var threadBinding: Binding<Bool> {
        Binding(get: { threadDriveKey != nil }, set: { if !$0 { threadDriveKey = nil } })
    }

    // MARK: - 展示

    private func detail(for action: FishConfigAction) -> String {
        statusDetails[action.id] ?? action.detail
    }

    private func chevron(for action: FishConfigAction) -> String {
        switch action.kind {
        case .scanLogin, .thread: return "chevron.right"
        case .status, .clean, .other: return "arrow.right.circle"
        }
    }

    // MARK: - 分派

    private func run(_ action: FishConfigAction) {
        switch action.kind {
        case .status:
            performStatus(action.id)
        case .scanLogin:
            openScanLogin(action)
        case .thread:
            guard let driveKey = section.driveKey else { fallback(action); return }
            threadDriveKey = driveKey
        case .clean:
            pendingCleanActionID = action.id
            message = "确定清除\(section.title)登录凭据？清除后需重新登录。"
        case .other:
            fallback(action)
        }
    }

    private func openScanLogin(_ action: FishConfigAction) {
        guard let driveKey = section.driveKey else { fallback(action); return }
        let service = FishDriveRegistry.service(for: driveKey)
        guard service.supportsScanLogin else {
            message = service.protocolEvidence + "；扫码动作不会伪装为可用。"
            return
        }
        scanLoginDriveKey = driveKey
    }

    private func performStatus(_ actionID: String) {
        Task {
            do {
                let result = try await FishConfigGateway.perform(actionID: actionID, section: section)
                await MainActor.run {
                    if let status = result.status { statusDetails[actionID] = status.detail }
                    message = result.message
                }
            } catch {
                await MainActor.run { message = error.localizedDescription }
            }
        }
    }

    private func performClean(_ actionID: String) {
        Task {
            do {
                let result = try await FishConfigGateway.perform(actionID: actionID, section: section)
                await MainActor.run {
                    statusDetails = [:]
                    revision += 1
                    message = result.message
                }
            } catch {
                await MainActor.run { message = error.localizedDescription }
            }
        }
    }

    private func fallback(_ action: FishConfigAction) {
        message = "“\(action.title)”的 Android action 已定位，原生协议仍在移植；当前不会用手动导入或空结果代替。"
    }

    private func refreshStatuses() async {
        for action in FishConfigCatalog.actions(for: section) where action.kind == .status {
            if let result = try? await FishConfigGateway.perform(actionID: action.id, section: section),
               let status = result.status {
                statusDetails[action.id] = status.detail
            }
        }
    }
}
