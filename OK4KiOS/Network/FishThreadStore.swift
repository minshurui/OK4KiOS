import Foundation

/// 下载线程偏好存储（普通/会员）。
/// Android 端是 SharedPreferences（C0109g1 包装）里的本地偏好，不涉及网盘协议；
/// iOS 以 UserDefaults 替代存储层，保持同样的本地语义。
final class FishThreadStore: @unchecked Sendable {
    static let shared = FishThreadStore()
    private let defaults: UserDefaults
    private let suite = "com.fongmi.ok4k.ios.fish.threads"

    init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else {
            self.defaults = UserDefaults(suiteName: suite) ?? .standard
        }
    }

    func value(for drive: String) -> String {
        defaults.string(forKey: key(drive)) ?? FishThreadOption.normal.id
    }

    func set(_ id: String, for drive: String) {
        defaults.set(id, forKey: key(drive))
    }

    func remove(_ drive: String) {
        defaults.removeObject(forKey: key(drive))
    }

    private func key(_ drive: String) -> String { "fish.thread.\(drive.lowercased())" }
}
