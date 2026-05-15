//
//  BuildersStorage.swift
//  SiteNote
//
//  Builder/Foreman 联系人簿。给 Inspection 工作流的"一键发邮件"用。
//  存 UserDefaults JSON(条目少,几十个上限,扛得住)。
//

import Foundation

/// 一个建造商/工头联系人。
struct Builder: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String           // 显示名,如 "Banruo" 或 "HRK Foreman"
    var company: String        // 公司名,如 "HRK"
    var email: String          // 收件邮箱
    var phone: String          // 手机(可选,空字符串表示没记)
    var notes: String          // 备注(可选)

    init(
        id: UUID = UUID(),
        name: String = "",
        company: String = "",
        email: String = "",
        phone: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.company = company
        self.email = email
        self.phone = phone
        self.notes = notes
    }
}

enum BuildersStorage {
    private static let key = "settings.builders.v1"
    /// E3.3 同步上限:UserDefaults JSON 列表防爆。Builder 通常 5-30 个,上限 200 足够。
    static let maxItems = 200

    /// 读取全部联系人。失败/没存过返回空。
    static func load() -> [Builder] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Builder].self, from: data)) ?? []
    }

    /// 覆盖保存。超过 maxItems 截断到上限。
    @discardableResult
    static func save(_ items: [Builder]) -> Bool {
        let capped = items.count > maxItems ? Array(items.prefix(maxItems)) : items
        guard let data = try? JSONEncoder().encode(capped) else { return false }
        UserDefaults.standard.set(data, forKey: key)
        return true
    }

    /// 新增一个 Builder。空 name 或空 email 拒绝。
    /// - Returns: 添加成功返回 Builder.id;失败 nil。
    @discardableResult
    static func add(_ builder: Builder) -> UUID? {
        let trimmedName = builder.name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = builder.email.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedEmail.isEmpty else { return nil }
        var all = load()
        guard all.count < maxItems else { return nil }
        var entry = builder
        entry.name = trimmedName
        entry.email = trimmedEmail
        all.append(entry)
        return save(all) ? entry.id : nil
    }

    /// 更新指定 id 的条目。找不到返回 false。
    @discardableResult
    static func update(_ builder: Builder) -> Bool {
        var all = load()
        guard let idx = all.firstIndex(where: { $0.id == builder.id }) else { return false }
        all[idx] = builder
        return save(all)
    }

    /// 按 id 删除。
    static func remove(id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        save(all)
    }

    /// 按 id 查找。
    static func find(id: UUID) -> Builder? {
        load().first { $0.id == id }
    }

    /// 按 id 字符串(InspectionDraft.builderID 存的)查找。
    static func find(idString: String) -> Builder? {
        guard let uuid = UUID(uuidString: idString) else { return nil }
        return find(id: uuid)
    }

    /// 按 name 前缀模糊匹配(autocomplete 用)。大小写不敏感。
    static func match(prefix: String) -> [Builder] {
        let lower = prefix.lowercased()
        guard !lower.isEmpty else { return load() }
        return load().filter {
            $0.name.lowercased().hasPrefix(lower)
                || $0.company.lowercased().hasPrefix(lower)
        }
    }

    /// 一键清空(SettingsView 的 nukeEverything 用)。
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
