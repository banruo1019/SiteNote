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
                    .onMove(perform: movePresets)
                } header: {
                    Text(String(localized: "工地预设 (\(presets.count))", locale: locale))
                } footer: {
                    Text(String(
                        localized: "工程师专用。导出 Inspection 报告时,Header 字段从这里自动填入。每个工地一条预设。",
                        locale: locale
                    ))
                    .font(.system(size: 12))
                }
            }
        }
        .industrialForm()
        .navigationTitle(String(localized: "工地预设", locale: locale))
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
            presets = SitePresetStorage.load()
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
        presets = SitePresetStorage.load()
    }

    private func movePresets(from source: IndexSet, to destination: Int) {
        var copy = presets
        copy.move(fromOffsets: source, toOffset: destination)
        SitePresetStorage.save(copy)
        presets = SitePresetStorage.load()
    }

    private func handleSave(_ draft: SitePreset, target: SitePresetEditingTarget) {
        switch target {
        case .new:
            guard presets.count < SitePresetStorage.maxItems else {
                alertMessage = String(
                    localized: "已达 \(SitePresetStorage.maxItems) 条上限,删一些再加。",
                    locale: locale
                )
                return
            }
            // SitePresetStorage.add 自动处理同 siteTag 更新。
            if SitePresetStorage.add(draft) == nil {
                alertMessage = String(localized: "保存失败:工地标签不能为空。", locale: locale)
            }
        case .edit:
            if !SitePresetStorage.update(draft) {
                alertMessage = String(localized: "保存失败:找不到原条目。", locale: locale)
            }
        }
        presets = SitePresetStorage.load()
        editing = nil
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
    let onSave: (SitePreset) -> Void

    @Environment(\.dismiss) private var dismiss

    // 工地标签(下拉选 + "新建"入口)
    @State private var siteTag: String
    @State private var siteTags: [String] = SiteTagsStorage.load()
    @State private var showsNewSiteSheet: Bool = false

    // 项目信息
    @State private var projectName: String
    @State private var projectNo: String
    @State private var clientName: String
    @State private var address: String

    // 默认值
    @State private var defaultAttn: String
    @State private var defaultBuilderID: UUID?
    @State private var defaultInspectionType: String
    @State private var builders: [Builder] = BuildersStorage.load()

    // 备注
    @State private var notes: String

    // 分配(Phase 0 mock;Phase 2 改为 @Query TeamMember)
    @State private var assignedToUserID: String?
    @State private var assignedAt: Date?

    // Phase 0 mock;Phase 2 改为 @Query TeamMember
    private let mockMembers: [TeamMember] = [
        TeamMember(userID: "self", displayName: "我(Owner)", email: "me@example.com", role: .owner),
        TeamMember(userID: "member-1", displayName: "工程师 A", email: "a@example.com", role: .engineer),
        TeamMember(userID: "member-2", displayName: "工程师 B", email: "b@example.com", role: .engineer),
    ]

    @State private var errorMessage: String?

    /// 用户手动改过 address 字段后,后续 siteTag 变化不再自动覆盖。
    /// 编辑模式(.edit)初始化时直接置 true,保证不会覆盖已有值。
    @State private var userEditedAddress: Bool = false
    /// 内部标记:这次 address 变化是程序自动填的,不是用户敲的。
    /// 仅在 prefillAddressIfNeeded 中置 true,onChange 看到后吞掉这次事件。
    @State private var suppressNextAddressChange: Bool = false

    private var locale: Locale { AppLanguageManager.currentLocale }

    init(target: SitePresetEditingTarget,
         onSave: @escaping (SitePreset) -> Void) {
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
        // 编辑模式:address 已是用户/之前保存的值,不要被 siteTag picker 覆盖。
        // 新建模式:允许自动填(直到用户真的编辑过 address)。
        switch target {
        case .edit:
            _userEditedAddress = State(initialValue: true)
        case .new:
            _userEditedAddress = State(initialValue: !initial.address.isEmpty)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                siteSection
                projectInfoSection
                defaultsSection
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
            .sheet(isPresented: $showsNewSiteSheet) {
                NewSiteSheet { tag, addr in
                    siteTags = SiteTagsStorage.load()
                    if !tag.isEmpty {
                        siteTag = tag
                    }
                    // NewSiteSheet 已经写好 SitePreset.address;
                    // 这里如果用户没改过 address 字段,顺手把新地址带进来,
                    // 避免用户再去 picker 选一次触发 onChange。
                    if !userEditedAddress, !addr.isEmpty, addr != address {
                        suppressNextAddressChange = true
                        address = addr
                    }
                }
            }
            .onChange(of: siteTag) { _, newTag in
                prefillAddressIfNeeded(for: newTag)
            }
        }
    }

    /// 选定 siteTag 时,如果是新建模式且用户没手填过 address,从已有 preset 自动填入。
    /// NewSiteSheet 创建工地时会写 SitePreset(siteTag, address),这里能直接拿到。
    private func prefillAddressIfNeeded(for tag: String) {
        guard !userEditedAddress else { return }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 编辑模式 init 时已把 userEditedAddress 置 true,这里到不了。
        if let preset = SitePresetStorage.find(siteTag: trimmed),
           !preset.address.isEmpty,
           preset.address != address {
            suppressNextAddressChange = true
            address = preset.address
        }
    }

    // MARK: - Sections

    private var siteSection: some View {
        Section {
            if siteTags.isEmpty {
                Text(String(localized: "还没有工地。先「新建工地」。", locale: locale))
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.fgDim)
            } else {
                Picker(String(localized: "工地标签", locale: locale), selection: $siteTag) {
                    Text(String(localized: "(未选择)", locale: locale)).tag("")
                    ForEach(siteTags, id: \.self) { tag in
                        Text(tag).tag(tag)
                    }
                }
                .font(.system(size: DesignTokens.FontSize.body))
            }

            Button {
                showsNewSiteSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                    Text(String(localized: "新建工地", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text(String(localized: "工地", locale: locale))
        } footer: {
            Text(String(
                localized: "工地标签必填且唯一。同一个工地标签已有预设时,保存会覆盖旧的。",
                locale: locale
            ))
            .font(.system(size: 12))
        }
    }

    private var projectInfoSection: some View {
        Section {
            TextField(
                String(localized: "项目名(如 Proposed duplex)", locale: locale),
                text: $projectName
            )
            .textInputAutocapitalization(.words)

            TextField(
                String(localized: "项目编号(如 25159)", locale: locale),
                text: $projectNo
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            TextField(
                String(localized: "客户(如 HRK)", locale: locale),
                text: $clientName
            )
            .textInputAutocapitalization(.words)

            TextField(
                String(localized: "地址(如 38 FORSYTH ST...)", locale: locale),
                text: $address,
                axis: .vertical
            )
            .lineLimit(1...3)
            .textInputAutocapitalization(.characters)
            .onChange(of: address) { _, _ in
                // 自动填的不算"用户编辑"。
                if suppressNextAddressChange {
                    suppressNextAddressChange = false
                    return
                }
                // 用户开始改 address 后,后续 siteTag 切换不再覆盖。
                userEditedAddress = true
            }
        } header: {
            Text(String(localized: "项目信息", locale: locale))
        } footer: {
            Text(String(
                localized: "导出 Inspection PDF 时,这些会自动填到 Header。",
                locale: locale
            ))
            .font(.system(size: 12))
        }
    }

    private var defaultsSection: some View {
        Section {
            TextField(
                String(localized: "默认收件人", locale: locale),
                text: $defaultAttn
            )
            .textInputAutocapitalization(.words)

            Picker(
                String(localized: "默认 Builder", locale: locale),
                selection: Binding(
                    get: { defaultBuilderID },
                    set: { newID in
                        defaultBuilderID = newID
                        // 选中 Builder 时自动把 name 填到 defaultAttn。
                        if let newID, let b = builders.first(where: { $0.id == newID }) {
                            defaultAttn = b.name
                        }
                    }
                )
            ) {
                Text(String(localized: "(不绑定)", locale: locale))
                    .tag(UUID?.none)
                ForEach(builders) { b in
                    Text(b.company.isEmpty ? b.name : "\(b.name) · \(b.company)")
                        .tag(Optional(b.id))
                }
            }
            .font(.system(size: DesignTokens.FontSize.body))

            TextField(
                String(localized: "默认巡检类型(如 level 1 reo)", locale: locale),
                text: $defaultInspectionType
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
            Text(String(localized: "默认值", locale: locale))
        } footer: {
            Text(String(
                localized: "选 Builder 后自动填「收件人」=builder.name。导出报告时巡检类型仍可单独改。",
                locale: locale
            ))
            .font(.system(size: 12))
        }
    }

    // Phase 0 mock;Phase 2 改为 @Query TeamMember
    private var assignmentSection: some View {
        Section {
            Picker(
                String(localized: "分配给", locale: locale),
                selection: Binding(
                    get: { assignedToUserID },
                    set: { newID in
                        assignedToUserID = newID
                        assignedAt = (newID == nil) ? nil : Date()
                    }
                )
            ) {
                Text(String(localized: "未分配 / 团队公用", locale: locale))
                    .tag(String?.none)
                ForEach(mockMembers, id: \.userID) { m in
                    Text(m.displayName).tag(Optional(m.userID))
                }
            }
            .font(.system(size: DesignTokens.FontSize.body))

            if let uid = assignedToUserID,
               let assignee = mockMembers.first(where: { $0.userID == uid }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "当前分配:\(assignee.displayName)", locale: locale))
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.fgDim)
                    Spacer()
                }
            }
        } header: {
            Text(String(localized: "分配", locale: locale))
        } footer: {
            Text(String(
                localized: "团队 Owner 可把工地分配给具体成员;未分配则团队公用。Phase 0 用 mock 数据,Phase 2 接通真实团队成员。",
                locale: locale
            ))
            .font(.system(size: 12))
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
            Text(String(localized: "备注", locale: locale))
        }
    }

    // MARK: - Save

    private var navTitle: String {
        switch target {
        case .new: return String(localized: "新建工地预设", locale: locale)
        case .edit: return String(localized: "编辑工地预设", locale: locale)
        }
    }

    private var trimmedSiteTag: String {
        siteTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedSiteTag.isEmpty
    }

    private func attemptSave() {
        guard !trimmedSiteTag.isEmpty else {
            errorMessage = String(localized: "工地标签不能为空。", locale: locale)
            return
        }

        var draft = target.initial  // 保留 id(编辑时)
        draft.siteTag = trimmedSiteTag
        draft.projectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.projectNo = projectNo.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.clientName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.defaultAttn = defaultAttn.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.defaultBuilderID = defaultBuilderID
        draft.defaultInspectionType = defaultInspectionType.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.assignedToUserID = assignedToUserID
        draft.assignedAt = assignedAt

        onSave(draft)
        dismiss()
    }
}
