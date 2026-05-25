//
//  DisclaimerStorage.swift
//  SiteNote
//
//  巡检报告默认 disclaimer 文本。InspectionDraft.disclaimerText 为 nil(或
//  PDF 渲染时未自定义)时,使用这里的内容。
//
//  存 UserDefaults JSON([String])。空数组表示"用 defaults",即用户从未自
//  定义或主动恢复了默认。
//

import Foundation

/// 巡检报告默认 disclaimer 文本。InspectionDraft.disclaimerText 为 nil 时,PDF 用这个。
enum DisclaimerStorage {
    private static let key = "settings.inspectionDisclaimers.v1"

    /// v1.6 (en-v1):不再 ship 任何预设 disclaimer(原 5 条带公司特定法律措辞,泄露公司信息)。
    /// 用户自己在 Settings → 默认免责声明 里逐条加。空 = 不画 DISCLAIMERS 段。
    static let defaults: [String] = []

    /// 读用户自定义。失败/没存过返回空。
    static func load() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// 保存(覆盖)。空数组也接受 — 表示用户主动清空,PDF 就不画 disclaimer 段。
    /// - 空字符串条目会被先过滤掉(避免存"5 条空白")。
    static func save(_ items: [String]) {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if cleaned.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(cleaned) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// 当前生效的 — 用户没加过任何一条 → 空数组,PDF 跳过 DISCLAIMERS 段。
    static func current() -> [String] {
        return load()
    }

    /// 清空用户自定义。
    static func restoreDefaults() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
