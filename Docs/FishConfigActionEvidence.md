# FishConfig Android Action 协议证据表

> 状态定义：`已取证`＝已从反编译源码定位；`已采样`＝已有真实请求/响应样本；`已复现`＝脱离 Android 的独立脚本跑通；`已实现`＝已接 iOS 业务；`已编译`、`真机通过`另行记录。不得互相替代。
>
> 本文当前只记录取证。除既有提交内容外，不代表任何 action 已接入业务。

## 1. 可复现的 ID 解码

```bash
Tools/decode_fishconfig_strings.py \
  /root/OK4K-debug-assets/fish-spider/sources/com/github/catvod/spider/FishConfig.java \
  --from-line 118 --to-line 1040
```

算法证据：`C0008.m30`、`C0009.m33`、`C0010.m39`、`C0012.m47`、`C0013.m51`、`C0014.m55`、`C0015.m56` 均为 `short[offset+i] XOR key`。

## 2. Android 栏目与 action 清单

| 栏目 ID | 栏目 | 已解码 action ID | 当前证据状态 |
|---|---|---|---|
| 1 | 夸克 | `quark_status`, `quark_scan`, `quark_thread`, `quark_clean` | ID 已取证；协议待追 |
| 2 | UC | `uc_status`, `uc_scan`, `uc_thread`, `uc_token_scan`, `uc_clean` | ID 已取证；协议待追 |
| 3 | 天翼 | `tianyi_status`, `tianyi_login`, `tianyi_thread`, `tianyi_clean`, `tianyi_help` | ID 已取证；协议待追 |
| 4 | 阿里 | `ali_status`, `ali_scan`, `ali_token`, `ali_thread`, `ali_clean` | ID 已取证；协议待追 |
| 5 | 系统 | `home_menu_manage`, `backup_mode`, `settings_menu_manage`, `config_performance`, `pan_filter`, `magnet_config`, `quality_config`, `config_clear`, `usage_help` 等 | ID 已取证；分派待逐项追 |
| 6 | 百度 | `baidu_status`, `baidu_scan`, `baidu_thread`, `baidu_clean` | ID 已取证；协议待追 |
| 7 | 弹幕 | `danmu_toggle`, `danmu_status`, `danmu_platforms`, `danmu_ai_config`, `danmu_ai_test`, `danmu_reset`, `danmu_help`, `danmu_match_help`, `danmu_ai_help` | ID 已取证；协议待追 |
| 8 | 迅雷 | `xunlei_status`, `xunlei_login`, `xunlei_thread`, `xunlei_clean` | ID 已取证；协议待追 |
| 9 | 115 | `pan115_status`, `pan115_login`, `pan115_magnet_switch`, `magnet_cloud_help`, `pan115_clean` | ID 已取证；协议待追 |
| 10 | 控制台 | `config_health`, `view_mode`, `config_accounts`, `config_performance`, `config_strategy`, `scan_config`, `config_backup`, `cloud_backup`, `webdav_backup`, `proxy_config`, `thread_config`, `quality_order`, `quality_manage`, `go_version`, `history_sync` 等 | ID 已取证；分派待逐项追 |
| 11 | 123 | `pan123_status`, `pan123_login`, `pan123_community_cookie`, `pan123_thread`, `pan123_clean` | ID 已取证；协议待追 |
| 12 | 光鸭 | `guangya_status`, `guangya_login`, `guangya_community_cookie`, `guangya_magnet_switch`, `magnet_cloud_help`, `guangya_clean` | 登录与播放主链已取证，见下表 |
| 13 | B站 | `bili_status`, `bili_login`, `bili_switch_mode`, `bili_playback_manage`, `bili_category_manage`, `bili_personal_manage`, `bili_reset_manage`, `bili_help`, `bili_clean`；handler 另接受 `bili_low_end`, `bili_logout`, `bili_personal_visibility`, `bili_history_sync`, `bili_personal_sort`, `bili_personal_reset` | ID 与分派已取证；handler 协议待逐项追 |
| 14 | 移动 | `yidong_status`, `yidong_login`, `yidong_clean` | ID 已取证；协议待追 |
| 15 | 海报 | `PianDan.posterSettingVods()` 动态生成 | 动态入口已取证；条目待运行/静态追踪 |
| 16 | 媒体库 | `fishdrive_display_manage`, `fishdrive_media_maintenance`, `fishdrive_server_settings`, `fishdrive_emby_settings`, `fishdrive_help`, `fishdrive_network_acceleration` | ID 与分派已取证；handler 协议待逐项追 |

来源：`FishConfig.java:93-800`（action 分派）、`:810-1033`（栏目条目），`Bili.java:173-199, 268-401`，`FishDrive.java:840-875, 1430-1496`。

### Bili 动态分派映射

| action ID | Android Runnable 分支 | 当前状态 |
|---|---:|---|
| `bili_clean`, `bili_status` | `RunnableC0234b0(24)` | 分派已取证；具体副作用待追 |
| `bili_login` | `RunnableC0376c(..., 21)` | 分派已取证；登录协议待追 |
| `bili_low_end` | `RunnableC0376c(..., 2)` | 分派已取证 |
| `bili_category_manage` | `RunnableC0376c(..., 4)` | 分派已取证 |
| `bili_switch_mode` | `RunnableC0376c(..., 0)` | 分派已取证 |
| `bili_personal_manage` | `RunnableC0376c(..., 5)` | 分派已取证 |
| `bili_logout` | `RunnableC0234b0(26)` | 分派已取证；与 clean 语义区别待追 |
| `bili_personal_visibility` | `RunnableC0376c(..., 18)` | 分派已取证 |
| `bili_history_sync` | `RunnableC0376c(..., 3)` | 分派已取证 |
| `bili_playback_manage` | `RunnableC0376c(..., 1)` | 分派已取证 |
| `bili_personal_sort` | `RunnableC0376c(..., 19)` | 分派已取证 |
| `bili_reset_manage` | `RunnableC0376c(..., 17)` | 分派已取证 |
| `bili_help` | `RunnableC0234b0(25)` | 分派已取证 |
| `bili_personal_reset` | `RunnableC0376c(..., 20)` | 分派已取证 |

### FishDrive 动态分派映射

| action ID | Android Runnable 分支 | 当前状态 |
|---|---:|---|
| `fishdrive_media_maintenance` | `RunnableC0387n(..., 4)`：刷新媒体库、清除缓存 | 分派与菜单语义已取证 |
| `fishdrive_server_settings` | `RunnableC0387n(..., 1)`：添加/管理/删除/启用服务器、Emby 登录与安全 | 分派与菜单语义已取证 |
| `fishdrive_emby_settings` | `RunnableC0387n(..., 2)`：我的 Emby、内容与搜索 | 分派与菜单语义已取证 |
| `fishdrive_help` | `RunnableC0382i(14)` | 分派已取证 |
| `fishdrive_display_manage` | `RunnableC0387n(..., 3)`：分类显示、服务器/分类排序 | 分派与菜单语义已取证 |
| `fishdrive_network_acceleration` | `com.github.catvod.spider.b(..., 2)` | 分派已取证 |

## 3. 光鸭扫码与凭据闭环证据

| 阶段 | action/方法 | 端点与请求 | 成功条件 | 保存/输出 | 状态 |
|---|---|---|---|---|---|
| 创建二维码 | `guangya_login` → `C0192G.action` → `RunnableC0186D(0)` | `POST https://account.guangyapan.com/v1/auth/device/code`; JSON：`scope=user`, `client_id=aMe-8VSlkrbQXpUR` | `device_code` 与 `verification_uri_complete`（后备 `verification_uri`）非空 | 二维码内容为 verification URI | **已取证、已采样、已独立复现**（2026-03-13）；未轮询/未授权 |
| 轮询 | `RunnableC0186D` → `Q(deviceCode)` | 每 3 秒 `POST /v1/auth/token`; `grant_type=urn:ietf:params:oauth:grant-type:device_code`, `device_code`, `client_id`；总时限 180 秒 | response 无 `error`，且 `data.access_token` 或根 `access_token` 非空 | `c(response)` → `Y()` → `d0()` | 已取证；pending/成功已有测试样本；完整授权待真实扫码复现 |
| 更新凭据 | `c(JSONObject)` | 无网络；兼容根/`data`、snake/camel key | 非空字段优先，缺失字段保留旧值 | `access_token`, `refresh_token`, `token_type`, `sub`, `phone`, `kaiser_folder` | 已取证 |
| 刷新 | `V()` | `POST /v1/auth/token`; `grant_type=refresh_token`, `refresh_token`, `client_id` | HTTP < 400、无 `error`、更新后 access token 非空 | `c(response)` → `Y()` | 已取证；未采样/未复现 |
| 用户状态 | `d0()` | `GET https://account.guangyapan.com/v1/user/me`; Header `Authorization: <token_type|Bearer> <access_token>` | HTTP < 400 且 body 非空 | 合并 `sub`, `name|nickname`, `picture|avatar`, `phone_number|phone` 后 `Y()` | 已取证；未采样/未复现 |
| 持久化 | `Y()` | Android `C0109g1.g("guangya", json)` | 写入无异常 | 8 字段：access/refresh/token_type/sub/name/picture/phone/kaiser_folder | 已取证；iOS 只能以 Keychain 替代此层，JSON 语义不得改 |
| 业务读取 | `I()`, `A()`, `j()`, `T()` | `I()` 读取 `guangya`; `T(auth=true)` 缺 access 时先 `V()`；API Header 使用 `d()` | 有 access 或 refresh；需要业务请求时 refresh 成功 | Spider 请求读取同一凭据 | 已取证；iOS 未接 |
| 退出 | `e()` / `guangya_clean` | 无远端 revoke 证据 | 内存字段、缓存列表清空 | `C0109g1.a("guangya")` 删除本地凭据 | 已取证；iOS Keychain 删除仅对应存储层 |

关键来源：`RunnableC0186D.java:24-67`；`C0192G.java:592-605, 666-687, 701-728, 805-824, 921-1001, 1071-1124, 1264-1281`。

### 动态 JSON 规则

Android 的 `c()`/`Y()`只持久化已知 8 字段，会丢未知字段；iOS 项目约束更严格：原始响应未知字段必须无损保留。后续实现应采用“原始 JSON 深合并 + 已知字段投影”，不能重新编码为仅含模型字段的 JSON。

## 4. 光鸭网盘业务/播放闭环证据

| 阶段 | 方法 | 端点/行为 | Header | 当前结论 |
|---|---|---|---|---|
| 分享访问令牌 | `u(I0)` | `/userres/v1/get_share_access_token`，404/400 后备 `/nd.bizuserres.s/v1/get_share_access_token` | 公共请求，无账号 Authorization | 已取证 |
| 分享枚举 | `G`, `H` | `/userres/v1/get_share_page_files_list`，分页 50；后备 nd 端点 | 分享 `accessToken` 在 JSON body | 已取证 |
| 我的文件枚举 | `F`, `E` | `/userres/v1/file/get_file_list`，分页 50；后备 nd 端点 | 账号 Authorization | 已取证 |
| 转存目录 | `X` | `/userres/v1/file/create_dir`，目录 `FishGuangYa` | 账号 Authorization | 已取证 |
| 转存 | `X` | `/userres/v1/restore_share`; body：share `accessToken`, `fileIds`, `parentId` | 账号 Authorization | 已取证 |
| 转存任务 | `e0` | `/userres/v1/get_task_status`; 最多 30 次、每次 1 秒 | 账号 Authorization | 已取证 |
| 我的文件播放 URL | `t` | `/userres/v1/get_res_download_url`; `fileId` | 账号 Authorization | 已取证 |
| 分享直链 | `v` | `/userres/v1/get_share_download_url`; `fileId`, share `accessToken` | 公共请求 | 已取证 |
| 播放策略 | `P`/`w` | 普通分享直接 `v()`；无限线路先 `X()` 转存再 `t()`，失败回退 `v()`；我的文件 `t()` | 返回播放器 Header 为桌面 UA + `Referer: https://www.guangyapan.com/` | 已取证 |
| 字幕 | 全库检索确认：`C0192G.java` 及光鸭播放链无 subtitle/caption/srt/ass/vtt 处理；播放 URL 接口只返回 URL 字段；Android 字幕由播放器层 `RefreshEvent.SUBTITLE + Sub.from(path)` 提供（`VideoActivity.java:1431`），不来自光鸭 spider 响应。结论：**光鸭协议无字幕字段，字幕属播放器层能力**（AVPlayer 原生支持 HLS 内嵌字幕），不阻塞网盘播放闭环 | 已取证 | 已取证 | 已确认：协议无字幕，播放器层处理 |

关键来源：`C0192G.java:358-532, 610-664, 839-919, 1128-1150, 1438-1504`。

## 5. 后续顺序（不可跳步）

1. 解码 `FishDrive`、`Bili` 动态 action，并追到实际 handler。
2. 对每个账号建立同格式表：创建/二维码/轮询/成功条件/保存字段/刷新/退出/业务读取。
3. 光鸭独立复现器 `Tools/reproduce_guangya_protocol.py` 已用 fixture 验证请求体、成功判定、JSON 无损深合并及播放 URL 兼容字段；`create-device` 已真实创建 device code。下一步采样 pending；成功扫码仍需用户授权。
4. 再复现分享解析、枚举、转存、任务轮询、播放 URL、Header。字幕已取证：光鸭协议无字幕字段，字幕由播放器层处理，不阻塞网盘闭环。
5. 证据与独立复现通过后才接 Swift 业务；全功能完成前不跑阶段 CI、不打 IPA。
