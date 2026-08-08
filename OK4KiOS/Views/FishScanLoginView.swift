import SwiftUI
import CoreImage.CIFilterBuiltins

/// 通用网盘扫码登录页：创建 → 展示二维码 → 轮询 → 授权 → 退出。
/// 完整生命周期由 FishDriveService（光鸭完整适配器 / 其余网盘诚实 pending）驱动；
/// 不支持扫码的网盘不会进入本页（入口处已拦截并给出取证状态）。
struct FishScanLoginView: View {
    let driveKey: String
    let onSuccess: () -> Void

    @Environment(\.presentationMode) private var presentationMode
    @State private var session: FishScanSession?
    @State private var status = "正在创建二维码…"
    @State private var errorText: String?
    @State private var loginTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            if let session, let image = QRCode.image(session.qrPayload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 320)
                    .accessibilityLabel("\(driveName)登录二维码")
                Text("使用浏览器或相机扫描二维码完成\(driveName)授权")
                    .multilineTextAlignment(.center)
                if let url = session.openURL {
                    Link("在本机浏览器打开授权页面", destination: url)
                }
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
        .navigationTitle("\(driveName)扫码登录")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { loginTask?.cancel(); presentationMode.wrappedValue.dismiss() }
            }
        }
        .onAppear { start() }
        .onDisappear { loginTask?.cancel() }
    }

    private var driveName: String { FishDriveRegistry.service(for: driveKey).displayName }

    private func start() {
        loginTask?.cancel()
        session = nil
        errorText = nil
        status = "正在创建二维码…"
        loginTask = Task {
            do {
                let service = FishDriveRegistry.service(for: driveKey)
                let created = try await service.beginLogin()
                try Task.checkCancellation()
                await MainActor.run { session = created; status = "等待扫码授权…" }
                let deadline = Date().addingTimeInterval(created.expiresIn)
                while Date() < deadline {
                    try Task.checkCancellation()
                    switch try await service.poll(created) {
                    case .pending:
                        try await Task.sleep(nanoseconds: UInt64(created.interval * 1_000_000_000))
                    case .authorized:
                        await MainActor.run { status = "\(driveName)登录成功"; onSuccess() }
                        return
                    }
                }
                throw FishDriveError.timeout
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }
}

/// 网盘登录二维码生成（CoreImage，与 Android 扫码内容一致）。
enum QRCode {
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
