# Worker 任务：夸克+UC网盘 网盘 iOS 原生实现

## 目标
在 OK4KiOS 中实现 quark 网盘的真实 FishDriveService（替换 PendingFishDriveService），
协议端点已从 Android fish-spider.jar 逆向取证（见 Docs/NetdiskEndpointsEvidence.md 对应小节，
以及 Docs/quark-strings.txt / Docs/quark-calls.txt）。

## 已取证端点
夸克（g0.smali / C0244g0）：
- 基址 `https://drive.quark.cn/1/clouddrive/`；账号 `https://pan.quark.cn/account/info?fr=pc&platform=pc`
- 扫码 `https://uop.quark.cn/cas/ajax/getTokenForQrcodeLogin`（机制同 UC）
- 分享 token `.../share/sharepage/token?__t=`；下载 token `https://drive-social-api.quark.cn/1/clouddrive/chat/conv/file/acquire_dl_token?pr=ucpro&fr=pc&sys=win32&ve=3.15.0`
- 转存 `.../chat/conv/msg/batch_send?...`；会员 `.../member?...`；下载 `https://drive-pc.quark.cn/1/clouddrive/file/download?pr=ucpro&fr=pc`
- 分享正则 `https://pan\.quark\.cn/s/([^\\|#/?]+)`
UC（C0.smali / C0185C0）：
- 基址 `https://pc-api.uc.cn/1/clouddrive/`；账号 `https://drive.uc.cn/account/info?fr=pc&platform=pc`
- 扫码 `https://api.open.uc.cn/cas/ajax/getTokenForQrcodeLogin?__dt=641254&__t=`
- 文件 info `.../file/info?pr=UCBrowser&fr=pc&fid=`；列表 `pdir_fid=0&_page=1&_size=200&_sort=file_type:asc,updated_at:desc&__t=`
- 分享 token `.../share/sharepage/token?pr=UCBrowser&fr=pc&uc_param_str=&__dt=&__t=`；下载 `.../file/download?pr=UCBrowser&fr=pc&sys=win32&ve=1.8.6&ut=`
- 任务 `task?pr=UCBrowser&fr=pc&uc_param_str=&task_id=`；会员 `.../member?...`
- UA `uc-cloud-drive/1.8.7 Chrome/100.0.4896.160 Electron/18.3.5.16-b62cf9c50d Safari/537.36 Channel/ucpan_other_ch`

## 必须参考的实现模式
1. `OK4KiOS/Network/GuangyaDriveServiceAdapter.swift` — 完整生命周期适配器（创建→轮询→授权保存→刷新→退出）
2. `OK4KiOS/Network/GuangyaAuthService.swift` — 网络层（device code / poll / refresh / profile）
3. `OK4KiOS/Network/GuangyaSession.swift` — actor 会话 + FishCredentialStore 注入（Keychain 可测替身）
4. `OK4KiOS/Network/FishDriveService.swift` — FishDriveService 协议 + FishDriveRegistry（注意 override 注入点）
5. `Tests/FishDriveServiceTests.swift` — 测试模式（GuangyaMockHTTPClient + MemoryCredentialStore + adapter 注入 registry）

## 产出（必须全部提交到本分支）
- `OK4KiOS/Network/quarkDriveService.swift` — 协议实现（网络层）
- `OK4KiOS/Network/quarkDriveServiceAdapter.swift` — 实现 FishDriveService（含 protocolEvidence 注明取证来源）
- `OK4KiOS/Network/FishDriveService.swift` — FishDriveRegistry.service(for:) 注册新 adapter（替换默认 pending）
- `Tests/quarkDriveServiceTests.swift` — 生命周期测试（mock HTTP，不真网）
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
- 提交到当前分支并 push origin worker-quark_uc
- PROGRESS.md 记录完成状态与剩余卡点
