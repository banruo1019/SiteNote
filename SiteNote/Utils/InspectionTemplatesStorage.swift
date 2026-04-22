//
//  InspectionTemplatesStorage.swift
//  SiteNote
//
//  巡检模板的 UserDefaults JSON 持久化。模板是 "一组有序的检查项字符串"。
//

import Foundation

/// 一份巡检模板。
struct InspectionTemplate: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var items: [String]

    init(id: UUID = UUID(), name: String, items: [String]) {
        self.id = id
        self.name = name
        self.items = items
    }
}

/// 巡检模板存储。JSON 编码进 UserDefaults,第一次访问自动种入默认模板。
enum InspectionTemplatesStorage {
    private static let key = "settings.inspectionTemplates"
    private static let seededKey = "settings.inspectionTemplates.seeded"

    /// 默认模板种子。首次调用 `load()` 时写入。
    private static var defaultSeeds: [InspectionTemplate] {
        [
            InspectionTemplate(
                name: "安全日检",
                items: [
                    "个人防护装备齐全",
                    "施工区警示标识到位",
                    "脚手架稳固",
                    "电缆无裸露",
                    "灭火器就位",
                    "急救箱完备",
                    "应急通道畅通"
                ]
            ),
            InspectionTemplate(
                name: "混凝土浇筑",
                items: [
                    "钢筋验收已完成",
                    "模板稳固、标高正确",
                    "配合比签认",
                    "坍落度检测",
                    "取样留置试块",
                    "振捣密实",
                    "养护安排到位"
                ]
            ),
            InspectionTemplate(
                name: "脚手架验收",
                items: [
                    "立杆基础硬化",
                    "扫地杆、剪刀撑齐全",
                    "连墙件间距合规",
                    "跳板铺满、绑扎牢固",
                    "安全网封闭",
                    "登高梯稳固",
                    "挂牌标识完整"
                ]
            )
        ]
    }

    /// 读取全部模板。首次读取时自动种入默认模板(一次性)。
    static func load() -> [InspectionTemplate] {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: seededKey) {
            save(defaultSeeds)
            defaults.set(true, forKey: seededKey)
            return defaultSeeds
        }
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([InspectionTemplate].self, from: data) else {
            return []
        }
        return list
    }

    /// 覆盖全量保存。
    static func save(_ templates: [InspectionTemplate]) {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// 追加一个新模板。
    @discardableResult
    static func add(_ template: InspectionTemplate) -> [InspectionTemplate] {
        var current = load()
        current.append(template)
        save(current)
        return current
    }

    /// 按 id 更新一个模板。
    @discardableResult
    static func update(_ template: InspectionTemplate) -> [InspectionTemplate] {
        var current = load()
        if let idx = current.firstIndex(where: { $0.id == template.id }) {
            current[idx] = template
            save(current)
        }
        return current
    }

    /// 按 id 删除一个模板。
    @discardableResult
    static func remove(id: UUID) -> [InspectionTemplate] {
        var current = load()
        current.removeAll { $0.id == id }
        save(current)
        return current
    }
}
