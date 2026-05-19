//
//  BuildersStorage.swift
//  SiteNote
//
//  Builder = "公司"/建造商(两级联系簿的第 1 级)。
//  下挂多条 Contact(具体联系人,见 ContactsStorage)。
//
//  历史:v1.4 之前 Builder 是扁平的(name/email/phone/company 一锅端),
//  v1.5 拆成 Builder(公司)+ Contact(联系人)两级。老数据通过
//  ContactsStorage.migrateFromBuilderLegacyOnce() 一次性迁移。
//
//  decoder 兼容:老 JSON 里的 `company` / `email` / `phone` 字段被吞掉(不再用),
//  保留 `notes`。新版本写出的 JSON 只含 `id` / `name` / `notes`。
//
//  存 UserDefaults JSON(条目少,几十-几百个上限)。
//

import Foundation

/// 一个建造商公司(Builder)。
struct Builder: Codable, Identifiable, Hashable {
    let id: UUID
    /// 公司名,如 "Acme Construction"。
    var name: String
    var notes: String

    init(
        id: UUID = UUID(),
        name: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.notes = notes
    }

    /// Codable decode:老 JSON 的 company/email/phone 字段被忽略,
    /// 老的 name 字段保留(迁移逻辑在 ContactsStorage 里负责把它重置为公司名)。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    /// 显式 CodingKeys:只编码新字段(老字段不再回写,JSON 越读越干净)。
    enum CodingKeys: String, CodingKey {
        case id, name, notes
    }
}

enum BuildersStorage {
    private static let key = "settings.builders.v1"
    /// 同步上限:UserDefaults JSON 列表防爆。
    static let maxItems = 200

    /// 读取全部 Builder。失败/没存过返回空。
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

    /// 新增一个 Builder(公司)。空 name 拒绝;同名公司不去重(下层用户自己看)。
    /// - Returns: 添加成功返回 Builder.id;失败 nil。
    @discardableResult
    static func add(_ builder: Builder) -> UUID? {
        let trimmedName = builder.name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        var all = load()
        guard all.count < maxItems else { return nil }
        var entry = builder
        entry.name = trimmedName
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

    /// 按 id 删除。同时连带删除该公司下的全部 Contact。
    static func remove(id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        save(all)
        ContactsStorage.removeAll(builderID: id)
    }

    /// 按 id 查找。
    static func find(id: UUID) -> Builder? {
        load().first { $0.id == id }
    }

    /// 按 id 字符串查找。
    static func find(idString: String) -> Builder? {
        guard let uuid = UUID(uuidString: idString) else { return nil }
        return find(id: uuid)
    }

    /// 按 name 前缀模糊匹配(autocomplete 用)。大小写不敏感。
    static func match(prefix: String) -> [Builder] {
        let lower = prefix.lowercased()
        guard !lower.isEmpty else { return load() }
        return load().filter { $0.name.lowercased().hasPrefix(lower) }
    }

    /// 一键清空(SettingsView 的 nukeEverything 用)。
    /// 同时清空 Contacts。
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
        ContactsStorage.clearAll()
    }

    // MARK: - 迁移辅助(仅 ContactsStorage 使用)

    /// 读老格式 JSON(含 company/email/phone)。专门给迁移用,正常代码不要用。
    static func loadRaw() -> [LegacyBuilder] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([LegacyBuilder].self, from: data)) ?? []
    }

    /// 覆盖保存(简化版,跳 add 校验)。专门给迁移把"被改成公司"的 Builder 写回去。
    @discardableResult
    static func saveRaw(_ items: [Builder]) -> Bool {
        save(items)
    }

    /// 老 Builder 的全字段镜像 — 仅用于读旧 JSON,迁移完后丢弃。
    struct LegacyBuilder: Codable {
        let id: UUID
        var name: String
        var company: String
        var email: String
        var phone: String
        var notes: String

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(UUID.self, forKey: .id)
            self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            self.company = try c.decodeIfPresent(String.self, forKey: .company) ?? ""
            self.email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
            self.phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
            self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        }

        enum CodingKeys: String, CodingKey {
            case id, name, company, email, phone, notes
        }
    }
}
