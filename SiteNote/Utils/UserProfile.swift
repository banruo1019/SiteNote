//
//  UserProfile.swift
//  SiteNote
//
//  用户角色 Profile (PM / Engineer)。
//  内核一致(speech → AI → SwiftData → PDF),按 Profile 切换的是:
//    - 主屏分组(RecordView 显示哪些 sections)
//    - AI prompt 重点(LogEntry 抽取关注什么)
//    - 默认 PDF 模板(施工日志 / 巡检报告)
//    - Settings 显示哪些复杂功能
//
//  Profile 可在 Settings 随时切换,所有 UI 通过 @Observable 自动更新。
//  Onboarding 第 2 步让新用户选;老用户(已 dismiss onboarding)默认 PM 向后兼容。
//

import Foundation
import Observation

enum ProfileKind: String, Codable, CaseIterable, Identifiable {
    case pm         // 项目经理 / 工长 / Builder / Foreman
    case engineer   // 工程师 / Inspector

    var id: String { rawValue }

    /// UI 显示名。
    var displayName: String {
        switch self {
        case .pm: return String(localized: "项目经理", locale: AppLanguageManager.currentLocale)
        case .engineer: return String(localized: "工程师", locale: AppLanguageManager.currentLocale)
        }
    }

    /// 一句话副标题(角色卡片用)。
    var subtitle: String {
        switch self {
        case .pm: return String(localized: "PM / 工长 / Builder", locale: AppLanguageManager.currentLocale)
        case .engineer: return String(localized: "Inspector", locale: AppLanguageManager.currentLocale)
        }
    }

    /// 长描述(onboarding 选择时显示)。
    var description: String {
        switch self {
        case .pm:
            return String(localized: "管工地全流程:人员/机械到场、隐患追踪、施工日志、EOT 索赔。", locale: AppLanguageManager.currentLocale)
        case .engineer:
            return String(localized: "做巡检/检验:专注问题与合规,导出标准 inspection report,可附图纸。", locale: AppLanguageManager.currentLocale)
        }
    }

    /// SF Symbol 图标。
    var sfSymbol: String {
        switch self {
        case .pm: return "checklist"
        case .engineer: return "doc.text.magnifyingglass"
        }
    }

    /// 主题色名(配合 Ink palette;实际颜色在 view 里映射)。
    var themeColorName: String {
        switch self {
        case .pm: return "orange"
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

    /// 用户是否已显式选过角色(onboarding 完成 OR Settings 改过)。
    /// 用来区分"老用户默认 PM"和"新用户主动选了 PM"。
    var hasExplicitlySelected: Bool {
        UserDefaults.standard.bool(forKey: Self.selectedFlagKey)
    }

    private static let key = "settings.userProfile"
    private static let selectedFlagKey = "settings.userProfile.selected"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? ProfileKind.pm.rawValue
        self.current = ProfileKind(rawValue: raw) ?? .pm
    }

    /// Onboarding / Settings 选择时调用。设 current + 标记已选过。
    func select(_ kind: ProfileKind) {
        current = kind
        UserDefaults.standard.set(true, forKey: Self.selectedFlagKey)
    }
}
