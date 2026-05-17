//
//  SettingsKeys.swift
//  SiteNote
//
//  @AppStorage 的键名集中维护 + AI 总开关读取。
//  原本在 SettingsView.swift 末尾,v1.3 清理 dead-code 时拆出来单文件。
//

import Foundation

/// @AppStorage 的键名集中维护。
enum SettingsKeys {
    static let speechLanguage = "settings.speechLanguage"
    static let morningReminderHour = "settings.morningReminderHour"
    static let morningReminderMinute = "settings.morningReminderMinute"
    /// v1.2 AI 精简:AI 总开关。关掉 = Polish 不跑。
    static let aiMasterEnabled = "settings.aiMasterEnabled"
    /// v1.2 AI 精简:Apple Intelligence Polish 开关。
    static let aiPolishEnabled = "settings.aiPolishEnabled"
    static let dailyDigestEnabled = "settings.dailyDigestEnabled"
}

/// 统一读 AI 总开关 + 单功能开关。两个都开才返回 true。
/// `master` 默认 true;`feature` 默认 true。
enum AIToggle {
    static var masterEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.aiMasterEnabled) as? Bool ?? true
    }

    static func featureEnabled(_ key: String) -> Bool {
        let feature = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        return masterEnabled && feature
    }
}
