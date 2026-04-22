//
//  SiteTagsStorage.swift
//  SiteNote
//
//  工地标签的 UserDefaults 持久化封装。所有读写走这里,避免 key 拼写错乱。
//

import Foundation

/// 工地标签列表的存储。
enum SiteTagsStorage {
    private static let key = "settings.siteTags"

    /// 读取所有工地标签。
    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// 保存整个标签列表。
    static func save(_ tags: [String]) {
        UserDefaults.standard.set(tags, forKey: key)
    }

    /// 追加一个新标签（去重 + 去空白）。
    @discardableResult
    static func add(_ tag: String) -> [String] {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return load() }
        var current = load()
        if !current.contains(trimmed) {
            current.append(trimmed)
            save(current)
        }
        return current
    }

    /// 删除一个标签。
    @discardableResult
    static func remove(_ tag: String) -> [String] {
        var current = load()
        current.removeAll { $0 == tag }
        save(current)
        return current
    }
}
