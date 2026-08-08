# FishDriveService 协议契约（worker 必须严格遵守，禁止臆造 API）

## 核心协议（OK4KiOS/Network/FishDriveService.swift 已定义，worker 只实现，不改协议）

```swift
protocol FishDriveService: Sendable {
    var driveKey: String { get }            // "quark"/"uc"/"tianyi"/"ali"/"baidu"/"xunlei"/"pan115"/"pan123"/"guangya"/"yidong"
    var displayName: String { get }
    var supportsScanLogin: Bool { get }
    var protocolEvidence: String { get }     // 注明取证来源，不得宣称"完整"除非真完整
    var threadOptions: [FishThreadOption] { get }

    func status() async throws -> FishDriveStatus
    func beginLogin() async throws -> FishScanSession     // 扫码/设备码创建
    func poll(_ session: FishScanSession) async throws -> FishScanResult
    func refresh() async throws
    func logout() async throws
    func currentThread() -> String
    func setThread(_ id: String)
}
```

## 关联类型（已定义，直接用）

```swift
enum FishScanResult: Equatable, Sendable {
    case pending
    case authorized
    // 没有其他 case！禁止构造 FishScanResult(success:pending:...)
}

enum FishDriveError: LocalizedError, Equatable {
    case protocolPending(String)   // 协议未取证/未完成时诚实抛错
    case notLoggedIn
    case invalidResponse
    case server(String)
}

struct FishScanSession: Equatable, Sendable {
    let qrPayload: String          // 二维码内容（图片 URL 或内容）
    let deviceCode: String         // 轮询会话标识（可打包多参数用 | 分隔）
    let expiresIn: TimeInterval
    let interval: TimeInterval
    let openURL: URL?
}

struct FishDriveStatus: Equatable, Sendable {
    enum State: Equatable, Sendable { case loggedIn, notLoggedIn, stale }
    let state: State
    let detail: String
    let displayName: String?
    static func notLoggedIn(_ detail: String) -> FishDriveStatus
}

protocol FishCredentialStore: Sendable {
    func data(for key: String) throws -> Data?
    func set(_ data: Data, for key: String) throws
    func remove(_ key: String) throws
}
// MemoryCredentialStore（测试）在 Tests/FishDriveServiceTests.swift（internal，非 private）
```

## 持久化规范
- 每网盘一个 Keychain key = driveKey（如 "baidu"/"tianyi"），经 `FishCredentialStore` 注入
- 动态 JSON 无损保留未知字段：深合并 + 已知字段投影（参考 GuangyaCredential.init）
- Session/actor 模式：`actor XxxSession { init(store: FishCredentialStore = FishSecureStore.shared, service: XxxAuthService = ...) }`

## HTTP 注入规范（可测）
- 每网盘定义 `protocol XxxHTTPClientProtocol { func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) }`
- wrapper：`struct XxxHTTPClient: XxxHTTPClientProtocol`（用 URLSession.shared.dataTask + withCheckedThrowingContinuation，
  禁止 `URLSession` extension 或 `session.data(for:)` 默认参数——有歧义）
- Service 注入：`init(client: XxxHTTPClientProtocol = XxxHTTPClient())`

## 测试规范
- 测试用 `XxxMockHTTPClient`（class，`final class`，非 mutating struct——协议方法非 mutating）
- mock 需要 header 时加 `var responseHeaders: [String: String]`
- 生命周期用例：beginLogin → poll(pending) → poll(authorized) → store 有凭据 → refresh → logout 删凭据
- 状态比较：`XCTAssertEqual(status.state, FishDriveStatus.State.loggedIn)`（禁止裸 `.loggedIn`）

## 已知错误（别踩）
- `nonempty` 扩展在 GuangyaAuthService.swift（internal，全 module 可见）——不要再定义第二个
- `XxxSession` 只能定义一次（在 XxxSession.swift）；DriveService 文件里禁止再写
- `FishScanResult`/`FishDriveError`/`FishCredential`（不存在这个类型！）禁止构造
- 扫码轮询 pending 判定按各网盘真实响应（error=authorization_pending / result 码 / status 码），
  证据不足诚实 `FishDriveError.protocolPending`
