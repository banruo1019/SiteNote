//
//  ContactsStorage.swift
//  SiteNote
//
//  联系人簿(两级结构第 2 级)。
//  上层是 Builder(公司,见 BuildersStorage),下层是 Contact(具体联系人,
//  绑公司)。每条 Contact 必须 belongsTo 一个 Builder。
//
//  数据模型:
//      Builder { id, name(公司名), notes }
//      Contact { id, builderID, name, email, phone, notes }
//
//  存 UserDefaults JSON(条目少,几十-几百)。
//
//  老数据迁移:旧的 Builder(name/email/phone/company)→ 把 company 当 Builder.name,
//  把 name/email/phone 写成一条 Contact 挂在上面。同 company 合并到一个 Builder 下。
//  详见 `migrateFromBuilderLegacyOnce()`。
//

import Foundation

/// 一个具体联系人(属于某个 Builder/公司)。
struct Contact: Codable, Identifiable, Hashable {
    let id: UUID
    /// 所属 Builder.id(公司)。必填——不允许"无公司"的孤儿联系人。
    var builderID: UUID
    var name: String
    var email: String
    var phone: String
    var notes: String

    init(
        id: UUID = UUID(),
        builderID: UUID,
        name: String = "",
        email: String = "",
        phone: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.builderID = builderID
        self.name = name
        self.email = email
        self.phone = phone
        self.notes = notes
    }
}

enum ContactsStorage {
    private static let key = "settings.contacts.v1"
    /// 上限。每个公司 ~5 联系人 × 200 公司 = 1000 已经够 small business。
    static let maxItems = 1000

    /// 一次性迁移 flag —— migrateFromBuilderLegacyOnce 跑过后写 true。
    private static let migrationDoneKey = "settings.contacts.migrationFromBuilderLegacy.done"

    // MARK: - CRUD

    static func load() -> [Contact] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Contact].self, from: data)) ?? []
    }

    @discardableResult
    static func save(_ items: [Contact]) -> Bool {
        let capped = items.count > maxItems ? Array(items.prefix(maxItems)) : items
        guard let data = try? JSONEncoder().encode(capped) else { return false }
        UserDefaults.standard.set(data, forKey: key)
        return true
    }

    /// 新增联系人。name 空拒绝(email 可以为空,有时只记电话)。
    /// 必须有合法 builderID。
    @discardableResult
    static func add(_ contact: Contact) -> UUID? {
        let trimmedName = contact.name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        var all = load()
        guard all.count < maxItems else { return nil }
        var entry = contact
        entry.name = trimmedName
        entry.email = contact.email.trimmingCharacters(in: .whitespaces)
        entry.phone = contact.phone.trimmingCharacters(in: .whitespaces)
        all.append(entry)
        return save(all) ? entry.id : nil
    }

    @discardableResult
    static func update(_ contact: Contact) -> Bool {
        var all = load()
        guard let idx = all.firstIndex(where: { $0.id == contact.id }) else { return false }
        all[idx] = contact
        return save(all)
    }

    static func remove(id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        save(all)
    }

    /// 删一个 Builder 时连带删它所有 Contact(BuildersStorage.remove 调用时同步触发)。
    static func removeAll(builderID: UUID) {
        var all = load()
        all.removeAll { $0.builderID == builderID }
        save(all)
    }

    static func find(id: UUID) -> Contact? {
        load().first { $0.id == id }
    }

    static func find(idString: String) -> Contact? {
        guard let uuid = UUID(uuidString: idString) else { return nil }
        return find(id: uuid)
    }

    /// 某公司下的全部 Contact。
    static func find(builderID: UUID) -> [Contact] {
        load().filter { $0.builderID == builderID }
    }

    /// 按 id 列表批量查(保持入参顺序;找不到的 id 跳过)。
    /// SitePreset.linkedContactIDs / defaultRecipientIDs 用。
    static func find(ids: [UUID]) -> [Contact] {
        let byID = Dictionary(uniqueKeysWithValues: load().map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
        // 同时清掉迁移 flag,这样调试时 clear-all 后再加新数据不会被旧迁移误带回。
        UserDefaults.standard.removeObject(forKey: migrationDoneKey)
    }

    // MARK: - 老数据迁移

    /// 一次性把"扁平 Builder"转成"Builder(公司)+ Contact(联系人)"二级结构。
    /// 同步把 SitePreset.linkedContactIDs / defaultRecipientIDs / defaultBuilderID
    /// 里指向老 Builder.id 的 UUID 重映射到对应新 Contact.id。
    ///
    /// idempotent:UserDefaults flag 防重跑。失败 / 没需要迁移 → silently no-op。
    /// 设计原则:只新增 / 改 SitePreset 的 ID 映射,不删老 Builder 数据
    /// (但实际上 Builder 会被覆盖成"公司"语义,旧字段 email/phone 字段对应 decoder 兼容)。
    static func migrateFromBuilderLegacyOnce() {
        if UserDefaults.standard.bool(forKey: migrationDoneKey) {
            return
        }
        defer {
            // 不管成功与否都打标 — 失败一次别每次启动重试拉慢冷启动。
            UserDefaults.standard.set(true, forKey: migrationDoneKey)
        }

        let legacyBuilders = BuildersStorage.loadRaw()
        guard !legacyBuilders.isEmpty else {
            return  // 全新用户没老数据,直接结束
        }

        // 一些老 Builder 可能已经被本次或以前的 build 用作"公司"了,
        // 这里看它有没有 email/phone/name 这些"联系人"字段填了来判断。
        // 如果旧 builder.name 或 email 任一非空 → 它原本是个联系人,需要拆。
        // 全为空(理论上不会,因为老 add() 拒收空 name/email)→ 它已经是纯公司,跳过。

        var existingContacts = load()
        var newContacts: [Contact] = []

        // 公司去重:同名 company 合并到一个 Builder。Key = company 名 trim 后小写。
        // value = "代表 Builder.id"(可能是已有老 Builder.id 直接复用,或新生成)。
        var companyToBuilderID: [String: UUID] = [:]

        // 同时建一个"老 Builder.id → 新 Contact.id"的映射表,后面用于改 SitePreset。
        var legacyBuilderToContactID: [UUID: UUID] = [:]

        var builderUpdates: [Builder] = []  // 累积要替换的 Builder(公司化后的)

        for legacy in legacyBuilders {
            let oldName = legacy.name.trimmingCharacters(in: .whitespaces)
            let oldEmail = legacy.email.trimmingCharacters(in: .whitespaces)
            let oldPhone = legacy.phone.trimmingCharacters(in: .whitespaces)
            let oldCompany = legacy.company.trimmingCharacters(in: .whitespaces)
            let oldNotes = legacy.notes.trimmingCharacters(in: .whitespaces)

            // 公司名兜底:company 非空用 company;否则用 name 顶上(没公司就个体户)。
            let companyName: String = oldCompany.isEmpty ? oldName : oldCompany
            let companyKey = companyName.lowercased()

            // 解析"代表 Builder"。
            let representativeBuilderID: UUID
            if let existing = companyToBuilderID[companyKey] {
                representativeBuilderID = existing
                // 合并到已有公司 — 老的 legacy Builder.id 就成"被合并掉"的。
            } else {
                // 第一次看见这家公司 — 直接复用老 Builder.id(避免改 SitePreset.linkedContactIDs
                // 中那些"指向 Builder.id 但其实指公司"的旧引用变量;实际上指 contact 不指 builder,
                // 但保留 ID 简化推理)。
                representativeBuilderID = legacy.id
                companyToBuilderID[companyKey] = representativeBuilderID
                builderUpdates.append(Builder(id: representativeBuilderID, name: companyName, notes: ""))
            }

            // 给老 Builder 拆出一条 Contact —— 仅当它原本有"联系人字段"(name 或 email/phone 非空)。
            let hasContactFields = !oldName.isEmpty || !oldEmail.isEmpty || !oldPhone.isEmpty
            if hasContactFields {
                let contact = Contact(
                    builderID: representativeBuilderID,
                    name: oldName.isEmpty ? companyName : oldName,
                    email: oldEmail,
                    phone: oldPhone,
                    notes: oldNotes
                )
                // 用 legacy.id 占 key,后面 SitePreset 把 builderID 重映射到 contact.id。
                legacyBuilderToContactID[legacy.id] = contact.id
                newContacts.append(contact)
            }
        }

        // 持久化:Builder 列表覆盖,Contact 列表合并到已有(避免覆盖手动加的)。
        if !builderUpdates.isEmpty {
            BuildersStorage.saveRaw(builderUpdates)
        }
        if !newContacts.isEmpty {
            existingContacts.append(contentsOf: newContacts)
            save(existingContacts)
        }

        // 改 SitePreset:linkedContactIDs / defaultRecipientIDs / defaultBuilderID 三个字段
        // 把指向老 Builder.id 的 UUID → 新 Contact.id。
        var presets = SitePresetStorage.load()
        var presetsChanged = false
        for i in presets.indices {
            var p = presets[i]
            let oldLinked = p.linkedContactIDs
            let newLinked = oldLinked.map { legacyBuilderToContactID[$0] ?? $0 }
            if newLinked != oldLinked {
                p.linkedContactIDs = newLinked
                presetsChanged = true
            }
            let oldDefault = p.defaultRecipientIDs
            let newDefault = oldDefault.map { legacyBuilderToContactID[$0] ?? $0 }
            if newDefault != oldDefault {
                p.defaultRecipientIDs = newDefault
                presetsChanged = true
            }
            // defaultBuilderID:老的指向"被拆掉的 legacy Builder.id" → 用第一个 contact 代替
            if let oldBid = p.defaultBuilderID,
               let newCid = legacyBuilderToContactID[oldBid] {
                p.defaultBuilderID = newCid
                // 顺便把它塞进 arrays(以前没塞进去的情况)
                if !p.linkedContactIDs.contains(newCid) {
                    p.linkedContactIDs.append(newCid)
                }
                if !p.defaultRecipientIDs.contains(newCid) {
                    p.defaultRecipientIDs.append(newCid)
                }
                presetsChanged = true
            }
            presets[i] = p
        }
        if presetsChanged {
            SitePresetStorage.save(presets)
        }
    }
}
