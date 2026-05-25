//
//  FloorPlansStorage.swift
//  SiteNote
//
//  工地平面图存储:图文件在 Documents/floorplans/,索引在 UserDefaults。
//  Phase 10 改动:FloorPlan 加 `siteTag` 字段,按工地分组;未绑定的归到 "未分类"。
//

import Foundation
import UIKit

struct FloorPlan: Codable, Identifiable, Hashable {
    let id: UUID
    /// 楼层/区域名字,如 "3 楼"、"地下室"、"东区机房"。
    var name: String
    /// 相对 Documents 的路径。
    let imageRelativePath: String
    /// 所属工地标签。`nil` 表示未分类(老数据或独立使用)。
    var siteTag: String?

    init(
        id: UUID = UUID(),
        name: String,
        imageRelativePath: String,
        siteTag: String? = nil
    ) {
        self.id = id
        self.name = name
        self.imageRelativePath = imageRelativePath
        self.siteTag = siteTag
    }
}

enum FloorPlansStorage {
    private static let key = "settings.floorPlans"

    /// 全部平面图(任意工地)。
    static func load() -> [FloorPlan] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([FloorPlan].self, from: data) else {
            return []
        }
        return list
    }

    /// 只看某工地的楼层(`siteTag == nil` 即过滤"未分类")。
    static func load(for siteTag: String?) -> [FloorPlan] {
        load().filter { $0.siteTag == siteTag }
    }

    /// 按工地名字分组。返回字典:工地名(或 nil=未分类)→ 该工地的楼层数组。
    static func loadGroupedBySite() -> [String?: [FloorPlan]] {
        Dictionary(grouping: load(), by: { $0.siteTag })
    }

    private static func save(_ plans: [FloorPlan]) {
        guard let data = try? JSONEncoder().encode(plans) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// 上传一张 UIImage 为新楼层。失败返回 nil。
    @discardableResult
    static func add(image: UIImage, name: String, siteTag: String?) -> FloorPlan? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return nil }

        let dir = docs.appendingPathComponent("floorplans", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString).jpg"
        let url = dir.appendingPathComponent(filename)
        guard let data = image.jpegData(compressionQuality: 0.85),
              (try? data.write(to: url)) != nil else {
            return nil
        }

        let plan = FloorPlan(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            imageRelativePath: "floorplans/\(filename)",
            siteTag: siteTag
        )
        var all = load()
        all.append(plan)
        save(all)
        return plan
    }

    static func remove(id: UUID) {
        var all = load()
        if let toRemove = all.first(where: { $0.id == id }) {
            if let url = absoluteURL(forRelative: toRemove.imageRelativePath) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        all.removeAll { $0.id == id }
        save(all)
    }

    /// 按名字查(优先带 siteTag 过滤,避免重名冲突)。
    static func find(name: String, siteTag: String? = nil) -> FloorPlan? {
        let all = load()
        if let site = siteTag,
           let found = all.first(where: { $0.name == name && $0.siteTag == site }) {
            return found
        }
        return all.first(where: { $0.name == name })
    }

    /// P2 #187:按 UUID 查 — 稳定引用,改名不丢绑定。
    /// 老数据 Note 没 floorPlanID 时,caller 走 find(name:) fallback。
    static func find(id: UUID) -> FloorPlan? {
        load().first(where: { $0.id == id })
    }

    /// P2 #187:fallback chain — 优先 id,fallback name,都没就 nil。
    /// 给 view / PDF builder 用,统一一处。
    static func resolve(id: UUID?, name: String?, siteTag: String? = nil) -> FloorPlan? {
        if let id, let byID = find(id: id) {
            return byID
        }
        if let name {
            return find(name: name, siteTag: siteTag)
        }
        return nil
    }

    static func absoluteURL(forRelative relative: String) -> URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return docs.appendingPathComponent(relative)
    }
}
