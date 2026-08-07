import SwiftUI

/// Native iPhone/iPad counterpart of the TVBox FishConfig entry.
///
/// FishConfig is intentionally retained in imported configurations. Android
/// implementations expose many device-specific actions through Spider.action;
/// iOS-owned settings are available here while account/drive actions are
/// migrated individually instead of pretending the Android JAR can run on iOS.
struct FishFeatureCenterView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("播放能力") {
                Toggle("点播默认使用 FFmpeg", isOn: $settings.preferFFmpeg)
                feature("直播播放", detail: "AVPlayer · 后台音频 · AirPlay · 画中画", icon: "play.tv")
                feature("音频兼容", detail: "MP2、AC3、E-AC3、DTS/DTS-HD", icon: "speaker.wave.3")
            }

            Section("接口与兼容") {
                feature("TVBox 配置", detail: "保留 type 0/1/3/4 和 FishConfig", icon: "list.bullet.rectangle")
                feature("本地媒体代理", detail: "Header、Cookie、Range、HLS 资源重写", icon: "network")
                feature("Spider 网关", detail: settings.spiderGateway.isEmpty ? "未启用（可选兜底）" : "已配置可选兼容地址", icon: "externaldrive.connected.to.line.below")
            }

            Section("FishConfig 原生移植") {
                migration("账号与网盘管理")
                migration("海报与首页布局设置")
                migration("解析与播放规则设置")
                migration("站点状态及缓存工具")
                Text("这些入口没有删除。Android FishConfig 的 action 调用依赖 Android UI、存储和账号组件，正在按功能逐项改写为 Swift；不会要求 iPhone 必须连接 Android。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("设置中心")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { presentationMode.wrappedValue.dismiss() }
            }
        }
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

    private func migration(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("移植中").font(.caption).foregroundColor(.orange)
        }
    }
}
