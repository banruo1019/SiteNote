//
//  ClauseRefsStorage.swift
//  SiteNote
//
//  合同条款常用引用的 UserDefaults 持久化。字符串列表,用户在设置页维护。
//

import Foundation

/// 常用合同条款引用(任务 19)。
///
/// 首次访问自动种入几条典型的 AS4000 类合同条款,用户可在设置里增删。
enum ClauseRefsStorage {
    private static let key = "settings.clauseRefs"
    private static let seededKey = "settings.clauseRefs.seeded"

    private static var defaultSeeds: [String] {
        [
            "Clause 34 - Extension of Time (EOT)",
            "Clause 35 - Delay Damages",
            "Clause 36 - Variations",
            "Clause 37 - Payment Claims",
            "Clause 42 - Disputes"
        ]
    }

    static func load() -> [String] {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: seededKey) {
            defaults.set(defaultSeeds, forKey: key)
            defaults.set(true, forKey: seededKey)
            return defaultSeeds
        }
        return defaults.stringArray(forKey: key) ?? []
    }

    static func save(_ refs: [String]) {
        UserDefaults.standard.set(refs, forKey: key)
    }

    @discardableResult
    static func add(_ ref: String) -> [String] {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return load() }
        var current = load()
        if !current.contains(trimmed) {
            current.append(trimmed)
            save(current)
        }
        return current
    }

    @discardableResult
    static func remove(_ ref: String) -> [String] {
        var current = load()
        current.removeAll { $0 == ref }
        save(current)
        return current
    }
}
