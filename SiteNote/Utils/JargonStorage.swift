//
//  JargonStorage.swift
//  SiteNote
//
//  用户在 Settings 里维护两类东西的 UserDefaults 封装:
//  1. **专业词汇**(customTerms):一个字符串列表,会喂给 SFSpeechRecognizer.contextualStrings
//     和 AI polish prompt。例如 "老张装饰队"、"3 区"、自家产品名等 baseline 没收的。
//  2. **快捷词**(shortcuts):一组替换对 [(from, to)],会在 polish 之前对原始转写做字符串替换。
//     例如 ("打 con", "打 concrete")。
//
//  为什么分开两个 storage:语义不同——
//  - 词汇是"识别得对"(给 hint)
//  - 快捷词是"自动展开"(改文本内容)
//

import Foundation

enum JargonStorage {

    // MARK: - 1. 专业词汇

    private static let termsKey = "settings.jargonCustomTerms"

    static func loadCustomTerms() -> [String] {
        UserDefaults.standard.stringArray(forKey: termsKey) ?? []
    }

    static func saveCustomTerms(_ terms: [String]) {
        let cleaned = terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 30 }
        UserDefaults.standard.set(cleaned, forKey: termsKey)
    }

    @discardableResult
    static func addCustomTerm(_ term: String) -> [String] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 30 else { return loadCustomTerms() }
        var current = loadCustomTerms()
        if !current.contains(trimmed) {
            current.append(trimmed)
            saveCustomTerms(current)
        }
        return current
    }

    @discardableResult
    static func removeCustomTerm(_ term: String) -> [String] {
        var current = loadCustomTerms()
        current.removeAll { $0 == term }
        saveCustomTerms(current)
        return current
    }

    // MARK: - 2. 快捷词替换对

    /// 一对替换:from 在转写文本里出现 → 替换为 to。
    /// 例:from = "打 con", to = "打 concrete"。**大小写敏感**(用户自己控制)。
    struct Shortcut: Codable, Equatable, Identifiable {
        var id: UUID = UUID()
        var from: String
        var to: String
    }

    private static let shortcutsKey = "settings.jargonShortcuts"

    static func loadShortcuts() -> [Shortcut] {
        guard let data = UserDefaults.standard.data(forKey: shortcutsKey),
              let list = try? JSONDecoder().decode([Shortcut].self, from: data) else {
            return []
        }
        return list
    }

    static func saveShortcuts(_ shortcuts: [Shortcut]) {
        let cleaned = shortcuts
            .map {
                Shortcut(
                    id: $0.id,
                    from: $0.from.trimmingCharacters(in: .whitespacesAndNewlines),
                    to: $0.to.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.from.isEmpty && !$0.to.isEmpty }
        guard let data = try? JSONEncoder().encode(cleaned) else { return }
        UserDefaults.standard.set(data, forKey: shortcutsKey)
    }

    @discardableResult
    static func addShortcut(from: String, to: String) -> [Shortcut] {
        let trimmedFrom = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFrom.isEmpty, !trimmedTo.isEmpty else { return loadShortcuts() }
        var current = loadShortcuts()
        // 去重:from 相同的最新覆盖旧的。
        current.removeAll { $0.from == trimmedFrom }
        current.append(Shortcut(from: trimmedFrom, to: trimmedTo))
        saveShortcuts(current)
        return current
    }

    @discardableResult
    static func removeShortcut(id: UUID) -> [Shortcut] {
        var current = loadShortcuts()
        current.removeAll { $0.id == id }
        saveShortcuts(current)
        return current
    }

    /// 把所有快捷词替换应用到一段原始转写。在 AI polish 之前调,简单直接的字符串替换。
    /// 顺序:按 from 长度倒序(长的先替换,避免短的吃掉长的)。
    static func applyShortcuts(to raw: String) -> String {
        let shortcuts = loadShortcuts().sorted { $0.from.count > $1.from.count }
        var result = raw
        for s in shortcuts {
            result = result.replacingOccurrences(of: s.from, with: s.to)
        }
        return result
    }

    // MARK: - 全局清空

    /// 给 SettingsView 的"一键清空所有内容"调用。术语和快捷词都属于"用户内容",
    /// 清空时必须连带清掉,否则下家用户/重置后录音 AI 还会用到旧术语。
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: termsKey)
        UserDefaults.standard.removeObject(forKey: shortcutsKey)
    }
}
