//
//  SitePresetStorage.swift
//  SiteNote
//
//  Engineer 工地预设:把"工地"和"工程师常用项目信息"绑定,
//  导出 Inspection 报告时按 siteTag 自动 prefill Header 字段。
//
//  v1.6 重大变化:从 struct + UserDefaults JSON 升级到 SwiftData @Model class,
//  为团队协作(CloudKit Sharing)铺路 — 跨用户共享必须走 @Model + CloudKit DB。
//
//  callers 不变:SitePresetStorage 保留为 facade,内部从 UserDefaults 切换到
//  SwiftData。view 层 @State load() / find() / add() / update() / remove() 用法不变,
//  只是返回的 SitePreset 现在是 reference type(@Model class)。
//
//  数据迁移:启动时(SiteNoteApp init)调一次 `migrateFromUserDefaultsOnce`,
//  把老 JSON 倒进 SwiftData。idempotent flag 防重跑。
//
//  关联机制:siteTag 是字符串 key(同 SiteTagsStorage),一个 siteTag 对应一条 SitePreset。
//  实际工作流:
//    1. 工程师在 Settings → 工地预设 添加一条:siteTag = "Olympic Park",projectNo = "25159",client = "Acme",...
//    2. 录音时 GPS 反向地理编码 → 自动匹配 siteTag
//    3. 导出报告时,InspectionFormView 拿 Note.siteTag → SitePresetStorage.find → 自动填 Header
//

import Foundation
import SwiftData

@Model
final class SitePreset {
    // 用 var(不是 let)— @Model 的硬性要求,字段全部 var + 全部默认值(CloudKit 同步前提)
    var id: UUID = UUID()
    var siteTag: String = ""
    var projectName: String = ""
    var projectNo: String = ""
    var clientName: String = ""
    var address: String = ""
    var defaultAttn: String = ""
    /// [Deprecated v1.4] 保留向后兼容;新代码用 defaultRecipientIDs
    var defaultBuilderID: UUID?
    var defaultInspectionType: String = ""
    var notes: String = ""

    /// 分配给团队哪个成员的 userID(CKRecord.recordName / Apple ID)。
    var assignedToUserID: String?
    /// 分配时间。
    var assignedAt: Date?

    /// v1.4 工地工作台:本工地能用的所有联系人(Contact.id),superset of defaultRecipientIDs。
    var linkedContactIDs: [UUID] = []
    /// v1.4 开始巡检时自动勾上的收件人(子集必须 ∈ linkedContactIDs)。
    var defaultRecipientIDs: [UUID] = []

    /// 创建时间 — 用于 list 排序保持一致。
    var createdAt: Date = Date()
    /// 更新时间 — 任何改动后写。
    var updatedAt: Date = Date()
    /// 软删 — 团队 sync 场景,硬删会让 member 端 dangling。
    var deletedAt: Date?

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
        assignedAt: Date? = nil,
        linkedContactIDs: [UUID] = [],
        defaultRecipientIDs: [UUID] = []
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
        self.linkedContactIDs = linkedContactIDs
        self.defaultRecipientIDs = defaultRecipientIDs
    }
}

/// Facade — 内部走 SwiftData。callers 不动。
/// @MainActor:SwiftData ModelContext 是 main-actor-only;callers 99% 在 SwiftUI view 里,
/// 已经在 MainActor,sync 调用透明。
@MainActor
enum SitePresetStorage {
    static let maxItems = 200

    private static var context: ModelContext? {
        SwiftDataStack.shared.mainContext
    }

    // MARK: - Read

    /// 全部未删除工地预设,按 createdAt 升序(老的在前,稳定)。
    static func load() -> [SitePreset] {
        guard let ctx = context else { return [] }
        let desc = FetchDescriptor<SitePreset>(
            predicate: #Predicate<SitePreset> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? ctx.fetch(desc)) ?? []
    }

    /// 按 siteTag 反查(导出报告时用)。
    static func find(siteTag: String) -> SitePreset? {
        let trimmed = siteTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let ctx = context else { return nil }
        let desc = FetchDescriptor<SitePreset>(
            predicate: #Predicate<SitePreset> {
                $0.siteTag == trimmed && $0.deletedAt == nil
            }
        )
        return (try? ctx.fetch(desc))?.first
    }

    static func find(id: UUID) -> SitePreset? {
        guard let ctx = context else { return nil }
        let desc = FetchDescriptor<SitePreset>(
            predicate: #Predicate<SitePreset> {
                $0.id == id && $0.deletedAt == nil
            }
        )
        return (try? ctx.fetch(desc))?.first
    }

    // MARK: - Write

    /// 新增 / 更新 — siteTag 唯一,同 tag 已存在则把新 preset 的字段写到旧 entity(保持 id)。
    /// 返回新增 / 更新后的 SitePreset.id。空 siteTag 拒绝。
    @discardableResult
    static func add(_ preset: SitePreset) -> UUID? {
        let trimmed = preset.siteTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let ctx = context else { return nil }

        // 同 siteTag 已存在 → 合并到旧 entity
        if let existing = find(siteTag: trimmed) {
            copyFields(from: preset, to: existing, siteTagOverride: trimmed)
            existing.updatedAt = Date()
            try? ctx.save()
            fireMirror(existing, in: ctx)
            return existing.id
        }

        // 容量限制(load 计数过滤了软删)
        guard load().count < maxItems else { return nil }
        preset.siteTag = trimmed
        preset.updatedAt = Date()
        // 防御:如果 caller 传进来的是已 insert 过的 @Model(避免重复 insert)
        if preset.modelContext == nil {
            ctx.insert(preset)
        }
        try? ctx.save()
        fireMirror(preset, in: ctx)
        return preset.id
    }

    /// 按 id 更新整个 entity 的字段。找不到返 false。
    @discardableResult
    static func update(_ preset: SitePreset) -> Bool {
        guard let existing = find(id: preset.id), let ctx = context else { return false }
        copyFields(from: preset, to: existing, siteTagOverride: nil)
        existing.updatedAt = Date()
        try? ctx.save()
        fireMirror(existing, in: ctx)
        return true
    }

    /// 软删 — 团队同步前提下硬删会让 member 端 dangling。
    static func remove(id: UUID) {
        guard let entity = find(id: id), let ctx = context else { return }
        entity.deletedAt = Date()
        entity.updatedAt = Date()
        try? ctx.save()
        fireMirror(entity, in: ctx)
    }

    // MARK: - Cloud mirror trigger(team 场景才有动作)

    /// 写本地后 fire-and-forget 把 preset 镜像到 team share zone。
    /// 单机模式(无 Team)直接 no-op。失败 silent + log。
    private static func fireMirror(_ preset: SitePreset, in ctx: ModelContext) {
        Task { @MainActor in
            await TeamDataMirrorService.shared.mirrorSitePreset(preset, in: ctx)
        }
    }

    /// 用于 "清空所有内容" 危险按钮。硬删所有 SitePreset(本地 + 让 SwiftData CloudKit 同步删)。
    static func clearAll() {
        guard let ctx = context else { return }
        try? ctx.delete(model: SitePreset.self)
        try? ctx.save()
    }

    /// 保存整列表 — 老 callers 用于排序后回写。新 SwiftData 走 update 路径即可。
    /// 这里实现为:对每条调 update(找不到的就 add)。
    @discardableResult
    static func save(_ items: [SitePreset]) -> Bool {
        for item in items {
            if find(id: item.id) != nil {
                _ = update(item)
            } else {
                _ = add(item)
            }
        }
        return true
    }

    // MARK: - Migration

    /// UserDefaults JSON → SwiftData 一次性迁移。SiteNoteApp init 时调。
    /// idempotent:flag `settings.sitePresets.migratedToSwiftData.v1` 防重跑。
    static func migrateFromUserDefaultsOnce() {
        let flagKey = "settings.sitePresets.migratedToSwiftData.v1"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        guard let ctx = context else { return }

        let legacyKey = "settings.sitePresets.v1"
        guard let data = UserDefaults.standard.data(forKey: legacyKey),
              let legacyArray = try? JSONDecoder().decode([LegacySitePreset].self, from: data) else {
            // 没老数据也算迁完(防下次 app 启动重跑)
            UserDefaults.standard.set(true, forKey: flagKey)
            return
        }

        for legacy in legacyArray {
            // 防重:已在 SwiftData 的 siteTag 不再插
            let trimmedTag = legacy.siteTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTag.isEmpty else { continue }
            if find(siteTag: trimmedTag) != nil { continue }

            let preset = SitePreset(
                id: legacy.id,
                siteTag: trimmedTag,
                projectName: legacy.projectName,
                projectNo: legacy.projectNo,
                clientName: legacy.clientName,
                address: legacy.address,
                defaultAttn: legacy.defaultAttn,
                defaultBuilderID: legacy.defaultBuilderID,
                defaultInspectionType: legacy.defaultInspectionType,
                notes: legacy.notes,
                assignedToUserID: legacy.assignedToUserID,
                assignedAt: legacy.assignedAt,
                linkedContactIDs: legacy.linkedContactIDs,
                defaultRecipientIDs: legacy.defaultRecipientIDs
            )
            ctx.insert(preset)
        }
        try? ctx.save()
        UserDefaults.standard.set(true, forKey: flagKey)
        // 老 JSON 暂不删 — 回滚保险。下一版本可清。
    }

    // MARK: - Helpers

    /// 把 preset(struct-style 字段)的字段复制到 existing(@Model entity)。
    /// 用于"siteTag 已存在的合并"和 update。
    /// siteTagOverride 不为空时强制写该值(去掉前后空白的 siteTag),否则不动 siteTag(update 路径用)。
    private static func copyFields(from src: SitePreset, to dst: SitePreset, siteTagOverride: String?) {
        if let tag = siteTagOverride {
            dst.siteTag = tag
        }
        dst.projectName = src.projectName
        dst.projectNo = src.projectNo
        dst.clientName = src.clientName
        dst.address = src.address
        dst.defaultAttn = src.defaultAttn
        dst.defaultBuilderID = src.defaultBuilderID
        dst.defaultInspectionType = src.defaultInspectionType
        dst.notes = src.notes
        dst.assignedToUserID = src.assignedToUserID
        dst.assignedAt = src.assignedAt
        dst.linkedContactIDs = src.linkedContactIDs
        dst.defaultRecipientIDs = src.defaultRecipientIDs
    }
}

// MARK: - Legacy decoding

/// 老 UserDefaults JSON 的 Codable 镜像 — 只用于一次性迁移。@Model class 自身不再 Codable。
private struct LegacySitePreset: Codable {
    let id: UUID
    var siteTag: String
    var projectName: String
    var projectNo: String
    var clientName: String
    var address: String
    var defaultAttn: String
    var defaultBuilderID: UUID?
    var defaultInspectionType: String
    var notes: String
    var assignedToUserID: String?
    var assignedAt: Date?
    var linkedContactIDs: [UUID]
    var defaultRecipientIDs: [UUID]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.siteTag = try c.decode(String.self, forKey: .siteTag)
        self.projectName = try c.decodeIfPresent(String.self, forKey: .projectName) ?? ""
        self.projectNo = try c.decodeIfPresent(String.self, forKey: .projectNo) ?? ""
        self.clientName = try c.decodeIfPresent(String.self, forKey: .clientName) ?? ""
        self.address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        self.defaultAttn = try c.decodeIfPresent(String.self, forKey: .defaultAttn) ?? ""
        self.defaultBuilderID = try c.decodeIfPresent(UUID.self, forKey: .defaultBuilderID)
        self.defaultInspectionType = try c.decodeIfPresent(String.self, forKey: .defaultInspectionType) ?? ""
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.assignedToUserID = try c.decodeIfPresent(String.self, forKey: .assignedToUserID)
        self.assignedAt = try c.decodeIfPresent(Date.self, forKey: .assignedAt)

        var linked = try c.decodeIfPresent([UUID].self, forKey: .linkedContactIDs) ?? []
        var defaults = try c.decodeIfPresent([UUID].self, forKey: .defaultRecipientIDs) ?? []
        if linked.isEmpty, defaults.isEmpty, let legacy = defaultBuilderID {
            linked = [legacy]
            defaults = [legacy]
        }
        self.linkedContactIDs = linked
        self.defaultRecipientIDs = defaults
    }
}
