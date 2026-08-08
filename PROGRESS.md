# PROGRESS — worker-A (GoSpider 网关) / 分支 worker-gospider

- [x] 网关：csp_FishConfig action 分派（L1.a0 → Bili → FishDrive → 本地 76-case switch 忠实复刻）—— gateway.go + gateway_test.go
- [x] 夸克 quark：status/scan/login(轮询)/thread/clean —— quark.go + 自测 + evidence
- [x] UC uc：status/scan/token_scan/thread/clean —— uc.go + 自测 + evidence
- [x] 天翼 tianyi：status/scan(经 login)/login(轮询/账号密码/短信/cookie)/thread/clean —— tianyi.go + 自测 + evidence
- [x] 阿里 ali：status/scan(OAuth URL)/token(输入+刷新+授权码)/thread/clean —— ali.go + 自测 + evidence
- [x] 百度 baidu：status/scan/login(轮询+BDUSS+cookie)/thread/clean —— baidu.go + 自测 + evidence
- [x] 迅雷 xunlei：status/scan(设备码)/login(轮询+Token JSON)/thread/clean —— xunlei.go + 自测 + evidence
- [x] 115 pan115：status/scan/login(轮询+cookie)/magnet_switch/clean —— pan115.go + 自测 + evidence
- [x] 123 pan123：status/scan(litepan OAuth)/login(轮询+Token+账号密码)/community_cookie/thread/clean —— pan123.go + 自测 + evidence（litepan start 实测跑通）
- [x] 移动 yidong：status/scan(扫码页)/login(凭证/账号密码/轮询)/clean —— yidong.go + 自测 + evidence
- [x] 光鸭 guangya：status/scan(设备码)/login(轮询)/community_cookie/magnet_switch/clean —— guangya.go（Go 镜像 iOS 三件套协议）+ 自测 + evidence
- [x] C 桥接：ok4k_action / ok4k_fishconfig_actions 导出（cmd/ok4kspider/bridge.go）
- [x] 接口文档：GoSpider/API.md（请求/响应 JSON 结构 + action 全表 + Swift 接入建议）
- [x] 实测探针：cmd/liveprobe（quark/uc/123/tianyi/115/xunlei/yidong/baidu/ali 真实端点可达性 → evidence/live/）
- [ ] 遗留（需 smali 方法级补全）：pan115 扫码 query 参数、xunlei client_id、139 queryId 网络可达性、各网盘成功扫码真机样本
