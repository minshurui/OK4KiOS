# OK影视4K iOS

iPhone/iPad 原生移植工程，最低支持 iOS 15.0（重点兼容 iPhone 12 / iOS 15.4）。目标是保持 Android 版主要功能，并输出可由 TrollStore 安装的 IPA。

## 构建架构

- Linux Docker：源码开发、通用 Swift 逻辑和辅助工具。
- GitHub Actions macOS：Xcode/iOS SDK 编译和无签名 IPA 打包。
- TrollStore：设备端安装。

> Linux Docker 无法运行 Xcode，因此不能单独完成 iOS 最终编译。

## 本地 Docker

```bash
docker compose build
docker compose up -d
docker compose exec ios-dev swift --version
```

## macOS / CI 构建

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project OK4KiOS.xcodeproj -scheme OK4KiOS -sdk iphoneos \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

GitHub Actions 会生成 `OK4KiOS-TrollStore-unsigned.ipa` artifact。

## 当前状态

已完成可安装的 iPhone/iPad 原生版本：AppleCMS 点播首页、分类、分页、搜索、详情、多线路选集、TVBox 配置导入、收藏、历史、断点续播、M3U 直播、AVPlayer 硬件播放、倍速、AirPlay、后台音频和系统画中画。最低部署版本为 iOS 15.0。

播放器提供系统 AVPlayer 与 KSPlayer/FFmpeg 双引擎切换。默认 AVPlayer 保持系统硬件解码和最低功耗；遇到 MP2、AC3、E-AC3、DTS/DTS-HD 等系统不支持的音轨时，可在播放页右上角切换 FFmpeg 引擎，KSPlayer 会继续使用 VideoToolbox 硬件视频解码并由 FFmpeg 处理音频。

已内置仅监听 `127.0.0.1:9978...9998` 的 Swift HTTP 代理，支持 Header、Range、HTTP 状态透传及 HLS 播放列表相对地址重写，用于需要 Cookie/Referer 的分片媒体。

TVBox 点播现区分 type 0 XML、type 1 JSON、type 3 Spider 和 type 4 规则接口，不再把所有 HTTP API 当成 AppleCMS JSON。type 3 带 `site`、`host` 或 `url` 扩展网址的规则由 SwiftSoup 网络内核直接执行首页、分类、搜索、详情和播放解析；其余加密 JAR/Guard 及 type 4 规则可配置 Spider Gateway，通过统一的 home/category/detail/search/player JSON 协议交给 Android 原版 `SiteApi` 执行。配置导入会保留 type 0/1/3/4 站点，并把配置顶层 `spider` JAR 继承到每个未单独声明 JAR 的站点。

配套 Android 版已增加 `POST /api/spider` 网关端点。Android 设备需先载入与 iOS 相同的 TVBox 配置；网关只执行该配置中已加载的 type 3 站点，避免客户端提交任意 JAR。iOS 设置中的网关填写 Android 设备地址（例如 `http://192.168.1.20:9978`），实际端口以 Android App 服务页显示为准。两台设备需在同一可信局域网或 Tailscale 网络中。
