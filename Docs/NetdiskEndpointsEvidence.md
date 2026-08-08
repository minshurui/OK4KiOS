# csp_FishConfig 设置中心 → OK4K iOS 原生移植 — 协议汇总

> 生成：W1(jar 逆向) + W2(Android) + W3(iOS) 并行取证汇总。状态标记：已取证=源码定位；已采样=真实网络请求；已复现=独立脚本跑通；已实现=iOS 代码落地。

## 1. 入口与分派（已取证）

- 站点：`{"key":"FishConfig","name":"🍼┆设置┆中心","type":3,"api":"csp_FishConfig"}`
- Android `FishConfig.action(str)` 分派顺序（FishConfig.java:112-115）：
  1. `L1.a0(str)`（预注册 action）
  2. `Bili.dispatchConfigAction(str)`
  3. `FishDrive.dispatchConfigAction(str)`
  4. 本地混淆 switch（16 栏目 action）
- iOS 已识别 FishConfig 特殊站点：`SiteModels.swift:57-58`（key/api 匹配），`canRunNatively` 判定在 :60。

## 2. 栏目与 action 全表（已取证，FishConfig 本地 switch 解码）

| 栏目 | action | 处理 |
|---|---|---|
| 夸克 | quark_status→RunnableC0234b0(27); quark_scan→RunnableC0234b0(6); quark_thread→RunnableC0380g(9); quark_clean→RunnableC0380g(20)→RunnableC0382i(8)→C0244g0.n().d() | 核心类 C0244g0（2089 行，42 处未反编译） |
| UC | uc_status→RunnableC0381h(11); uc_scan→RunnableC0381h(14); uc_token_scan→RunnableC0381h(29); uc_thread→RunnableC0381h(26); uc_clean→RunnableC0382i(0)→(3)→C0185C0.n().d() | 核心类 C0185C0（2362 行） |
| 天翼 | tianyi_status→RunnableC0382i(2); tianyi_login→RunnableC0380g(6)→L1.l1(); tianyi_thread→RunnableC0380g(17); tianyi_clean→RunnableC0380g(28)→RunnableC0382i(7)→C0268s0.q().h() | 核心类 C0278x0 |
| 阿里 | ali_status→RunnableC0380g(0); ali_scan→RunnableC0380g(1)→L1.G0(); ali_token→case 'G'; ali_thread→RunnableC0380g(2); ali_clean→RunnableC0379f(12) | 核心类 C0239e |
| 百度 | baidu_status→RunnableC0382i(12); baidu_scan→RunnableC0382i(13)→L1.H0(); baidu_thread→RunnableC0234b0(7); baidu_clean→RunnableC0379f(0) | 核心类 C0243g |
| 迅雷 | xunlei_status→RunnableC0380g(3); xunlei_login→RunnableC0380g(4)→L1.p1(); xunlei_thread→RunnableC0380g(4)→L1.p1(); xunlei_clean→RunnableC0382i(11)→C0203L0.v() | 核心类 C0203L0（2277 行） |
| 115 | pan115_status→RunnableC0380g(8); pan115_login→(W0)→L1.W0(); pan115_magnet_switch→RunnableC0380g(11); pan115_clean→RunnableC0380g(13)→RunnableC0382i(6)→C0210P.y() | 核心类 C0210P（5013 行） |
| 123 | pan123_status→RunnableC0380g(14); pan123_thread→RunnableC0380g(16); pan123_community_cookie→RunnableC0380g(15)→L1.X0(); pan123_login→(l1 中 p1 相关)；pan123_clean→RunnableC0382i(5)→C0223W.r | 核心类 C0223W（1761 行） |
| 光鸭 | guangya_status→RunnableC0380g(19); guangya_login→RunnableC0380g(21)→L1.R0(); guangya_community_cookie→RunnableC0380g(22)→L1.Q0(); guangya_magnet_switch; guangya_clean→RunnableC0382i(4)→C0192G.q.e() | **完整已取证+已复现+已实现(iOS)** |
| 移动 | yidong_status→RunnableC0381h(20); yidong_login→RunnableC0382i(1)→L1.r1(); yidong_clean→RunnableC0382i(10)→C0218T0.u().c() | 核心类 C0218T0（1500 行） |

## 3. 登录方式总表（已取证，L1.java）

| 网盘 | 登录方式 | 入口 |
|---|---|---|
| 阿里 | Token 输入 | L1.G0() → Z0(...,"Token",...) |
| 百度 | 扫码(K2(17)) / 手动Cookie | L1.H0() → T0(...,"baidu",...) |
| 光鸭 | 扫码(F2(13)) / 手动Token(F2(15)) | L1.R0() → C0192G.q.A() |
| 115 | Cookie 输入 | L1.W0() → Z0(...,"Cookie",...) |
| 123 | 扫码授权(F2(18)) / 账号密码(F2(19)) / Open Token(F2(20)) | L1 123 分支 → RunnableC0241f |
| 天翼 | 扫码(F2(27)) / 账号密码(K2(7)) / 短信(K2(16)) | L1.l1() → C0278x0.f().s() |
| 迅雷 | 扫码(K2(10)) / Token JSON(K2(11)) | L1.p1() → C0203L0.v().H() |
| 移动 | App扫码(K2(23)) / 账号密码(K2(24)) / 导入凭证(K2(25)) | L1.r1() → C0218T0.F() |
| 夸克 | 扫码 | RunnableC0234b0(6) → C0244g0 |
| UC | 扫码/Token | RunnableC0381h(14)/(29) → C0185C0 |

## 4. 光鸭完整闭环（已取证 → 已采样 → 已复现 → 已实现 iOS）

- 设备码：`POST https://account.guangyapan.com/v1/auth/device/code`，body `{scope:user, client_id:aMe-8VSlkrbQXpUR}`；二维码=verification_uri_complete
- 轮询：`POST /v1/auth/token`，body `{grant_type:urn:ietf:params:oauth:grant-type:device_code, device_code, client_id}`；3s 间隔、180s 超时；`error=authorization_pending` 未完成
- 刷新：`POST /v1/auth/token`，body `{grant_type:refresh_token, refresh_token, client_id}`；响应缺字段继承旧凭据
- 资料：`GET https://account.guangyapan.com/v1/user/me`，Authorization Bearer
- 持久化字段：access_token、refresh_token、token_type、sub、name、picture、phone、kaiser_folder（Android C0109g1 "guangya"；iOS Keychain 替代）
- 业务（api.guangyapan.com，主/备端点 `nd.bizuserres.s` 前缀）：
  - 分享令牌 `/userres/v1/get_share_access_token`（404/400 回退备端点）
  - 分享枚举 `/userres/v1/get_share_page_files_list`；私有 `/userres/v1/file/get_file_list`（分页 50）
  - 建目录 `/userres/v1/file/create_dir`（FishGuangYa）；转存 `/userres/v1/restore_share`；任务 `/userres/v1/get_task_status`（30×1s）
  - 播放 URL `/userres/v1/get_res_download_url`（私有）/`get_share_download_url`（分享）；字段 signedURL/signedUrl/downloadUrl/downloadURL/url 兼容
  - 播放 Header：桌面 UA + `Referer: https://www.guangyapan.com/`
- 字幕：**全库检索无 subtitle 字段**；Android 字幕由播放器层 RefreshEvent.SUBTITLE + Sub.from(path) 提供，非 spider 返回 → 不阻塞闭环
- iOS 落地：GuangyaAuthService + GuangyaSession(Keychain) + GuangyaDriveService，测试 4 个用例；**成功扫码样本仍缺（需用户真机扫码）**

## 5. 其余网盘卡点（重要）

- 8 个核心类（C0244g0/C0185C0/C0278x0/C0239e/C0203L0/C0210P/C0223W/C0218T0）均使用：
  - `f<id>short = new short[]{...}` + XOR 解码（已支持）
  - **moyu.fucking 字符串池**（C0040/C0043/C0044/C0050/C0053/C0070/C0075/C0086…）：`C00XX.n(id)` 单参=静态值、两参=字段、三参=方法，switch (K^var0) 分发
  - 已写池解析器 `Tools/decode_moyu_pools.py` → moyu_pools.json，验证：`C0050.n(8987)` = 解码方法 `a.青山依旧在夕阳.采菊东篱见南山(short[],off,key,len)→String`
  - **C0070.n(1412) 等返回 short[] 的 case 在 jadx 产物中缺失** → 需 baksmali 反汇编 classes.dex（jadx/baksmali 当前不可用，`apktool` 缺 jar）
  - 大量方法 "Method not decompiled"（<init>、B、P 等）→ 方法体只能从 smali 读取
- 结论：夸克/UC/天翼/阿里/百度/迅雷/115/123/移动 **协议取证未完成**，未到 iOS 实现阶段

## 6. 持久化（已取证）

- Android：`C0109g1.g/e/a(key)`（SharedPreferences 包装），key 包括 `guangya`、`pan123_open` 等；123 额外 C0223W.r 内存字段
- iOS：FishCredentialStore 抽象 + Keychain（FishSecureStore 实现）；约束：只替代存储层，不改变 Android 登录交互
- W2 确认 Android 端 JarLoader 从 `csp_` 前缀加载 jar 内 spider 类（`loadClass("com.github.catvod.spider." + api.split("csp_")[1])`）

## 7. iOS 现状（W3）

- 已有：FishConfigModels（16 栏目+action 目录）、FishConfigSectionView、ConfigService（FishConfig 站点识别）、GoSpider 桥（GoSpider/pkg/fishguard ext 解密）、光鸭三件套
- type 3 处理：`SiteModels.swift:60` 需要 nativeBaseURLs 非空才原生；FishConfig 被特判
- 播放参数（软解/硬解组：opensles/overlay-format/framedrop/soundtouch/start-on-prepared/http-detect-range-support/fflags/skip_loop_filter/reconnect/enable-accurate-seek/mediacodec 系列/dns_cache_timeout）**尚未在 iOS 播放器接入**（player.md 空）——FFmpegPlayerView/PlayerEngine 未看到 IJK 参数
- 设置中心完成前不跑阶段 CI、不打 IPA（约束）

## 8. 下一步（按序）

1. 安装 jadx 或 baksmali（`apt install jadx` / 下载 baksmali.jar），反汇编 classes.dex 补全字符串池缺失 case + 未反编译方法体
2. 补齐池解析：C0070.n(1412) 等 short[] 引用 → 解出 UC 等网盘协议（device code/扫码端点/保存字段/清除语义）
3. 逐网盘建光鸭同格式协议表（创建/二维码/轮询/成功/保存/刷新/退出/业务读取）
4. 光鸭成功扫码样本（需用户）→ refresh/profile 真实验证
5. 全部取证后：会话仓库统一凭据 → 各网盘服务 → FishConfigSectionView 全栏目 → 播放参数接入 → 统一 go test/Device/Simulator/IPA

---

## 9. 各网盘端点取证（2026-08-08 批量解码，smali short-array XOR 暴力 key 验证）

方法：baksmali 反汇编 classes.dex → 提取各核心类 `short` 数组 → 锚点扫描 + 穷举 16-bit key 解码。已确认与 jadx 明文调用点 (offset,key,len) 自洽。

### 夸克（g0.smali / C0244g0）
- 基址 `https://drive.quark.cn/1/clouddrive/`；账号 `https://pan.quark.cn/account/info?fr=pc&platform=pc`
- 扫码 `https://uop.quark.cn/cas/ajax/getTokenForQrcodeLogin`（getTokenForQrcodeLogin 机制同 UC）
- 分享详情 `.../share/sharepage/detail?pr=ucpro&fr=pc&uc_param_str=&pwd_id=`；分享 token `.../share/sharepage/token?__t=`
- 下载 token `https://drive-social-api.quark.cn/1/clouddrive/chat/conv/file/acquire_dl_token?pr=ucpro&fr=pc&sys=win32&ve=3.15.0`
- 转存 `.../chat/conv/msg/batch_send?...`；会员 `.../member?pr=ucpro&fr=pc&fetch_subscribe=true&_ch=home&fetch_identity=true`
- 下载 `https://drive-pc.quark.cn/1/clouddrive/file/download?pr=ucpro&fr=pc`；分享正则 `https://pan\.quark\.cn/s/([^\\|#/?]+)`

### UC（C0.smali / C0185C0）
- 基址 `https://pc-api.uc.cn/1/clouddrive/`；账号 `https://drive.uc.cn/account/info?fr=pc&platform=pc`
- 扫码 `https://api.open.uc.cn/cas/ajax/getTokenForQrcodeLogin?__dt=641254&__t=`
- 文件 info `.../file/info?pr=UCBrowser&fr=pc&fid=`；列表参数 `pdir_fid=0&_page=1&_size=200&_sort=file_type:asc,updated_at:desc&__t=`
- 分享 token `.../share/sharepage/token?pr=UCBrowser&fr=pc&uc_param_str=&__dt=&__t=`；下载 `.../file/download?pr=UCBrowser&fr=pc&sys=win32&ve=1.8.6&ut=`
- 任务 `task?pr=UCBrowser&fr=pc&uc_param_str=&task_id=`；会员 `.../member?pr=UCBrowser&fr=pc&fetch_subscribe=true&_ch=home`
- UA `uc-cloud-drive/1.8.7 Chrome/100.0.4896.160 Electron/18.3.5.16-b62cf9c50d Safari/537.36 Channel/ucpan_other_ch`
- 播放线路 uc_original/uc_unlimited/uc_smart；`broccoli.uc.cn`

### 阿里（e.smali / C0239e）
- API `https://api.aliyundrive.com/`；OAuth 授权 `https://open.aliyundrive.com/oauth/users/authorize?client_id=10e184c407cb4d8087f9d3b8f1fd2c23&redirect_uri=https://opentoken.xiaoya.pro/callback&scope=user:base,file:all:read,file:all:write&state=`
- Token `https://auth.aliyundrive.com/v2/account/token`；刷新 `auth.xiaoya.pro/api/ali_open/refresh`
- 播放预览 `.../adrive/v1.0/openFile/getVideoPreviewPlayInfo`；个人信息 `/v2/databox/get_personal_info`、`/v2/file/get`

### 115（P.smali / C0210P）
- 扫码 `https://passportapi.115.com/app/1.0/alipaymini/1.0/login/qrcode/`；轮询 token `https://qrcodeapi.115.com/api/1.0/alipaymini/1.0/token/`（备 codeapi）
- 存储 `https://115.com/index.php?ct=ajax&ac=get_storage_info`；文件 `http://web.api.115.com/files`、`https://my.115.com/?ct=ajax&ac=nav`
- 下载 `https://proapi.115.com/app/chrome/downurl?t=`、`/app/share/downurl?t=`；上传 `.../app/uploadinfo`
- 分享快照 `https://115cdn.com/webapi/share/snap`；分享 `https://115cdn.com/s/`；空间 `.../android/2.0/user/count_space_nums`、`/android/user/space_info`

### 123（W.smali / C0223W）
- OAuth 授权 `https://open-api.123pan.com/api/v1/oauth2/user/authorize`；登录 `https://api.123278.com/api/restful/goapi/v1/oauth2/user/login`
- litepan 中转 `https://oauth.litepan.top/api/oauth/start`、`/api/oauth/status/`、`/api/oauth/refresh`、`/api/oauth/confirm-received/`
- 用户 `/api/user/info`、`/api/user/sign_in`；分享 `/api/share/download/info`、`/api/v1/share/create`
- 分享正则 `https://((?:[\w-]+\.)?share\.123pan\.cn|123592\.com|123912\.com|123865\.com|123684\.com|123pan\.com|123pan\.cn|www\.123684\.com|...)/(?:s|123pan)/([^/\s?#]+)`

### 天翼（x0.smali / C0278x0）
- 基址 `https://api.cloud.189.cn`；批量 `/batch/createBatchTask.action`、`/batch/checkBatchTask.action`
- 家庭 `/family/file`、`/family/manage/getFamilyList.action?clientType=TELEPC&version=6.2&channelId=web_cloud.189.cn`
- 分享 `/api/open/share/`；播放 `.../api/portal/getNewVlcVideoPlayUrl.action?shareId=`
- 用户 `/api/portal/v2/getUserBriefInfo.action`、`/api/portal/getUserSizeInfo.action`

### 迅雷（L0.smali / C0203L0）
- API `https://api-pan.xunlei.com/drive/v1/`；auth `https://xluser-ssl.xunlei.com/v1/auth/token`
- 用户 `/v1/user/me`；文件 `/drive/v1/files?parent_id=`；转存 `/drive/v1/share/restore`；验证码 `/v1/shield/captcha/init`

### 移动（T0.smali / C0218T0）
- 基址 `https://user-njs.yun.139.com`、`https://personal-kd-njs.yun.139.com/hcy`、`https://share-kd-njs.yun.139.com/yun-share/richlifeApp/devapp/IOutLink/`
- 用户 `/user/getUser`、`/user/disk/quota/detail`、`/user/route/qryRoutePolicy`；列表 `/v1.2/queryContentList`
- 扫码 `https://yun.139.com/w/#/qrcLogin?sID=`；分享 `getOutLinkInfoV6`、`getContentInfoFromOutLink`、`dlFromOutLinkV3`
- 分享正则 `https://caiyun.139.com/w/i/([\w-]+)`、`https://caiyun\.139\.com/m/i\?([^&]+)`

## 10. 结论

- 9 网盘核心端点已取证（登录扫码/业务/播放/分享），覆盖 quark/uc/ali/baidu/xunlei/pan115/pan123/tianyi/yidong
- 登录**轮询与保存字段细节**仍需 smali 方法级分析（哪些响应字段持久化、轮询间隔、成功判定）
- 百度（g.smali 仅 242 行，C0243g 委托 W0/A 类）端点待补充
- 下一步：方法级 smali 分析登录流程（qr→poll→save），再接入 iOS

## 11. 调用点级补充（2026-08-08 decode_all_calls）

- 移动登录：`/portal/loginUrl.action?redirectURL=https://cloud.189.cn/web/redirect.html&returnURL=/main.action`（yidong D 方法，云盘网页跳转登录）
- 115 请求设备头：`adprovider/8.56.0.1134 netWorkType/WIFI appid/40 deviceName/Xiaomi_Mi 9 deviceModel/MI 9 ...`
- 迅雷桌面 UA：`Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) uc-cloud-drive/2...`
- 123 分享正则与夸克共享同一字符串池（quark 类 L99 命中 123 分享正则，跨类池引用）
- 方法级映射已建立：pan115 `l`=加密登录、`c0`=转存、`B`=HTTP 请求封装、`f`=文件；tianyi `l`=登录、`j`=请求；uc `p/r/w/X/d`=请求/文件/分享/转存；yidong `D/f`=请求/登录
