//
//  AppLanguage.swift
//  SiteNote
//
//  App 内语言切换。三档:跟随系统 / 简体中文 / English。
//  - SwiftUI Text(LocalizedStringKey)即时切换,通过 .environment(\.locale)。
//  - String(localized:, locale:) 等显式 API 通过传 locale: AppLanguageManager.currentLocale 即时生效;不传则跟 Bundle 走需重启。
//

import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String(localized: "跟随系统", locale: AppLanguageManager.currentLocale)
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }

    /// 用来 driving `.environment(\.locale)` 与 UserDefaults["AppleLanguages"]。
    /// `.system` 返回 nil 表示"跟随系统"——交给 iOS 自己挑。
    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .zhHans: return "zh-Hans"
        case .en: return "en"
        }
    }
}

@Observable
final class AppLanguageManager {
    static let shared = AppLanguageManager()

    var current: AppLanguage {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: Self.key)
            applyToBundle()
        }
    }

    /// SwiftUI 注入到 `.environment(\.locale)` 的值。
    /// `.system` 时用 `Locale.current`,让 SwiftUI 走系统默认。
    var locale: Locale { Self.currentLocale }

    /// **Nonisolated** 读取当前 locale。给 `LocalizedError.errorDescription` 等
    /// nonisolated 协议方法用——它们无法访问 MainActor 隔离的 `shared`。
    /// 直接从 UserDefaults["AppleLanguages"] 读,绕开单例,Locale 是 value type 线程安全。
    nonisolated static var currentLocale: Locale {
        if let langs = UserDefaults.standard.array(forKey: appleLanguagesKey) as? [String],
           let first = langs.first {
            return Locale(identifier: first)
        }
        return .current
    }

    nonisolated private static let key = "settings.appLanguage"
    nonisolated private static let appleLanguagesKey = "AppleLanguages"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? AppLanguage.system.rawValue
        let stored = AppLanguage(rawValue: raw) ?? .system

        // F1 (R1-P2-12):iOS Settings → SiteNote → Language 改 per-app 语言时,
        // 系统会写 UserDefaults["AppleLanguages"] 第一项。这恰好也是 applyToBundle 写入的 key。
        // 启动时若 AppleLanguages 与 settings.appLanguage 不一致,以 AppleLanguages 为新真相
        // (用户在系统设置改了 → 应该跟随),并把 settings.appLanguage 同步过去。
        let systemAppleLangs = UserDefaults.standard.array(forKey: Self.appleLanguagesKey) as? [String]
        let systemPrimary = systemAppleLangs?.first

        let resolved: AppLanguage
        if let primary = systemPrimary, let inferred = Self.appLanguage(forAppleLanguagesPrimary: primary) {
            if inferred != stored {
                // iOS 系统设置已改,以系统为准,反向同步到 in-app 偏好。
                resolved = inferred
                UserDefaults.standard.set(inferred.rawValue, forKey: Self.key)
            } else {
                resolved = stored
            }
        } else {
            // AppleLanguages 缺失或无法解析 → 沿用 in-app 偏好。
            resolved = stored
        }

        self.current = resolved
        applyToBundle()
    }

    /// F1:把 `UserDefaults["AppleLanguages"]` 第一项(如 "en", "zh-Hans-US")映射回 AppLanguage。
    /// iOS 没改过会是 nil 或缺失;改过后是带 region 的 BCP-47。
    /// 不识别的语言一律落到 `.system`。
    private static func appLanguage(forAppleLanguagesPrimary primary: String) -> AppLanguage? {
        let lower = primary.lowercased()
        if lower.hasPrefix("zh") {
            // zh-Hans / zh-Hans-CN / zh-CN 一律视作简体。
            // 简化处理:不区分繁简(项目当前只支持 zh-Hans)。
            return .zhHans
        }
        if lower.hasPrefix("en") {
            return .en
        }
        return nil
    }

    /// 写 AppleLanguages 让 Bundle.localizedString / String(localized:) 在下次启动时认它。
    /// SwiftUI Text 这边靠 `.environment(\.locale)` 即时生效,这条只为非 SwiftUI 的 API。
    private func applyToBundle() {
        if let id = current.localeIdentifier {
            UserDefaults.standard.set([id], forKey: Self.appleLanguagesKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.appleLanguagesKey)
        }
    }
}
