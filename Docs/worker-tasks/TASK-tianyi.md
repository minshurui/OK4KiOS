# Worker 任务：天翼云盘 网盘 iOS 原生实现

## 目标
在 OK4KiOS 中实现 tianyi 网盘的真实 FishDriveService（替换 PendingFishDriveService），
协议端点已从 Android fish-spider.jar 逆向取证（见 Docs/NetdiskEndpointsEvidence.md 对应小节，
以及 Docs/tianyi-strings.txt / Docs/tianyi-calls.txt）。

## 已取证端点
- 基址 `https://api.cloud.189.cn`
- 批量 `/batch/createBatchTask.action`、`/batch/checkBatchTask.action`
- 家庭 `/family/file`、`/family/manage/getFamilyList.action?clientType=TELEPC&version=6.2&channelId=web_cloud.189.cn`
- 分享 `/api/open/share/`；播放 `.../api/portal/getNewVlcVideoPlayUrl.action?shareId=`
- 用户 `/api/portal/v2/getUserBriefInfo.action`、`/api/portal/getUserSizeInfo.action`
- 登录方式（Android L1.l1()）：扫码 F2(27)/账号密码 K2(7)/短信验证码 K2(16)

## 必须参考的实现模式
1. `OK4KiOS/Network/GuangyaDriveServiceAdapter.swift` — 完整生命周期适配器（创建→轮询→授权保存→刷新→退出）
2. `OK4KiOS/Network/GuangyaAuthService.swift` — 网络层（device code / poll / refresh / profile）
3. `OK4KiOS/Network/GuangyaSession.swift` — actor 会话 + FishCredentialStore 注入（Keychain 可测替身）
4. `OK4KiOS/Network/FishDriveService.swift` — FishDriveService 协议 + FishDriveRegistry（注意 override 注入点）
5. `Tests/FishDriveServiceTests.swift` — 测试模式（GuangyaMockHTTPClient + MemoryCredentialStore + adapter 注入 registry）

## 产出（必须全部提交到本分支）
- `OK4KiOS/Network/tianyiDriveService.swift` — 协议实现（网络层）
- `OK4KiOS/Network/tianyiDriveServiceAdapter.swift` — 实现 FishDriveService（含 protocolEvidence 注明取证来源）
- `OK4KiOS/Network/FishDriveService.swift` — FishDriveRegistry.service(for:) 注册新 adapter（替换默认 pending）
- `Tests/tianyiDriveServiceTests.swift` — 生命周期测试（mock HTTP，不真网）
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
- 提交到当前分支并 push origin worker-tianyi
- PROGRESS.md 记录完成状态与剩余卡点
