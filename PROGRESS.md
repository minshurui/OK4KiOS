# worker-B（Swift 设置中心）进度 — 分支 worker-swift

## 任务
FishConfig 设置中心：SiteModels 特判确认 + 10 网盘栏目 UI + 扫码登录（创建/轮询/刷新/退出）+ 状态/线程/清理 + 数据层网关接入。
网关接口：/root/tv-ios-w1/GoSpider/API.md 未生成 → 按 PROTOCOL.md 直接实现本地调用，接口后续对齐（Go 符号 ok4k_fishconfig 动态探测，存在即切 Go）。

## 日志（追加式）
- [M1] 确认 SiteModels.swift:57-60：isFeatureCenter(:57-58) 特判 FishConfig；canRunNatively(:60) 对 type3 需 nativeBaseURLs 非空 → FishConfig=false（功能中心不应作为 VOD 执行，正确）；VodServiceFactory 补硬防护：FishConfig 永不构造点播服务
- [M2] FishConfigModels 增补：FishConfigSection.driveKey/isDriveSection（10 网盘）、FishConfigAction.kind（status/scanLogin/thread/clean/other）分派
- [M3] 数据层：FishDriveService 协议（status/beginLogin/poll/refresh/logout/thread）+ FishScanSession/FishDriveStatus/FishDriveError + FishThreadStore(UserDefaults)
- [M4] 数据层：GuangyaDriveServiceAdapter（完整生命周期：device code 创建→3s 轮询→refresh_token 刷新→Keychain 退出，复用 GuangyaAuthService/Session）
- [M5] 数据层：PendingFishDriveService（9 网盘协议取证未完成，登录抛 protocolPending 不伪装；clean/status 诚实实现）+ FishDriveRegistry
- [M6] 数据层：FishConfigGateway（本地优先；GoSpiderBridge.supportsFishConfig 存在时走 ok4k_fishconfig，JSON 信封契约已注释）
- [M7] UI：FishScanLoginView 通用扫码页（创建/轮询/超时/重试/取消）+ FishThreadPickerView 线程选择
- [M8] UI：FishConfigSectionView 全 action 分派（login/status/thread/clean/other 诚实路由）
- [M9] 测试：Tests/FishDriveServiceTests.swift（registry/pending/线程/网关/适配器）
- [M10] 收尾：swift:5.9 docker 语法 parse + 纯 Foundation 层 typecheck 全绿（0 error）；清理临时检查脚本；提交
