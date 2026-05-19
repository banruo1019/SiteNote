//
//  SitePresetEditorView.swift
//  SiteNote
//
//  工地预设编辑器(Engineer 专用)。
//  把"工地"和工程师常用项目信息绑定:导出 Inspection 报告时,Header 字段
//  按 siteTag 自动 prefill(projectName / projectNo / clientName / address / attn / inspectionType)。
//
//  结构参考 BuildersEditorView:Form 列表 + sheet 编辑;swipe 删除;EditButton 拖动;
//  右上角 + 新建。每个 siteTag 唯一一条预设(SitePresetStorage.add 自动处理)。
//

import SwiftUI
import SwiftData

struct SitePresetEditorView: View {
    /// 当前展示的预设列表。
    @State private var presets: [SitePreset] = SitePresetStorage.load()

    /// 添加 / 编辑 sheet 状态。
    @State private var editing: SitePresetEditingTarget? = nil

    /// 通用 alert(超上限等)。
    @State private var alertMessage: String? = nil

    private var locale: Locale { AppLanguageManager.currentLocale }

    var body: some View {
        Form {
            if presets.isEmpty {
                Section {
                    Text(String(localized: "还没有工地预设。点右上角「添加」加一个试试。", locale: locale))
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.fgDim)
                }
            } else {
                Section {
                    ForEach(presets) { preset in
                        Button {
                            editing = .edit(preset)
                        } label: {
                            row(for: preset)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                remove(preset)
                            } label: {
                                Label(String(localized: "删除", locale: locale),
                                      systemImage: "trash")
                            }
                        }
                    }
                    // R3#10:onMove 之前 no-op(SitePresetStorage 按 createdAt 排,save 不写 sortIndex)
                    // → 删 reorder UI 避免误导,直到加 sortIndex 字段。
                } header: {
                    SectionHeader(String(localized: "工地预设 (\(presets.count))", locale: locale))
                } footer: {
                    SectionFooter(String(
                        localized: "工程师专用。导出 Inspection 报告时,Header 字段从这里自动填入。每个工地一条预设。",
                        locale: locale
                    ))
                }
            }
        }
        .industrialForm()
        .navigationTitle(String(localized: "工地", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !presets.isEmpty {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = .new
                } label: {
                    Label(String(localized: "添加", locale: locale),
                          systemImage: "plus")
                }
                .disabled(presets.count >= SitePresetStorage.maxItems)
            }
        }
        .sheet(item: $editing) { target in
            SitePresetEditSheet(
                target: target,
                onSave: { handleSave($0, target: target) }
            )
        }
        .alert(String(localized: "无法保存", locale: locale),
               isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
               )) {
            Button(String(localized: "知道了", locale: locale), role: .cancel) {
                alertMessage = nil
            }
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear {
            syncFromSiteTagsStorage()
            presets = SitePresetStorage.load()
        }
    }

    /// 把 SiteTagsStorage 里有但 SitePresetStorage 没有的工地补成空 SitePreset。
    /// v1.3:让"工地"页是工地的唯一入口 — 老 siteTag(只有名字)也要能在这里看到/编辑预设。
    private func syncFromSiteTagsStorage() {
        let allSiteTags = SiteTagsStorage.load()
        let presetTags = Set(SitePresetStorage.load().map { $0.siteTag })
        for tag in allSiteTags where !presetTags.contains(tag) {
            let stub = SitePreset(siteTag: tag, address: "")
            _ = SitePresetStorage.add(stub)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for p: SitePreset) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "building.2")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.siteTag.isEmpty
                     ? String(localized: "(未命名工地)", locale: locale)
                     : p.siteTag)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                let subline = subtitleLine(for: p)
                if !subline.isEmpty {
                    Text(subline)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.dim)
        }
        .contentShape(Rectangle())
    }

    /// 副标题:projectName + projectNo(任一非空就显示)。
    private func subtitleLine(for p: SitePreset) -> String {
        var parts: [String] = []
        if !p.projectName.isEmpty { parts.append(p.projectName) }
        if !p.projectNo.isEmpty { parts.append("#\(p.projectNo)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private func remove(_ p: SitePreset) {
        SitePresetStorage.remove(id: p.id)
        // 同步从 SiteTagsStorage 删 siteTag,否则下次 onAppear syncFromSiteTagsStorage
        // 会把这个孤儿 tag 补成空 preset 复活。Note.siteTag 历史引用不动 — 那是预期的。
        if !p.siteTag.isEmpty {
            _ = SiteTagsStorage.remove(p.siteTag)
        }
        presets = SitePresetStorage.load()
    }

    // R3#10:movePresets 删除 — onMove 之前是 no-op(SitePresetStorage 按 createdAt 排序,
    // save() 不写 sortIndex)。删 UI 避免用户做"看起来生效但不生效"的拖拽。
    // 若以后要支持自定义排序,需要给 SitePreset 加 `var sortIndex: Int` + 修改 load() 排序逻辑。

    @discardableResult
    private func handleSave(_ draft: SitePreset, target: SitePresetEditingTarget) -> Bool {
        switch target {
        case .new:
            guard presets.count < SitePresetStorage.maxItems else {
                alertMessage = String(
                    localized: "已达 \(SitePresetStorage.maxItems) 条上限,删一些再加。",
                    locale: locale
                )
                return false
            }
            // SitePresetStorage.add 自动处理同 siteTag 更新。
            if SitePresetStorage.add(draft) == nil {
                alertMessage = String(localized: "保存失败:工地标签不能为空。", locale: locale)
                return false
            }
        case .edit:
            if !SitePresetStorage.update(draft) {
                alertMessage = String(localized: "保存失败:找不到原条目。", locale: locale)
                return false
            }
        }
        presets = SitePresetStorage.load()
        editing = nil
        return true
    }
}

// MARK: - Editing target

enum SitePresetEditingTarget: Identifiable {
    case new
    case edit(SitePreset)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let p): return p.id.uuidString
        }
    }

    var editingID: UUID? {
        switch self {
        case .new: return nil
        case .edit(let p): return p.id
        }
    }

    var initial: SitePreset {
        switch self {
        case .new: return SitePreset()
        case .edit(let p): return p
        }
    }
}

// MARK: - Edit sheet

private struct SitePresetEditSheet: View {
    let target: SitePresetEditingTarget
    let onSave: (SitePreset) -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // A2:接通真实团队。@Query 自动随 SwiftData CloudKit 同步刷新。
    //   - teams:本机最多 1 个团队(memory 决议:简单模型);用 .first 拿当前团队。
    //   - teamMembers:所有 member,在 currentTeamMembers 里按 teamID 过滤。
    @Query(sort: \Team.createdAt) private var teams: [Team]
    @Query(sort: \TeamMember.joinedAt) private var teamMembers: [TeamMember]

    // 工地标签(siteTag):
    // - 新建模式:不再让用户单独输入,保存时 siteTag = address(地址即工地标签)。
    // - 编辑模式:已有 siteTag 在历史 Note 上有引用,只读展示,不允许改(避免断关联)。
    @State private var siteTag: String

    // 项目信息
    @State private var projectName: String
    @State private var projectNo: String
    @State private var clientName: String
    @State private var address: String

    // 默认值
    @State private var defaultAttn: String
    /// [Deprecated v1.4] 老的"默认 Builder" picker 已删,字段保留用于回写 draft(向后兼容)。
    @State private var defaultBuilderID: UUID?
    @State private var defaultInspectionType: String

    // v1.4 本工地联系人:linked 是 superset,defaultRecipient ⊆ linked。
    // v1.5:从指向 Builder.id 改成指向 Contact.id(两级联系簿)。
    @State private var linkedContactIDs: [UUID]
    @State private var defaultRecipientIDs: [UUID]
    @State private var availableContacts: [Contact] = []
    @State private var availableBuilders: [Builder] = []
    @State private var showsAddContactSheet: Bool = false
    /// 从已有 Contacts 选已存在的联系人加到本工地(不新建)。
    @State private var showsLinkExistingSheet: Bool = false
    /// 「+ 新建公司」弹窗(在 clientName Menu 里点)。
    @State private var showsAddCompanySheet: Bool = false
    /// 用户手动改过 projectName 后,address 联动停止;新建模式默认 false 让 address → projectName 自动同步。
    @State private var userEditedProjectName: Bool = false

    // 备注
    @State private var notes: String

    // 分配(A2:接通真实团队 — 见下方 assignmentSection)。
    @State private var assignedToUserID: String?
    @State private var assignedAt: Date?

    @State private var errorMessage: String?

    /// R6#4:跟踪是否成功 save。Cancel 时(.onDisappear hasSaved=false)清掉 .new 模式下
    /// 提前写到 SiteTagsStorage 的 orphan tag(那是 FloorPlanManageView NavigationLink onAppear
    /// 临时占位的副作用)。
    @State private var hasSavedSuccessfully: Bool = false

    private var locale: Locale { AppLanguageManager.currentLocale }

    init(target: SitePresetEditingTarget,
         onSave: @escaping (SitePreset) -> Bool) {
        self.target = target
        self.onSave = onSave
        let initial = target.initial
        _siteTag = State(initialValue: initial.siteTag)
        _projectName = State(initialValue: initial.projectName)
        _projectNo = State(initialValue: initial.projectNo)
        _clientName = State(initialValue: initial.clientName)
        _address = State(initialValue: initial.address)
        _defaultAttn = State(initialValue: initial.defaultAttn)
        _defaultBuilderID = State(initialValue: initial.defaultBuilderID)
        _defaultInspectionType = State(initialValue: initial.defaultInspectionType)
        _notes = State(initialValue: initial.notes)
        _assignedToUserID = State(initialValue: initial.assignedToUserID)
        _assignedAt = State(initialValue: initial.assignedAt)
        // v1.4 本工地联系人:从 SitePreset 直接读;onAppear 再刷新 availableContacts。
        _linkedContactIDs = State(initialValue: initial.linkedContactIDs)
        _defaultRecipientIDs = State(initialValue: initial.defaultRecipientIDs)
        // 编辑模式 / 新建模式有初始 projectName → 视为用户已编辑过,不再被 address 覆盖。
        _userEditedProjectName = State(initialValue: !initial.projectName.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                siteSection
                projectInfoSection
                contactsSection
                floorPlansSection
                assignmentSection
                notesSection

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                }
            }
            .onDisappear {
                // **R6#4 + R7#2 修正**:新建模式 Cancel 时清掉 FloorPlanManageView 写入的 orphan tag。
                // 之前用 `siteTag` 字段做对比是错的:新建模式下 siteTag @State 永远为空,
                // 真正写入 SiteTagsStorage 的是 `effectiveSiteTag`(从 address 派生)。
                // 改:用 effectiveSiteTag 作为 leak 比对。
                if case .new = target,
                   !hasSavedSuccessfully {
                    let leaked = effectiveSiteTag.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !leaked.isEmpty,
                       SitePresetStorage.find(siteTag: leaked) == nil {
                        _ = SiteTagsStorage.remove(leaked)
                    }
                }
            }
            .industrialForm()
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "取消", locale: locale)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "保存", locale: locale)) {
                        attemptSave()
                    }
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showsAddContactSheet) {
                // 新增联系人:可能也会一并创建新公司(若 clientName 找不到匹配的 Builder)。
                // 加进来就直接当收件人(默认勾选)— 不再保留"默认"二级开关。
                AddContactSheet(company: clientName) { newContact, _ in
                    availableContacts = ContactsStorage.load()
                    availableBuilders = BuildersStorage.load()
                    if !linkedContactIDs.contains(newContact.id) {
                        linkedContactIDs.append(newContact.id)
                    }
                    if !defaultRecipientIDs.contains(newContact.id) {
                        defaultRecipientIDs.append(newContact.id)
                    }
                }
            }
            .sheet(isPresented: $showsLinkExistingSheet) {
                LinkExistingContactsSheet(
                    candidates: unlinkedContacts,
                    builders: availableBuilders,
                    currentCompany: clientName.trimmingCharacters(in: .whitespacesAndNewlines)
                ) { pickedIDs in
                    for id in pickedIDs where !linkedContactIDs.contains(id) {
                        linkedContactIDs.append(id)
                        // 收件人 = 联系人:加进来就默认勾选
                        if !defaultRecipientIDs.contains(id) {
                            defaultRecipientIDs.append(id)
                        }
                    }
                }
            }
            .sheet(isPresented: $showsAddCompanySheet) {
                AddCompanyMiniSheet { newName in
                    // 写通讯录 + 立即选中作为本工地的客户
                    let b = Builder(name: newName)
                    _ = BuildersStorage.add(b)
                    availableBuilders = BuildersStorage.load()
                    clientName = newName
                }
            }
            .onAppear {
                // 每次出现都重新读,确保从其他入口加的新联系人能看到。
                availableContacts = ContactsStorage.load()
                availableBuilders = BuildersStorage.load()
            }
        }
    }

    // MARK: - Sections

    /// 工地段:
    /// - 新建模式:直接输入"工地地址",自动联想(MKLocalSearchCompleter)。
    ///   保存时 siteTag = address(地址即工地标签),省掉再起名字这一步。
    /// - 编辑模式:siteTag 在历史 Note 上已有引用,只读展示;下方依然是地址自动补全。
    private var siteSection: some View {
        Section {
            AddressAutocompleteField(
                text: $address,
                placeholder: LocalizedStringKey(
                    String(localized: "搜地址,例 123 Sample St Sydney", locale: locale)
                )
            )

            // 编辑模式:把 siteTag 作为副信息显示在地址下方,提示用户它不可改。
            if case .edit = target, !siteTag.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Ink.fgDim)
                    Text(String(localized: "标签 \(siteTag) 已锁定", locale: locale))
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                    Spacer()
                }
            }
        } header: {
            SectionHeader(String(localized: "工地", locale: locale))
        }
    }

    private var projectInfoSection: some View {
        Section {
            TextField(
                String(localized: "项目名", locale: locale),
                text: $projectName
            )
            .textInputAutocapitalization(.words)
            .onChange(of: projectName) { _, newValue in
                let trimmedAddr = address.trimmingCharacters(in: .whitespacesAndNewlines)
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedAddr {
                    userEditedProjectName = true
                }
            }
            .onChange(of: address) { _, newAddr in
                let trimmedAddr = newAddr.trimmingCharacters(in: .whitespacesAndNewlines)
                if !userEditedProjectName, !trimmedAddr.isEmpty {
                    projectName = trimmedAddr
                }
            }

            TextField(
                String(localized: "项目编号", locale: locale),
                text: $projectNo
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            // 客户 = 公司 picker:从 BuildersStorage 选,不让手输,保证三级关联(公司→工地→联系人)。
            clientPickerRow

            TextField(
                String(localized: "默认巡检类型(如 level 1 reo)", locale: locale),
                text: $defaultInspectionType
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
            SectionHeader(String(localized: "项目", locale: locale))
        }
    }

    /// 客户(公司)选择行 — Menu 列出 availableBuilders + 「+ 新建公司」+ 「清除」。
    private var clientPickerRow: some View {
        Menu {
            ForEach(availableBuilders) { b in
                Button {
                    clientName = b.name
                } label: {
                    if b.name == clientName {
                        Label(b.name, systemImage: "checkmark")
                    } else {
                        Text(b.name)
                    }
                }
            }
            if !availableBuilders.isEmpty {
                Divider()
            }
            Button {
                showsAddCompanySheet = true
            } label: {
                Label(String(localized: "新建公司", locale: locale), systemImage: "plus.circle")
            }
            if !clientName.isEmpty {
                Divider()
                Button(role: .destructive) {
                    clientName = ""
                } label: {
                    Label(String(localized: "清除", locale: locale), systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(String(localized: "客户", locale: locale))
                    .foregroundStyle(Ink.fg)
                Spacer()
                Text(clientName.isEmpty
                     ? String(localized: "选公司", locale: locale)
                     : clientName)
                    .foregroundStyle(clientName.isEmpty ? Ink.fgDim : Ink.fg)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.dim)
            }
            .contentShape(Rectangle())
        }
    }

    // defaultsSection 已合并到 projectInfoSection(默认巡检类型);
    // defaultAttn 字段不再展示,save 时自动取第一个联系人的 name。

    // MARK: - 本工地联系人 (v1.4)

    /// 当前 linkedContactIDs 对应的 Contact 对象(过滤后保持 linkedContactIDs 中的顺序)。
    /// 联系人本体由 ContactsStorage 管;这里只决定本工地用谁。
    private var linkedContacts: [Contact] {
        let byID = Dictionary(uniqueKeysWithValues: availableContacts.map { ($0.id, $0) })
        return linkedContactIDs.compactMap { byID[$0] }
    }

    /// 还没绑到本工地的 Contact 候选 — 供「从已有选」sheet 列出来。
    /// **三级关系强制**:工地预设若设了 clientName(公司),候选只显示属于该公司的 Contact;
    /// clientName 没匹配的 Builder(用户手输了通讯录里没有的公司)→ 返回空 → LinkSheet
    /// 引导用户「新建联系人」(顺手新建该公司)。clientName 为空时不过滤(向后兼容)。
    private var unlinkedContacts: [Contact] {
        let linked = Set(linkedContactIDs)
        let pool = availableContacts.filter { !linked.contains($0.id) }
        let trimmedClient = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClient.isEmpty else { return pool }
        let companyBuilderIDs: Set<UUID> = Set(
            availableBuilders
                .filter { $0.name.caseInsensitiveCompare(trimmedClient) == .orderedSame }
                .map { $0.id }
        )
        guard !companyBuilderIDs.isEmpty else { return [] }
        return pool.filter { companyBuilderIDs.contains($0.builderID) }
    }

    /// 通过 Contact.builderID 反查公司名,用于在 row 上显示"<公司名>"副标题。
    private func companyName(for contact: Contact) -> String {
        availableBuilders.first(where: { $0.id == contact.builderID })?.name ?? ""
    }

    private var contactsSection: some View {
        Section {
            if linkedContacts.isEmpty {
                Text(String(localized: "未添加", locale: locale))
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.fgDim)
            } else {
                ForEach(linkedContacts) { contact in
                    contactRow(contact)
                }
                .onDelete { idxSet in
                    // 仅从本工地解绑(不删除 Contact 本体),defaultRecipientIDs 同步删 — 合并后两者等同。
                    let idsToRemove = idxSet.map { linkedContacts[$0].id }
                    linkedContactIDs.removeAll { idsToRemove.contains($0) }
                    defaultRecipientIDs.removeAll { idsToRemove.contains($0) }
                }
            }
            Menu {
                Button {
                    showsLinkExistingSheet = true
                } label: {
                    Label(
                        String(localized: "从已有联系人选", locale: locale),
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                }
                .disabled(unlinkedContacts.isEmpty)
                Button {
                    showsAddContactSheet = true
                } label: {
                    Label(
                        String(localized: "新建联系人", locale: locale),
                        systemImage: "person.crop.circle.badge.plus"
                    )
                }
            } label: {
                Label(
                    String(localized: "加联系人", locale: locale),
                    systemImage: "plus.circle"
                )
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
            }
        } header: {
            SectionHeader(String(
                localized: "收件人 (\(linkedContacts.count))",
                locale: locale
            ))
        }
    }

    /// 单行联系人:纯展示行(合并后不再有"默认 vs 非默认"二级开关)。
    @ViewBuilder
    private func contactRow(_ contact: Contact) -> some View {
        let company = companyName(for: contact)
        HStack(spacing: 12) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 14))
                .foregroundStyle(Ink.fgDim)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(contact.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.fg)
                    if !company.isEmpty {
                        Text("· \(company)")
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
                if !contact.email.isEmpty {
                    Text(contact.email)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    // MARK: - 分配 (A2:真实团队)

    /// 当前用户 CloudKit userRecordName(""=未登 iCloud / 单机)。
    private var currentUserID: String {
        ICloudSyncConfig.shared.currentUserRecordName ?? ""
    }

    /// 当前(唯一)团队 — 本机最多 1 个,见 TeamManagementView 的 currentTeam 同款逻辑。
    private var currentTeam: Team? {
        teams.filter { $0.deletedAt == nil }.first
    }

    /// 当前团队的全部成员(按 teamID 过滤)。
    private var currentTeamMembers: [TeamMember] {
        guard let t = currentTeam else { return [] }
        return teamMembers.filter { $0.teamID == t.id }
            .sorted { $0.joinedAt < $1.joinedAt }
    }

    /// 当前用户是否本团队 Owner — 决定显示分配 UI 还是只读 chip。
    private var isOwner: Bool {
        guard let t = currentTeam, !currentUserID.isEmpty else { return false }
        return t.ownerUserID == currentUserID
    }

    /// 按 userID 反查 member,用于显示 displayName。
    private func member(for userID: String?) -> TeamMember? {
        guard let uid = userID, !uid.isEmpty else { return nil }
        return currentTeamMembers.first { $0.userID == uid }
    }

    /// "已分配 / 未分配"状态文案。
    private var assignmentStatusText: String {
        if let uid = assignedToUserID, !uid.isEmpty {
            if let m = member(for: uid) {
                return String(localized: "已分配给 \(m.displayName)", locale: locale)
            }
            // 老分配但 member 已离队 — 兜底显示 userID 后 6 位避免空白。
            let suffix = String(uid.suffix(6))
            return String(localized: "已分配给(已离队成员 …\(suffix))", locale: locale)
        }
        return String(localized: "未分配 / 团队公用", locale: locale)
    }

    private var assignmentSection: some View {
        Section {
            // 顶部状态行 — 不论 Owner / Member 都展示。
            HStack(spacing: 8) {
                Image(systemName: assignedToUserID == nil
                      ? "person.crop.circle.dashed"
                      : "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
                Text(assignmentStatusText)
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.fg)
                Spacer()
                if let at = assignedAt {
                    Text(at.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                }
            }

            if currentTeam == nil {
                // 没建团队 — 解释为啥不能分配,引导到团队页。
                Text(String(localized: "先在「团队」里建一个团队,才能把工地分配给成员。", locale: locale))
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.fgDim)
            } else if isOwner {
                // Owner 视角:可选 member 或清除。
                Picker(
                    String(localized: "分配给", locale: locale),
                    selection: Binding(
                        get: { assignedToUserID },
                        set: { newID in assignToMember(newID) }
                    )
                ) {
                    Text(String(localized: "未分配 / 团队公用", locale: locale))
                        .tag(String?.none)
                    ForEach(currentTeamMembers, id: \.userID) { m in
                        Text(m.displayName.isEmpty ? m.email : m.displayName)
                            .tag(Optional(m.userID))
                    }
                }
                .font(.system(size: DesignTokens.FontSize.body))
            } else {
                // Member 视角:只读,看不到 picker。
                Text(String(localized: "只有团队 Owner 可以分配工地。", locale: locale))
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.fgDim)
            }
        } header: {
            SectionHeader(String(localized: "分配", locale: locale))
        } footer: {
            SectionFooter(String(
                localized: "Owner 分配工地给成员后,自动在该成员的「日程」里建一条今天的访问条目(可后续改时间)。取消分配不会删已建日程。",
                locale: locale
            ))
        }
    }

    /// 处理分配 / 取消分配。
    /// 这里只更新 sheet 本地状态;真正创建 SiteVisitSchedule 必须等用户点「保存」后做,
    /// 否则「取消」无法回滚已经插入/镜像出去的日程。
    private func assignToMember(_ memberUserID: String?) {
        let normalized = normalizedUserID(memberUserID)
        guard normalized != assignedToUserID else { return }
        assignedToUserID = normalized
        assignedAt = normalized == nil ? nil : Date()
    }

    private func normalizedUserID(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    private func createOrUpdateAssignmentSchedule(target: String, siteTag: String, titleSource: String) {
        let siteForSchedule = siteTag
        let trimmedTitle = titleSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheduleTitle = trimmedTitle.isEmpty ? siteForSchedule : trimmedTitle
        // 默认今天 09:00(本地时区),user 后续可在「日程」页改时间。
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let nineAm = cal.date(bySettingHour: 9, minute: 0, second: 0, of: today) ?? today

        // **去重**:之前 assignToMember 每次都 insert 新 schedule,导致改分配 / 切人 / 给自己分配
        // 会出现多条同 site 的重复巡检。改:先 fetch 同 site 同日期未完成的 schedule —
        // 有就 update assignedToUserID(改派),无再 insert。
        let dayStart = today
        let dayEnd = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let normalizedSiteTag: String? = siteForSchedule.isEmpty ? nil : siteForSchedule
        let existing: SiteVisitSchedule? = try? modelContext.fetch(FetchDescriptor<SiteVisitSchedule>(
            predicate: #Predicate<SiteVisitSchedule> { s in
                s.deletedAt == nil
                    && s.siteTag == normalizedSiteTag
                    && s.scheduledDate >= dayStart
                    && s.scheduledDate < dayEnd
                    && s.statusRaw != "completed"
            }
        )).first

        let schedule: SiteVisitSchedule
        if let existing {
            existing.assignedToUserID = target
            existing.title = scheduleTitle
            if existing.scheduledTime == nil { existing.scheduledTime = nineAm }
            schedule = existing
        } else {
            schedule = SiteVisitSchedule(
                scheduledDate: today,
                scheduledTime: nineAm,
                siteTag: normalizedSiteTag,
                title: scheduleTitle,
                assignedToUserID: target
            )
            modelContext.insert(schedule)
        }
        do {
            try modelContext.save()
        } catch {
            print("[SitePresetEditor] assignToMember save failed:", error)
        }
        // 团队 mirror:schedule 镜像到 share zone; preset 已由 onSave/SitePresetStorage 镜像。
        let ctx = modelContext
        Task { await TeamDataMirrorService.shared.mirrorSchedule(schedule, in: ctx) }
    }

    /// 平面图段:从 settings 主页搬下来 — 平面图是 per-site 资源,工地详情页才是它的归属。
    /// v1.6:新建模式下也支持上传 — lockedSite 用 effectiveSiteTag(新建模式 = trimmedAddress,
    /// 编辑模式 = 已保存的 siteTag)。地址还没填时 NavigationLink 禁用并提示「先填工地地址」。
    private var floorPlansSection: some View {
        Section {
            if effectiveSiteTag.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "map")
                        .foregroundStyle(Ink.fgDim)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "平面图", locale: locale))
                            .font(.system(size: DesignTokens.FontSize.body))
                            .foregroundStyle(Ink.fgDim)
                        Text(String(localized: "先填工地地址,再上传图纸", locale: locale))
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
            } else {
                NavigationLink {
                    FloorPlanManageView(lockedSite: effectiveSiteTag)
                        .onAppear {
                            // 新建模式下用户还没 Save 工地预设。先把 siteTag 写进 SiteTagsStorage,
                            // 这样 FloorPlanManageView 上传的图纸有合法 site 归属;否则上传完图纸
                            // 但用户取消 Save 时,图纸成孤儿。SitePreset 仍只有 Save 才写入。
                            SiteTagsStorage.add(effectiveSiteTag)
                        }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "map")
                            .foregroundStyle(Ink.fg)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "平面图", locale: locale))
                                .font(.system(size: DesignTokens.FontSize.body))
                            Text(String(localized: "标注隐患位置,GPS 匹配 10 倍精度", locale: locale))
                                .font(.system(size: 11))
                                .foregroundStyle(Ink.fgDim)
                        }
                    }
                }
            }
        } header: {
            SectionHeader(String(localized: "平面图", locale: locale))
        } footer: {
            SectionFooter(String(
                localized: "录音可在图上标记位置,比 GPS 的地址精度高 10 倍。",
                locale: locale
            ))
        }
    }

    private var notesSection: some View {
        Section {
            TextField(
                String(localized: "备注(可选)", locale: locale),
                text: $notes,
                axis: .vertical
            )
            .lineLimit(2...5)
        } header: {
            SectionHeader(String(localized: "备注", locale: locale))
        }
    }

    // MARK: - Save

    private var navTitle: String {
        switch target {
        case .new: return String(localized: "新建工地预设", locale: locale)
        case .edit: return String(localized: "编辑工地预设", locale: locale)
        }
    }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 实际要存进 SitePreset 的 siteTag。
    /// - 新建模式:siteTag = address(地址即工地标签)。
    /// - 编辑模式:沿用已有的 siteTag(只读),不允许改,避免断历史 Note 关联。
    private var effectiveSiteTag: String {
        switch target {
        case .new:
            return trimmedAddress
        case .edit:
            return siteTag.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var canSave: Bool {
        !effectiveSiteTag.isEmpty
    }

    private func attemptSave() {
        let finalTag = effectiveSiteTag
        guard !finalTag.isEmpty else {
            errorMessage = String(localized: "请输入工地地址。", locale: locale)
            return
        }

        let initialAssignedToUserID = normalizedUserID(target.initial.assignedToUserID)
        let finalAssignedToUserID = normalizedUserID(assignedToUserID)
        let shouldCreateAssignmentSchedule = finalAssignedToUserID != nil
            && finalAssignedToUserID != initialAssignedToUserID

        var draft = target.initial  // 保留 id(编辑时)
        draft.siteTag = finalTag
        draft.projectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.projectNo = projectNo.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.clientName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.address = trimmedAddress
        // **R6#6 + R7#3 + R8#1 修正**:defaultAttn UI 不展示,推导规则:
        // - 有 linkedContacts → 用第一个
        // - 无 linkedContacts:
        //   - .new 模式 → ""(用户没填过任何 contacts)
        //   - .edit 模式 + initial 也无 contacts → 保留 target.initial.defaultAttn(legacy 手填值不破)
        //   - .edit 模式 + initial 有 contacts 但当前清空 → "" (用户主动清,意图明确)
        let derivedAttn: String
        if let first = linkedContacts.first {
            derivedAttn = first.name.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if case .edit = target, target.initial.linkedContactIDs.isEmpty {
            // legacy preset 无 contacts + 手填 defaultAttn → 保留
            derivedAttn = target.initial.defaultAttn
        } else {
            derivedAttn = ""
        }
        draft.defaultAttn = derivedAttn
        draft.defaultBuilderID = defaultBuilderID
        draft.defaultInspectionType = defaultInspectionType.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.assignedToUserID = assignedToUserID
        draft.assignedAt = assignedAt
        // v1.6:合并语义 — defaultRecipientIDs ≡ linkedContactIDs(收件人 = 联系人,
        // 加进来就默认勾选)。仍写两个字段是为了向后兼容老代码读 defaultRecipientIDs。
        draft.linkedContactIDs = linkedContactIDs
        draft.defaultRecipientIDs = linkedContactIDs

        guard onSave(draft) else { return }
        hasSavedSuccessfully = true  // R6#4 标记 save 成功,.onDisappear 不清 orphan
        // 新建模式:保存成功后同步写一份 SiteTagsStorage,让 Note.siteTag autocomplete /
        // 历史 site 列表 / 其他 picker 都能立刻看到新工地。
        if case .new = target {
            SiteTagsStorage.add(finalTag)
        }
        if shouldCreateAssignmentSchedule, let targetUserID = finalAssignedToUserID {
            createOrUpdateAssignmentSchedule(
                target: targetUserID,
                siteTag: finalTag,
                titleSource: draft.projectName
            )
        }
        dismiss()
    }
}

// MARK: - 从已有联系人选

/// "把已存在的 Contact link 到本工地"的 bottom sheet。
/// 工作流补全:之前只能新建联系人,导致已经在通讯录里的也得重输一遍。
///
/// - candidates:还没绑到本工地的全部 Contact(在 caller 端先过滤)
/// - builders:用于行内显示"公司"副标
/// - onPicked:用户点完成后回传选中的 Contact.id 数组,caller append 到 linkedContactIDs
private struct LinkExistingContactsSheet: View {
    let candidates: [Contact]
    let builders: [Builder]
    /// 当前工地预设的 clientName。非空 = 候选已被 caller 按这家公司过滤过;
    /// 用于 navtitle 副标 + 空态文案;空 = 没设公司,候选全展示。
    let currentCompany: String
    var onPicked: ([UUID]) -> Void

    @Environment(\.dismiss) private var dismiss
    /// **R11 修**:Set 无序导致点完成后回传 linkedContactIDs 顺序乱 → derivedAttn picks 错的第一个。
    /// 改用有序 `[UUID]`(append/remove 维护用户点选顺序)。
    @State private var selectedIDs: [UUID] = []
    @State private var searchText: String = ""

    private var locale: Locale { AppLanguageManager.currentLocale }

    /// 空态文案 — 看公司是否设过来决定提示语,引导用户去「新建联系人」。
    private var emptyStateText: String {
        if currentCompany.isEmpty {
            return String(localized: "通讯录里还没别的联系人 — 用「新建联系人」加一个。", locale: locale)
        }
        return String(localized: "「\(currentCompany)」名下还没联系人 — 用「新建联系人」加一个,公司会自动设为此项。", locale: locale)
    }

    /// 按公司分组 → 同公司联系人聚在一起,符合用户心智。
    private var grouped: [(company: String, contacts: [Contact])] {
        let byID = Dictionary(uniqueKeysWithValues: builders.map { ($0.id, $0) })
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = q.isEmpty ? candidates : candidates.filter {
            $0.name.lowercased().contains(q)
                || $0.email.lowercased().contains(q)
                || (byID[$0.builderID]?.name.lowercased().contains(q) ?? false)
        }
        let groups = Dictionary(grouping: filtered) { (c: Contact) -> String in
            byID[c.builderID]?.name ?? String(localized: "未分组", locale: AppLanguageManager.currentLocale)
        }
        return groups.keys.sorted().map { name in
            (company: name, contacts: groups[name]!.sorted { $0.name < $1.name })
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if candidates.isEmpty {
                    Section {
                        Text(emptyStateText)
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.fgDim)
                    }
                } else {
                    if !currentCompany.isEmpty {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "building.2")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Ink.fgDim)
                                Text(String(localized: "只显示「\(currentCompany)」的联系人", locale: locale))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Ink.fgDim)
                            }
                        }
                    }
                    ForEach(grouped, id: \.company) { group in
                        Section {
                            ForEach(group.contacts) { contact in
                                row(contact)
                            }
                        } header: {
                            SectionHeader(group.company)
                        }
                    }
                }
            }
            .industrialForm()
            .searchable(text: $searchText, prompt: Text(String(localized: "搜索姓名 / 邮箱", locale: locale)))
            .navigationTitle(String(localized: "选联系人", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", locale: locale)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        // R11:selectedIDs 是 [UUID](有序),直接回传保留用户点选顺序
                        onPicked(selectedIDs)
                        dismiss()
                    } label: {
                        Text(selectedIDs.isEmpty
                             ? String(localized: "完成", locale: locale)
                             : String(localized: "完成 (\(selectedIDs.count))", locale: locale))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ contact: Contact) -> some View {
        let isSelected = selectedIDs.contains(contact.id)
        Button {
            if let idx = selectedIDs.firstIndex(of: contact.id) {
                selectedIDs.remove(at: idx)
            } else {
                selectedIDs.append(contact.id)  // 保留点选顺序
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Ink.fg : Ink.fgDim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name.isEmpty ? String(localized: "(无名)", locale: locale) : contact.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                    if !contact.email.isEmpty {
                        Text(contact.email)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.fgDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 新建公司迷你 sheet

/// 在 clientName Picker 里点「+ 新建公司」时弹出,只输公司名,保存即写入 BuildersStorage。
/// 设计意图:避免在工地预设流程里跳出去到 Settings 加公司再返回,保持上下文。
private struct AddCompanyMiniSheet: View {
    var onAdded: (_ name: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @FocusState private var focused: Bool

    private var locale: Locale { AppLanguageManager.currentLocale }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "公司名(如 Acme Construction)", locale: locale), text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focused)
                } footer: {
                    SectionFooter(String(localized: "保存后会写入「通讯录 → 公司」,本工地的客户字段自动选中。后续可在通讯录里加这家公司的联系人。", locale: locale))
                }
            }
            .industrialForm()
            .navigationTitle(String(localized: "新建公司", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", locale: locale)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !trimmed.isEmpty else { return }
                        onAdded(trimmed)
                        dismiss()
                    } label: {
                        Text(String(localized: "保存", locale: locale))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
            .presentationDetents([.height(220)])
        }
    }
}
