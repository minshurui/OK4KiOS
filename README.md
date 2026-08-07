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

当前仅完成工程、网络层和 AVPlayer 播放器骨架。Spider、代理、FFmpeg、完整页面和数据迁移尚未完成，不能把当前骨架视为完整产品。
