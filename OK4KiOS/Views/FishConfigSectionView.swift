import SwiftUI
import CoreImage.CIFilterBuiltins

struct FishConfigSectionView: View {
    let section: FishConfigSection
    @State private var message: String?
    @State private var showingGuangyaLogin = false
    @State private var guangyaRevision = 0
    @State private var guangyaStatus = "正在读取账号状态…"

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
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            if FishConfigCatalog.actions(for: section).isEmpty {
                Text("该栏目正在按 Android FishConfig 协议逐项移植，尚未完成的动作不会伪装为可用。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle(section.title)
        .sheet(isPresented: $showingGuangyaLogin) {
            NavigationView {
                GuangyaLoginView {
                    guangyaRevision += 1
                    showingGuangyaLogin = false
                }
            }
            .navigationViewStyle(.stack)
        }
        .task(id: guangyaRevision) {
            guard section == .guangya else { return }
            do {
                let credential = try await GuangyaSession.shared.validatedCredential()
                guangyaStatus = credential.displayName.map { "已登录 · \($0)" } ?? "已登录"
            } catch GuangyaAuthError.notLoggedIn {
                guangyaStatus = "需要扫码登录"
            } catch {
                guangyaStatus = "登录已失效，请重新扫码"
            }
        }
        .alert(section.title, isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func detail(for action: FishConfigAction) -> String {
        action.id == "guangya_status" ? guangyaStatus : action.detail
    }

    private func run(_ action: FishConfigAction) {
        switch action.id {
        case "guangya_login": showingGuangyaLogin = true
        case "guangya_status":
            Task {
                do {
                    let credential = try await GuangyaSession.shared.validatedCredential()
                    let account = credential.displayName.map { "（\($0)）" } ?? ""
                    await MainActor.run { guangyaStatus = "已登录" + account; message = "光鸭网盘已登录" + account }
                } catch { await MainActor.run { message = error.localizedDescription } }
            }
        case "guangya_clean":
            Task {
                do {
                    try await GuangyaSession.shared.logout()
                    await MainActor.run { guangyaRevision += 1; guangyaStatus = "需要扫码登录"; message = "光鸭账号已清除" }
                } catch { await MainActor.run { message = error.localizedDescription } }
            }
        default:
            message = "“\(action.title)”的 Android action 已定位，原生协议仍在移植；当前不会用手动导入或空结果代替。"
        }
    }
}

private struct GuangyaLoginView: View {
    @Environment(\.presentationMode) private var presentationMode
    let onSuccess: () -> Void
    @State private var authorization: GuangyaDeviceAuthorization?
    @State private var status = "正在创建二维码…"
    @State private var errorText: String?
    @State private var loginTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            if let authorization, let image = QRCode.image(authorization.verificationURL.absoluteString) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 320)
                    .accessibilityLabel("光鸭登录二维码")
                Text("使用浏览器或相机扫描二维码完成光鸭授权")
                    .multilineTextAlignment(.center)
                Link("在本机浏览器打开授权页面", destination: authorization.verificationURL)
            } else if errorText == nil {
                ProgressView()
            }
            Text(errorText ?? status)
                .font(.caption)
                .foregroundColor(errorText == nil ? .secondary : .red)
                .multilineTextAlignment(.center)
            if errorText != nil { Button("重试") { start() } }
            Spacer()
        }
        .padding()
        .navigationTitle("光鸭扫码登录")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { loginTask?.cancel(); presentationMode.wrappedValue.dismiss() }
            }
        }
        .onAppear { start() }
        .onDisappear { loginTask?.cancel() }
    }

    private func start() {
        loginTask?.cancel()
        authorization = nil
        errorText = nil
        status = "正在创建二维码…"
        loginTask = Task {
            do {
                let service = GuangyaAuthService()
                let auth = try await service.begin()
                try Task.checkCancellation()
                await MainActor.run { authorization = auth; status = "等待扫码授权…" }
                let deadline = Date().addingTimeInterval(auth.expiresIn)
                while Date() < deadline {
                    try Task.checkCancellation()
                    switch try await service.poll(deviceCode: auth.deviceCode) {
                    case .pending:
                        try await Task.sleep(nanoseconds: UInt64(auth.interval * 1_000_000_000))
                    case .authorized(let credential):
                        let saved = try await GuangyaSession.shared.finishLogin(credential)
                        let suffix = saved.displayName.map { " · \($0)" } ?? ""
                        await MainActor.run { status = "光鸭网盘登录成功" + suffix; onSuccess() }
                        return
                    }
                }
                throw GuangyaAuthError.timeout
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }
}

private enum QRCode {
    static func image(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
