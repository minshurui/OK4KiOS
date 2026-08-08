# GoSpider csp_FishConfig 设置中心网关 — Swift 调用接口

> 模块：`GoSpider/pkg/fishconfig`（worker-A，分支 `worker-gospider`）
> C 桥接：`cmd/ok4kspider` 导出 `ok4k_action` / `ok4k_fishconfig_actions`
> 证据：`GoSpider/pkg/fishconfig/evidence/`（mock 自测）与 `evidence/live/`（实测探针）

## 1. 调用入口

Swift 通过 c-archive 静态库调用：

```c
const char* ok4k_action(const char* siteJSON);            // 网关分派
const char* ok4k_fishconfig_actions(void);                // action 目录
void ok4k_free(char* p);                                  // 释放返回值
```

`siteJSON` 结构（与现有 `ok4k_home/search/...` 的 siteJSON 一致）：

```json
{
  "site": "FishConfig",
  "api": "csp_FishConfig",
  "params": {
    "action": "quark_status",
    "payload": "{\"netdisk\":\"quark\",\"cookie\":\"__puus=...\"}"
  }
}
```

- `params.action`：必填。FishConfig 站点的 action 名（见 §3 全表）。
- `params.payload`：可选 JSON 字符串。status/login 传已保存凭证；thread 传新值；scan/login 空载荷表示发起登录。

## 2. 响应包络（所有 action 统一）

```json
{
  "ok": true,
  "action": "quark_status",
  "kind": "status",               // status|scan|login|thread|clean|magnet_switch|community_cookie|info|not_implemented|error
  "netdisk": "quark",
  "data": { ... },                // 见 §4 各 kind 的 data 结构
  "message": "夸克网盘已登录",      // 中文 UI 文案（可空）
  "error": ""                     // kind=error 时非空
}
```

约定：
- `ok=false` + `kind=error`：网关/客户端错误，`error` 字段为可展示信息。
- `kind=not_implemented`：Android 由 L1.a0 / Bili / FishDrive / 本地 switch 处理、Go 侧暂不接管的 action（poster_*、bili_*、fishdrive_*、系统栏目等）。
- 凭证持久化由 Swift 负责（Keychain，沿用 FishCredentialStore 抽象）：`kind=login` 响应里 `data.login.credential` 是**唯一需要落盘的 JSON**；status/login 请求时把它原样放进 `payload.credential` 传回。

## 3. Action 全表（与 Android FishConfig.action() 分派顺序一致）

分派顺序（`pkg/fishconfig/gateway.go` 忠实复刻 FishConfig.java:112-115）：
1. `L1.a0(str)` — `poster_*`（not_implemented）
2. `Bili.dispatchConfigAction(str)` — `bili_*`（not_implemented）
3. `FishDrive.dispatchConfigAction(str)` — `fishdrive_*`（not_implemented）
4. 本地 switch（76 case）→ 网盘 action 路由到 `pkg/fishconfig` 各客户端

### 网盘 action（Go 侧已实现）

| 网盘 | actions | 登录方式（Android 证据） |
|---|---|---|
| 夸克 quark | quark_status, quark_scan, quark_thread, quark_clean | 扫码（C0244g0，CAS getTokenForQrcodeLogin） |
| UC uc | uc_status, uc_scan, uc_token_scan, uc_thread, uc_clean | 扫码/Token（C0185C0，同源 CAS） |
| 天翼 tianyi | tianyi_status, tianyi_login, tianyi_thread, tianyi_clean | 扫码/账号密码/短信（C0278x0） |
| 阿里 ali | ali_status, ali_scan, ali_token, ali_thread, ali_clean | Token 输入 / OAuth 授权（C0239e） |
| 百度 baidu | baidu_status, baidu_scan, baidu_thread, baidu_clean | 扫码 / 手动 Cookie（C0243g） |
| 迅雷 xunlei | xunlei_status, xunlei_login, xunlei_thread, xunlei_clean | 扫码 / Token JSON（C0203L0） |
| 115 pan115 | pan115_status, pan115_login, pan115_magnet_switch, pan115_clean | Cookie 输入 / 扫码（C0210P） |
| 123 pan123 | pan123_status, pan123_login, pan123_community_cookie, pan123_thread, pan123_clean | 扫码授权/账号密码/Open Token（C0223W，litepan 中转） |
| 移动 yidong | yidong_status, yidong_login, yidong_clean | App扫码/账号密码/导入凭证（C0218T0） |
| 光鸭 guangya | guangya_status, guangya_login, guangya_community_cookie, guangya_magnet_switch, guangya_clean | 扫码/手动 Token（C0192G，与 iOS 三件套同协议） |

### 无独立 *_scan 的网盘（tianyi/xunlei/pan115/pan123/yidong/guangya）
Android 中这些网盘只有 `*_login`，扫码对话框由 `*_login` 打开。Go 侧一致：
**空 payload 调用 `*_login` 返回 `kind=login, data.stage="start"`**（含二维码/授权链接 + session），
再用 `*_login` + `payload.session` 完成轮询（`data.stage="done"`）。

## 4. data 结构（按 kind）

### kind=status
```json
{
  "logged_in": true,
  "account": { "name": "夸克用户", "avatar": "https://...", "user_id": "...", "vip": true, "extra": {} },
  "usage": { "used": 1024, "total": 2048 },
  "hint": "夸克网盘已登录"
}
```
未登录时 `logged_in=false`，`account` 缺省。

### kind=scan（quark/uc/baidu/ali 的 *_scan）
```json
{
  "kind": "qrcode",                     // qrcode | device_code | oauth_url | web
  "qr_image": "data:image/png;base64,...",   // 百度直接给图片
  "qr_url": "https://...",              // device_code/oauth_url/web 的跳转/二维码内容
  "qr_content": "..." ,
  "session": { "qrcode": "...", "qr_sign": "..." },
  "interval_seconds": 3,
  "timeout_seconds": 180,
  "hint": "使用夸克App扫码"
}
```

### kind=login（含扫码轮询结果）
```json
{
  "stage": "start",                    // start=发起（含 scan 字段） | done=完成（含 login 字段）
  "scan": { ... },                     // stage=start 时：二维码/授权链接 + session（同 kind=scan.data）
  "login": {
    "success": true,
    "credential": { "netdisk": "quark", "cookie": "__puus=...", "token": "", "raw": {} },
    "account": { "name": "夸克用户", ... },
    "hint": "夸克网盘登录成功"
  }
}
```
- 轮询由 Go 客户端内部完成（间隔/超时见 scan 返回）；`success=false` 表示扫码取消/过期/失败或凭证无效。
- 阿里/123 的授权码与 Open Token 均为 `*_token`/`*_login` 的 `payload.input` 文本。

### kind=thread
```json
{ "netdisk": "quark", "current": 4, "options": [1, 2, 4, 8, 16], "hint": "选择播放/转存线程数" }
```
设置：`payload = {"value": 8}`；非法值忽略并返回当前值。

### kind=clean / kind=magnet_switch / kind=community_cookie
```json
{ "cleared": true, "hint": "已清除本地登录信息" }
{ "netdisk": "pan115", "on": true, "hint": "..." }
{ "stage": "done", "login": { "success": true, "credential": {...}, ... } }  // 社区 Cookie 保存
```

## 5. 请求方载荷（payload）

| 场景 | payload 示例 |
|---|---|
| status：带凭证 | `{"netdisk":"quark","cookie":"__puus=...","token":"","raw":{}}` |
| status：带 token 型凭证 | `{"netdisk":"ali","token":"..."}` |
| login 发起（无 *_scan 网盘） | `""`（空） |
| login 轮询（session 来自 scan） | `{"session":{"qrcode":"...","qr_sign":"..."}}` |
| login 粘贴凭证 | `{"input":"COOKIE 串 或 Token JSON 或 短信码"}` |
| login 账号密码 | `{"account":"138...","password":"..."}` |
| login 短信 | `{"account":"138...","code":"123456"}` |
| thread 设置 | `{"value":8}` |
| magnet_switch | `{"on":true}` |

## 6. 端点与协议来源

- 端点全集：`/tmp/ok4k-para/w4/PROTOCOL.md` §9（quark/uc/ali/115/123/tianyi/xunlei/yidong/baidu 批量解码）。
- 登录方式与入口：PROTOCOL.md §3（L1.java 各 `*0()` 方法）。
- 每个网盘协议的实现注释里标注了证据来源与卡点（如 pan115 扫码 query 参数、xunlei client_id 需从 smali 补全）。
- 实测探针：`cmd/liveprobe`（`go run ./cmd/liveprobe`），结果在 `evidence/live/*.json`。

## 7. 自测与证据

```bash
cd GoSpider
go test ./pkg/fishconfig/ -v     # 14 个用例：网关分派 + 9 网盘 status/scan/login/thread/clean
go run ./cmd/liveprobe           # 真实端点可达性探针（无凭证）
# 产物：pkg/fishconfig/evidence/{netdisk}.json + evidence/live/*.json
```

## 8. 后续（Swift 侧接入建议）

1. `GoSiteAdapter`/`SpiderGatewayService` 对 `api=csp_FishConfig` 走 `ok4k_action`（现有 fishguard ext 桥接旁新增）。
2. Keychain 持久化 `login.credential`（沿用 FishCredentialStore 抽象，key 用 `credential.<netdisk>`）。
3. FishConfigSectionView 的“扫码登录”流程：`*_scan`（或空 payload `*_login`）→ 渲染 QR → 携带 session 调 `*_login` 轮询。
4. 未实现的系统栏目（poster_*/bili_*/fishdrive_*/系统设置）返回 not_implemented，由其余 worker 接管。
