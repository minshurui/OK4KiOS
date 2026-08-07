# GoSpider — iOS 原生 Go 蜘蛛引擎

用 Go 实现 TVBox Spider/规则引擎，编译为 **c-archive 静态库** 嵌入 iOS（iPhone/iPad），
由 Swift 通过 C API 调用。纯 Go 无平台绑定，Linux 可完整开发 + `go test`，
macOS runner 上交叉编译 `GOOS=ios` 得到 `.a`。

## 为什么用 Go

| 需求 | Go 方案 |
|------|---------|
| JS 签名脚本（加密 Spider） | `github.com/dop251/goja` 纯 Go JS 引擎，直接执行 Spider 脚本 |
| 加密解密（FishGuard 算法） | `crypto/*` 覆盖 AES/DES/MD5/SHA/RC4 |
| HTML 解析（Wogg 等明文站） | `golang.org/x/net/html` |
| type 4 规则引擎 | `pkg/rules`（迷你 XPath/JSONPath/URL 模板） |
| 开发闭环 | Linux `go test` 秒级验证，不占 iOS CI |

## 模块结构

```
cmd/ok4kspider/bridge.go   C API 导出（c-archive 入口）
pkg/rules/                 迷你 XPath + JSONPath + URL 模板
pkg/engine/                type 4 规则引擎（HTML/JSON 双模式）+ goja JS
pkg/sites/wogg/            Wogg 站点规则 + 真实 HTML fixture 测试
```

## 构建

```bash
# Linux/macOS 通用（纯 Go 验证）
go test ./...

# iOS c-archive（macOS + Xcode）
cd cmd/ok4kspider
GOOS=ios GOARCH=arm64 CGO_ENABLED=1 \
  CC="$(xcrun --sdk iphoneos --find clang)" \
  SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)" \
  go build -buildmode=c-archive -o libok4kspider.a

# Linux 本地 C 冒烟（验证桥接）
go build -buildmode=c-archive -o /tmp/libok4kspider.a ./cmd/ok4kspider
gcc bridge_test.c /tmp/libok4kspider.a -lpthread -lm
```

## C API

| 函数 | 说明 |
|------|------|
| `ok4k_version()` | 引擎版本 |
| `ok4k_home(siteJSON)` | 首页条目 |
| `ok4k_category(siteJSON)` | 分类（params.cateId/pg） |
| `ok4k_search(siteJSON)` | 搜索（params.wd/pg） |
| `ok4k_detail(siteJSON)` | 详情（params.id）→ 线路+播放列表 |
| `ok4k_play(siteJSON)` | 播放（params.flag/id）→ 可播放 URL |
| `ok4k_js_sign(script,url,paramsJSON)` | 执行 JS 签名脚本 |
| `ok4k_free(p)` | 释放 C 字符串 |

`siteJSON` 格式：

```json
{
  "site": "wogg",            // 内置站点名，或
  "rule": { "host": "...", "home": {...}, ... },  // type 4 完整规则
  "host": "https://...",
  "params": { "cateId": "1", "pg": "2", "wd": "...", "id": "...", "flag": "..." }
}
```

## 状态

- [x] 规则引擎（XPath 子集/JSONPath/模板/goja）
- [x] Wogg 真实站点提取（120 条唯一）
- [x] C 桥接冒烟（Linux）
- [x] iOS c-archive 构建流程（GitHub Actions macOS）
- [ ] Swift 分派接入（VodServiceFactory）
- [ ] 加密 Spider 逐站移植（FishGuard 算法 → Go crypto）
- [ ] type 4 规则 JSON 解析进引擎
