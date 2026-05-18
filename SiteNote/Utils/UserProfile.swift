//
//  UserProfile.swift
//  SiteNote
//
//  用户角色 Profile (Site Team / Engineer)。
//  v1.6 改名:`pm` → `siteTeam`(适用面更广 — 不只项目经理,也包括工长 / Builder / Foreman / 业主代表)。
//  内核一致(speech → AI → SwiftData → PDF),按 Profile 切换的是:
//    - 主屏分组(RecordView 显示哪些 sections)
//    - 默认 PDF 模板(巡检报告)
//    - Settings 显示哪些复杂功能
//
//  Profile 可在 Settings 随时切换,所有 UI 通过 @Observable 自动更新。
//  Onboarding 第 2 步让新用户选;老用户(已 dismiss onboarding)默认 Site Team 向后兼容。
//
//  UserDefaults 兼容:老用户存的 rawValue 是 "pm"(v1.5 之前),启动时 migrate 到 "siteTeam"。
//

import Foundation
import Observation

enum ProfileKind: String, Codable, CaseIterable, Identifiable {
    /// Site Team — 工地组长 / 工长 / Builder / Foreman / 业主代表 / 项目经理。
    /// rawValue "siteTeam"(v1.6+);老用户的 "pm" rawValue 在 UserProfileManager.init 里被 migrate 过来。
    case siteTeam
    /// Engineer — 工程师 / Inspector / Consultant。
    case engineer

    var id: String { rawValue }

    /// UI 显示名。
    var displayName: String {
        switch self {
        case .siteTeam: return String(localized: "工地小组", locale: AppLanguageManager.currentLocale)
        case .engineer: return String(localized: "工程师", locale: AppLanguageManager.currentLocale)
        }
    }

    /// 一句话副标题(角色卡片用)。
    var subtitle: String {
        switch self {
        case .siteTeam: return String(localized: "工长 / Builder / Foreman / PM", locale: AppLanguageManager.currentLocale)
        case .engineer: return String(localized: "Inspector", locale: AppLanguageManager.currentLocale)
        }
    }

    /// 长描述(onboarding 选择时显示)。
    var description: String {
        switch self {
        case .siteTeam:
            return String(localized: "工地速记 + 团队协作,导出 PDF 工地日志。", locale: AppLanguageManager.currentLocale)
        case .engineer:
            return String(localized: "做巡检/检验:专注问题与合规,导出标准 inspection report,可附图纸。", locale: AppLanguageManager.currentLocale)
        }
    }

    /// SF Symbol 图标。
    var sfSymbol: String {
        switch self {
        case .siteTeam: return "checklist"
        case .engineer: return "doc.text.magnifyingglass"
        }
    }

    /// 主题色名(配合 Ink palette;实际颜色在 view 里映射)。
    var themeColorName: String {
        switch self {
        case .siteTeam: return "orange"
        case .engineer: return "blue"
        }
    }
}

/// 全局单例,@Observable 自动驱动 UI 更新。
@Observable
final class UserProfileManager {
    static let shared = UserProfileManager()

    /// 当前角色。改变时自动写盘 + 通知所有读它的 view 重画。
    var current: ProfileKind {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: Self.key)
        }
    }

    /// 用户的真名(例 "Sam")— 巡检报告默认填这个作 engineerName / 签字。
    /// 空 = 用户还没设过。@Observable 自动驱动设置 UI 与新建报告链路。
    var userDisplayName: String {
        didSet {
            UserDefaults.standard.set(userDisplayName, forKey: Self.nameKey)
            // **关键**:改名时清掉所有 `team.selfPushed.<teamID>.<oldDisplayName>` flag,
            // 否则 ensureSelfMemberRecord 会判定"已推过"跳过 push → 团队成员永远看到老名字。
            let defaults = UserDefaults.standard
            let prefix = "team.selfPushed."
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// 用户是否已显式选过角色(onboarding 完成 OR Settings 改过)。
    /// 用来区分"老用户默认 Site Team"和"新用户主动选了 Site Team"。
    var hasExplicitlySelected: Bool {
        UserDefaults.standard.bool(forKey: Self.selectedFlagKey)
    }

    private static let key = "settings.userProfile"
    private static let selectedFlagKey = "settings.userProfile.selected"
    private static let nameKey = "settings.userProfile.displayName"

    private init() {
        // v1.6 migration:老用户 UserDefaults 存的是 "pm",改名后视为 "siteTeam"。
        // 写回新 rawValue 让以后读到统一,不用每次 init 跑 migration。
        let rawStored = UserDefaults.standard.string(forKey: Self.key)
        let migratedRaw: String
        if let rawStored, rawStored == "pm" {
            migratedRaw = ProfileKind.siteTeam.rawValue
            UserDefaults.standard.set(migratedRaw, forKey: Self.key)
        } else {
            migratedRaw = rawStored ?? ProfileKind.siteTeam.rawValue
        }
        self.current = ProfileKind(rawValue: migratedRaw) ?? .siteTeam
        self.userDisplayName = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
    }

    /// Onboarding / Settings 选择时调用。设 current + 标记已选过。
    func select(_ kind: ProfileKind) {
        current = kind
        UserDefaults.standard.set(true, forKey: Self.selectedFlagKey)
    }
}
