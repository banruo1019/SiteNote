//
//  SiteArchiveStorage.swift
//  SiteNote
//
//  归档项目(工地)的存储。UserDefaults string set,存被归档的工地 tag。
//
//  主屏"记" Tab 按工地分组时,归档的工地从默认分组移到底部"已归档项目"折叠区。
//  归档不删除工地标签或其 Note —— 只是从默认视图移开。
//

import Foundation

enum SiteArchiveStorage {

    private static let key = "settings.archivedSites.v1"

    /// 当前归档的工地 tags(set,无序)。
    static func loadArchived() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(arr)
    }

    /// 判定某工地是否在归档列表。
    static func isArchived(_ tag: String) -> Bool {
        loadArchived().contains(tag)
    }

    /// 归档一个工地。已归档无副作用。
    static func archive(_ tag: String) {
        var set = loadArchived()
        set.insert(tag)
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    /// 取消归档。不在列表无副作用。
    static func unarchive(_ tag: String) {
        var set = loadArchived()
        set.remove(tag)
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    /// 删除整个工地时(SiteResourcesSettingsView)同步清掉归档状态。
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
