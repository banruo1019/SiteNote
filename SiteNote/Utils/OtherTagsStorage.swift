//
//  SubTagsStorage (文件名暂保留 OtherTagsStorage.swift,下一次 Xcode 工程整理时改)
//  SiteNote
//
//  **分类 = 独立的全局标签类型**(不属于任何工地)。
//  一条 note 的工地和分类是正交关系:
//    - siteTag: 一条属于哪个工地(单选)
//    - subTag:  一条是什么类型(单选,如 RFI / 缺陷 / 施工 / 开会 / 紧急)
//  每个分类带颜色,用在 chip 染色 + 平面图图钉色。
//

import Foundation
import SwiftUI

/// 一个分类。全局共享,不按工地隔离。
struct SubTag: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    /// 颜色名(见 `SubTag.availableColorNames`)。
    var colorName: String

    init(id: UUID = UUID(), name: String, colorName: String = "blue") {
        self.id = id
        self.name = name
        self.colorName = colorName
    }

    /// SwiftUI 颜色。
    var color: Color {
        SubTag.color(from: colorName)
    }

    /// UIKit 颜色(给 PDF / 短信合成用)。
    var uiColor: UIColor {
        SubTag.uiColor(from: colorName)
    }

    static func color(from name: String) -> Color {
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "teal": return .teal
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        default: return .gray
        }
    }

    static func uiColor(from name: String) -> UIColor {
        switch name {
        case "red": return .systemRed
        case "orange": return .systemOrange
        case "yellow": return .systemYellow
        case "green": return .systemGreen
        case "teal": return .systemTeal
        case "blue": return .systemBlue
        case "indigo": return .systemIndigo
        case "purple": return .systemPurple
        case "pink": return .systemPink
        case "brown": return .systemBrown
        default: return .systemGray
        }
    }

    static let availableColorNames: [String] = [
        "red", "orange", "yellow", "green", "teal", "blue",
        "indigo", "purple", "pink", "brown"
    ]
}

/// 全局分类持久化。扁平列表,无工地分组。
enum SubTagsStorage {
    private static let key = "settings.subTagsGlobalV1"

    static func load() -> [SubTag] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([SubTag].self, from: data) else {
            return []
        }
        return list
    }

    private static func save(_ list: [SubTag]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    @discardableResult
    static func add(_ tag: SubTag) -> [SubTag] {
        var all = load()
        if !all.contains(where: { $0.name == tag.name }) {
            all.append(tag)
            save(all)
        }
        return all
    }

    @discardableResult
    static func remove(id: UUID) -> [SubTag] {
        var all = load()
        all.removeAll { $0.id == id }
        save(all)
        return all
    }

    @discardableResult
    static func update(_ tag: SubTag) -> [SubTag] {
        var all = load()
        if let idx = all.firstIndex(where: { $0.id == tag.id }) {
            all[idx] = tag
            save(all)
        }
        return all
    }

    static func lookup(name: String) -> SubTag? {
        load().first { $0.name == name }
    }

    static func color(name: String) -> Color {
        lookup(name: name)?.color ?? .gray
    }

    static func uiColor(name: String) -> UIColor {
        lookup(name: name)?.uiColor ?? .systemGray
    }
}
