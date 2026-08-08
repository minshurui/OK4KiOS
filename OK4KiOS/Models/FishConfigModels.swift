import Foundation

enum FishConfigSection: String, CaseIterable, Identifiable, Sendable {
    case console = "10"
    case system = "5"
    case poster = "15"
    case danmaku = "7"
    case media = "16"
    case bili = "13"
    case quark = "1"
    case uc = "2"
    case tianyi = "3"
    case yidong = "14"
    case baidu = "6"
    case xunlei = "8"
    case pan123 = "11"
    case pan115 = "9"
    case guangya = "12"
    case ali = "4"

    var id: String { rawValue }

    /// PROTOCOL.md 第 2 节：10 个网盘栏目对应的 driveKey（action 前缀）。
    /// 其余栏目（控制台/系统/海报/弹幕/媒体库/B站）不是网盘入口。
    var driveKey: String? {
        switch self {
        case .quark: return "quark"
        case .uc: return "uc"
        case .tianyi: return "tianyi"
        case .yidong: return "yidong"
        case .baidu: return "baidu"
        case .xunlei: return "xunlei"
        case .pan123: return "pan123"
        case .pan115: return "pan115"
        case .guangya: return "guangya"
        case .ali: return "ali"
        default: return nil
        }
    }

    var isDriveSection: Bool { driveKey != nil }
    var title: String {
        switch self {
        case .console: return "控制台"
        case .system: return "系统设置"
        case .poster: return "智能海报墙"
        case .danmaku: return "弹幕配置"
        case .media: return "媒体库设置"
        case .bili: return "B站设置"
        case .quark: return "夸克网盘"
        case .uc: return "UC网盘"
        case .tianyi: return "天翼云盘"
        case .yidong: return "移动云盘"
        case .baidu: return "百度网盘"
        case .xunlei: return "迅雷网盘"
        case .pan123: return "123网盘"
        case .pan115: return "115网盘"
        case .guangya: return "光鸭网盘"
        case .ali: return "阿里云盘"
        }
    }
}

struct FishConfigAction: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
}

/// action 的分派类别：扫码/状态/线程/清理/其它。
/// 依据 Android FishConfig 各栏目 action 命名约定（PROTOCOL.md 第 2 节）。
enum FishConfigActionKind: Equatable, Sendable {
    case status
    case scanLogin
    case thread
    case clean
    case other
}

extension String {
    /// 按 action id 后缀判定分派类别（对 FishConfigAction 与网关均可用）。
    var fishConfigActionKind: FishConfigActionKind {
        if hasSuffix("_status") { return .status }
        if hasSuffix("_scan") || hasSuffix("_login") { return .scanLogin }
        if hasSuffix("_thread") { return .thread }
        if hasSuffix("_clean") { return .clean }
        return .other
    }
}

extension FishConfigAction {
    var kind: FishConfigActionKind { id.fishConfigActionKind }
}

enum FishConfigCatalog {
    static func actions(for section: FishConfigSection) -> [FishConfigAction] {
        switch section {
        case .quark: return drive("quark", login: ("quark_scan", "使用夸克App扫码"))
        case .uc:
            return [
                .init(id: "uc_status", title: "账号状态", detail: "查看账号和会员状态"),
                .init(id: "uc_scan", title: "扫码登录", detail: "使用UC网盘App扫码"),
                .init(id: "uc_thread", title: "下载线程", detail: "选择普通或会员下载线程"),
                .init(id: "uc_token_scan", title: "智能画质授权", detail: "扫码完成Token授权"),
                .init(id: "uc_clean", title: "清除登录", detail: "删除UC账号凭据")
            ]
        case .tianyi: return drive("tianyi", login: ("tianyi_login", "使用天翼云盘App扫码")) + [.init(id: "tianyi_help", title: "登录帮助", detail: "查看常见问题解决方案")]
        case .yidong:
            return [
                .init(id: "yidong_status", title: "账号状态", detail: "查看移动云盘账号状态"),
                .init(id: "yidong_login", title: "账号登录", detail: "App扫码 / 账号密码 / Authorization"),
                .init(id: "yidong_clean", title: "清除登录", detail: "删除移动云盘账号凭据")
            ]
        case .ali:
            return [
                .init(id: "ali_status", title: "账号状态", detail: "查看阿里云盘账号状态"),
                .init(id: "ali_scan", title: "扫码登录", detail: "使用阿里云盘App扫码"),
                .init(id: "ali_token", title: "Token登录", detail: "输入RefreshToken"),
                .init(id: "ali_thread", title: "下载线程", detail: "调整阿里云盘下载线程"),
                .init(id: "ali_clean", title: "清除登录", detail: "删除阿里云盘账号凭据")
            ]
        case .baidu: return drive("baidu", login: ("baidu_scan", "扫码或输入Cookie"))
        case .xunlei: return drive("xunlei", login: ("xunlei_login", "使用迅雷App扫码"))
        case .pan115:
            return [
                .init(id: "pan115_status", title: "账号状态", detail: "查看115账号状态"),
                .init(id: "pan115_login", title: "扫码登录", detail: "使用115App扫码"),
                .init(id: "pan115_magnet_switch", title: "磁力云下载接管", detail: "由115接管磁力任务"),
                .init(id: "magnet_cloud_help", title: "磁力云下载帮助", detail: "风险说明、使用步骤、状态查看"),
                .init(id: "pan115_clean", title: "清除登录", detail: "删除115账号凭据")
            ]
        case .pan123:
            return [
                .init(id: "pan123_status", title: "账号状态", detail: "查看123网盘账号状态"),
                .init(id: "pan123_login", title: "账号密码登录", detail: "扫码、账号密码或Open Token授权"),
                .init(id: "pan123_community_cookie", title: "123社区Cookie", detail: "社区站点登录凭据"),
                .init(id: "pan123_thread", title: "下载线程", detail: "调整123网盘下载线程"),
                .init(id: "pan123_clean", title: "清除登录", detail: "删除123网盘账号凭据")
            ]
        case .guangya:
            return [
                .init(id: "guangya_status", title: "账号状态", detail: "查看光鸭账号状态"),
                .init(id: "guangya_login", title: "扫码登录", detail: "使用光鸭网页授权扫码"),
                .init(id: "guangya_community_cookie", title: "光鸭社区Cookie", detail: "社区站点登录凭据"),
                .init(id: "guangya_magnet_switch", title: "磁力云下载接管", detail: "由光鸭接管磁力任务"),
                .init(id: "magnet_cloud_help", title: "磁力云下载帮助", detail: "使用步骤、状态查看、播放说明"),
                .init(id: "guangya_clean", title: "清除登录", detail: "删除光鸭账号凭据")
            ]
        case .console:
            return [
                .init(id: "config_health", title: "配置检查", detail: "检查账号和关键配置"),
                .init(id: "view_mode", title: "模式切换", detail: "切换设置中心展示模式"),
                .init(id: "config_accounts", title: "账号总览", detail: "查看全部账号状态"),
                .init(id: "config_performance", title: "性能加速", detail: "代理与下载线程"),
                .init(id: "config_strategy", title: "播放策略", detail: "网盘与画质优先级"),
                .init(id: "scan_config", title: "登录导入", detail: "账号登录与备份导入"),
                .init(id: "cloud_backup", title: "云端备份", detail: "备份或恢复应用设置")
            ]
        case .system:
            return [
                .init(id: "home_menu_manage", title: "主页管理", detail: "管理主页栏目"),
                .init(id: "backup_mode", title: "备份方式", detail: "选择备份存储"),
                .init(id: "settings_menu_manage", title: "设置管理", detail: "管理设置菜单"),
                .init(id: "config_performance", title: "性能设置", detail: "代理、版本与下载线程"),
                .init(id: "magnet_config", title: "磁力管理", detail: "磁力云下载和自动清理"),
                .init(id: "quality_config", title: "播放源管理", detail: "排序与开关"),
                .init(id: "config_clear", title: "清理配置", detail: "清除全部配置需二次确认")
            ]
        case .danmaku:
            return [
                .init(id: "danmu_toggle", title: "弹幕开关", detail: "启用或关闭弹幕"),
                .init(id: "danmu_status", title: "功能配置", detail: "管理服务和配置"),
                .init(id: "danmu_platforms", title: "弹幕源开关", detail: "管理弹幕平台"),
                .init(id: "danmu_ai_config", title: "AI匹配", detail: "配置AI匹配"),
                .init(id: "danmu_ai_test", title: "AI测试", detail: "测试AI匹配效果"),
                .init(id: "danmu_reset", title: "恢复默认", detail: "重置弹幕配置")
            ]
        case .poster, .media, .bili: return []
        }
    }

    private static func drive(_ key: String, login: (String, String), status: String? = nil) -> [FishConfigAction] {
        [
            .init(id: status ?? "\(key)_status", title: "账号状态", detail: "查看账号状态"),
            .init(id: login.0, title: "扫码登录", detail: login.1),
            .init(id: "\(key)_thread", title: "下载线程", detail: "调整下载线程"),
            .init(id: "\(key)_clean", title: "清除登录", detail: "删除账号凭据")
        ]
    }
}
