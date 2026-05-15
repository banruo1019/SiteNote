//
//  SitePresetStorage.swift
//  SiteNote
//
//  Engineer 工地预设:把"工地"和"工程师常用项目信息"绑定,
//  导出 Inspection 报告时按 siteTag 自动 prefill Header 字段。
//
//  关联机制:siteTag 是字符串 key(同 SiteTagsStorage),一个 siteTag 对应一条 SitePreset。
//  实际工作流:
//    1. 工程师在 Settings → 工地预设 添加一条:siteTag = "Olympic Park",projectNo = "25159",client = "HRK",...
//    2. 录音时 GPS 反向地理编码 → 自动匹配 siteTag
//    3. 导出报告时,InspectionFormView 拿 Note.siteTag → SitePresetStorage.find → 自动填 Header
//

import Foundation

struct SitePreset: Codable, Identifiable, Hashable {
    let id: UUID
    var siteTag: String            // 关联 SiteTagsStorage 的 tag,e.g. "Olympic Park"
    var projectName: String        // "Proposed duplex"
    var projectNo: String          // "25159"
    var clientName: String         // "HRK"
    var address: String            // "38 FORSYTH ST NORTH WILLOUGHBY"
    var defaultAttn: String        // "Banruo"(builder.name 或手输)
    var defaultBuilderID: UUID?    // BuildersStorage.Builder.id;nil 表示无关联
    var defaultInspectionType: String  // "level 1 reo"(用户每次只改这个)
    var notes: String              // 备注(可选)

    /// 分配给团队哪个成员的 userID(CKRecord.recordName / Apple ID)。
    /// 团队 Owner 可设置;nil = 未分配 / 团队公用。
    var assignedToUserID: String?
    /// 分配时间(Owner 决定时记)。
    var assignedAt: Date?

    init(
        id: UUID = UUID(),
        siteTag: String = "",
        projectName: String = "",
        projectNo: String = "",
        clientName: String = "",
        address: String = "",
        defaultAttn: String = "",
        defaultBuilderID: UUID? = nil,
        defaultInspectionType: String = "",
        notes: String = "",
        assignedToUserID: String? = nil,
        assignedAt: Date? = nil
    ) {
        self.id = id
        self.siteTag = siteTag
        self.projectName = projectName
        self.projectNo = projectNo
        self.clientName = clientName
        self.address = address
        self.defaultAttn = defaultAttn
        self.defaultBuilderID = defaultBuilderID
        self.defaultInspectionType = defaultInspectionType
        self.notes = notes
        self.assignedToUserID = assignedToUserID
        self.assignedAt = assignedAt
    }
}

enum SitePresetStorage {
    private static let key = "settings.sitePresets.v1"
    static let maxItems = 200

    static func load() -> [SitePreset] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SitePreset].self, from: data)) ?? []
    }

    @discardableResult
    static func save(_ items: [SitePreset]) -> Bool {
        let capped = items.count > maxItems ? Array(items.prefix(maxItems)) : items
        guard let data = try? JSONEncoder().encode(capped) else { return false }
        UserDefaults.standard.set(data, forKey: key)
        return true
    }

    @discardableResult
    static func add(_ preset: SitePreset) -> UUID? {
        let trimmed = preset.siteTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var all = load()
        // siteTag 唯一:同 tag 已存在则更新,不重复添加
        if let idx = all.firstIndex(where: { $0.siteTag == trimmed }) {
            var entry = preset
            entry.siteTag = trimmed
            all[idx] = entry
            return save(all) ? all[idx].id : nil
        }
        guard all.count < maxItems else { return nil }
        var entry = preset
        entry.siteTag = trimmed
        all.append(entry)
        return save(all) ? entry.id : nil
    }

    @discardableResult
    static func update(_ preset: SitePreset) -> Bool {
        var all = load()
        guard let idx = all.firstIndex(where: { $0.id == preset.id }) else { return false }
        all[idx] = preset
        return save(all)
    }

    static func remove(id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        save(all)
    }

    /// 按 siteTag 反查。导出报告时用 Note.siteTag → 这里拿预设填表。
    static func find(siteTag: String) -> SitePreset? {
        let trimmed = siteTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return load().first { $0.siteTag == trimmed }
    }

    static func find(id: UUID) -> SitePreset? {
        load().first { $0.id == id }
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
