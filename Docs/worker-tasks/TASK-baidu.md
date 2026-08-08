# Worker 任务：百度网盘 网盘 iOS 原生实现

## 目标
在 OK4KiOS 中实现 baidu 网盘的真实 FishDriveService（替换 PendingFishDriveService），
协议端点已从 Android fish-spider.jar 逆向取证（见 Docs/NetdiskEndpointsEvidence.md 对应小节，
以及 Docs/baidu-strings.txt / Docs/baidu-calls.txt）。

## 已取证端点
- 端点证据最少（g.smali 仅 242 行，百度核心委托 C0243g + W0/A 类）
- Android 登录（L1.H0()）：扫码登录 K2(17) + 手动 Cookie（r1）
- 存储方式：Cookie 持久化（非 OAuth token）
- 若扫码/轮询端点无法从 smali 取证：诚实 pending（FishDriveError.protocolPending），
  实现 clean/status/thread（真实），登录项标 protocolPending 并在 PROGRESS.md 记录卡点
- 可继续用 Tools/smali-decoder/decode_netdisk.py + /root/OK4K-debug-assets/fish-spider/sources 取证

## 必须参考的实现模式
1. `OK4KiOS/Network/GuangyaDriveServiceAdapter.swift` — 完整生命周期适配器（创建→轮询→授权保存→刷新→退出）
2. `OK4KiOS/Network/GuangyaAuthService.swift` — 网络层（device code / poll / refresh / profile）
3. `OK4KiOS/Network/GuangyaSession.swift` — actor 会话 + FishCredentialStore 注入（Keychain 可测替身）
4. `OK4KiOS/Network/FishDriveService.swift` — FishDriveService 协议 + FishDriveRegistry（注意 override 注入点）
5. `Tests/FishDriveServiceTests.swift` — 测试模式（GuangyaMockHTTPClient + MemoryCredentialStore + adapter 注入 registry）

## 产出（必须全部提交到本分支）
- `OK4KiOS/Network/baiduDriveService.swift` — 协议实现（网络层）
- `OK4KiOS/Network/baiduDriveServiceAdapter.swift` — 实现 FishDriveService（含 protocolEvidence 注明取证来源）
- `OK4KiOS/Network/FishDriveService.swift` — FishDriveRegistry.service(for:) 注册新 adapter（替换默认 pending）
- `Tests/baiduDriveServiceTests.swift` — 生命周期测试（mock HTTP，不真网）
- `PROGRESS.md` — 追加工作日志（M1..Mn）

## 硬约束
- 不硬编码 Token/Cookie；缺凭据抛明确错误（参考 GuangyaAuthError.notLoggedIn）
- 动态 JSON 无损保留未知字段（深合并 + 已知字段投影，参考 GuangyaCredential.init）
- 登录交互与 Android 一致：扫码页走 FishScanLoginView（FishConfigSectionView 已接 scanLogin action）
- 登录完整流程：创建二维码→轮询（间隔/超时按 Android）→授权后持久化→refresh→logout（删凭据）
- 若某协议细节（如轮询成功判定字段）证据不足：诚实保留 pending（抛 FishDriveError.protocolPending），
  不得臆造请求体/响应字段；在 PROGRESS.md 记录卡点
- 线程设置用 FishThreadStore（UserDefaults），值与 Android 线程选项一致

## 验证（必须全绿才提交）
- `swiftc -parse` 通过新增/改动文件（Linux 用 docker：`docker run --rm -v $PWD:/src -w /src swift:5.9 swiftc -parse <files>`）
- 若有条件跑完整测试更好；至少 parse + 现有测试文件不改坏
- `git diff --check` 通过

## 完成后
- 提交到当前分支并 push origin worker-baidu
- PROGRESS.md 记录完成状态与剩余卡点
