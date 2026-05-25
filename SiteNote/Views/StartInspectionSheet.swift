//
//  StartInspectionSheet.swift
//  SiteNote
//
//  Engineer 巡检 session 的"开始巡检"bottom sheet。
//
//  触发场景:
//  - 主屏点"开始巡检"按钮
//  - 在 idle 态点 mic / camera 时(无 active session)
//
//  完成动作:
//  - 调 InspectionSessionManager.shared.start(...) 建一条 draft InspectionReport
//  - 通过 onStarted(report) 回调把报告交给 caller(可以跳详情或不动)
//  - dismiss 自身
//
//  M1 极简白风格:自定义 ScrollView + 卡片,黑底白字胶囊确认按钮。
//  参考 NewSiteSheet.swift 的视觉节奏。
//

import SwiftUI
import SwiftData

struct StartInspectionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 启动成功 callback,把新建的 report 传回去(caller 可以直接跳详情或不动)。
    var onStarted: (InspectionReport) -> Void

    /// 可选预设站点 — 从 RecordView 来时可能有当前选中工地。
    var prefilledSiteTag: String?

    // MARK: - 表单状态

    @State private var siteTag: String = ""
    @State private var inspectionType: String = ""
    /// **R7#1**:跟踪用户是否手改过 inspectionType。
    /// 没手改过 → 切 site preset 时覆盖 preset.defaultInspectionType。
    /// 手改过 → 保留用户输入(尊重 explicit choice)。
    @State private var inspectionTypeUserEdited: Bool = false
    /// v1.5:availableBuilders 改成 Contact 列表(原来是 Builder 扁平列表)。
    /// 命名保留是为了少改变量,本质装的是 ContactsStorage.load()。
    @State private var availableContacts: [Contact] = []
    @State private var availableBuilders: [Builder] = []
    @State private var selectedBuilderIDs: Set<UUID> = []
    @State private var showsNewSite: Bool = false
    @State private var showsBuildersEditor: Bool = false

    /// 缓存的 SitePreset 列表(进入时 load 一次,新建工地后刷新)。
    @State private var sitePresets: [SitePreset] = []

    @FocusState private var typeFocused: Bool

    private var locale: Locale { AppLanguageManager.currentLocale }

    /// 当前选中工地的 preset(可能为 nil = 选了但没预设,或没选)。
    private var selectedPreset: SitePreset? {
        guard !siteTag.isEmpty else { return nil }
        return sitePresets.first { $0.siteTag == siteTag }
    }

    /// 当前 site preset linked 的联系人列表(v1.5 起从 ContactsStorage 拉,id 指 Contact)。
    /// 没绑联系人 → 空(空态引导用户去设置 → 工地详情加联系人)。
    /// **R10 修**:按 `preset.linkedContactIDs` 顺序构造,与 attn/builderID 决议顺序一致。
    /// 否则 UI 显示第一个 vs attn 拿到的"第一个 selected" 可能不是同一人。
    private var siteContacts: [Contact] {
        guard let preset = selectedPreset else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: availableContacts.map { ($0.id, $0) })
        return preset.linkedContactIDs.compactMap { byID[$0] }
    }

    /// 通过 Contact.builderID 反查公司名(用于 row 显示)。
    private func companyName(for contact: Contact) -> String {
        availableBuilders.first(where: { $0.id == contact.builderID })?.name ?? ""
    }

    /// 表单是否可提交:必须选工地 + 填类型。
    private var canStart: Bool {
        !siteTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !inspectionType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }


    // MARK: - body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    siteSection
                    inspectionTypeSection
                    recipientsSection
                    actionRow
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(Ink.bg)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(String(localized: "开始巡检", locale: locale))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                }
            }
            .onAppear { initialLoad() }
            .sheet(isPresented: $showsNewSite) {
                NewSiteSheet { newSiteName, _ in
                    // 新建后刷新 preset 列表,自动选中。
                    sitePresets = SitePresetStorage.load()
                    siteTag = newSiteName
                    applyPresetDefaults()
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showsBuildersEditor, onDismiss: {
                // 编辑联系人回来后重新 load(可能新增)。
                availableContacts = ContactsStorage.load()
                availableBuilders = BuildersStorage.load()
            }) {
                NavigationStack {
                    BuildersEditorView()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 工地 section

    private var siteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(String(localized: "工地", locale: locale))

            Menu {
                if sitePresets.isEmpty {
                    Text(String(localized: "暂无工地预设", locale: locale))
                } else {
                    ForEach(sitePresets, id: \.id) { preset in
                        Button {
                            siteTag = preset.siteTag
                            applyPresetDefaults()
                        } label: {
                            if preset.siteTag == siteTag {
                                Label(preset.siteTag, systemImage: "checkmark")
                            } else {
                                Text(preset.siteTag)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "building.2")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                    Text(siteTag.isEmpty
                         ? String(localized: "选择工地", locale: locale)
                         : siteTag)
                        .font(.system(size: 15))
                        .foregroundStyle(siteTag.isEmpty ? Ink.fgDim : Ink.fg)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.fgDim)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Ink.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Ink.line, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button {
                showsNewSite = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(localized: "新建工地", locale: locale))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Ink.fg)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 巡检类型 section

    private var inspectionTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(String(localized: "巡检类型", locale: locale))

            TextField(
                String(localized: "如 level 1 reo", locale: locale),
                text: Binding(
                    get: { inspectionType },
                    set: { newValue in
                        inspectionType = newValue
                        // R7#1:用户手敲过 → 锁住,不再被切 preset 覆盖
                        inspectionTypeUserEdited = true
                    }
                )
            )
            .focused($typeFocused)
            .font(.system(size: 15))
            .tint(Ink.fg)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Ink.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        typeFocused ? Ink.fg : Ink.line,
                        lineWidth: typeFocused ? 1.5 : 1
                    )
            )
        }
    }

    // MARK: - 收件人 section

    private var recipientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(String(localized: "收件人", locale: locale))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                Rectangle()
                    .fill(Ink.line)
                    .frame(height: 1)
                Text("\(selectedBuilderIDs.count) / \(siteContacts.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Ink.fgDim)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)

            // v1.4:收件人改成"只显示当前 site 明确绑定的联系人"
            // (SitePreset.linkedContactIDs),不再按公司模糊匹配。
            // 没选工地 → 空态;选了但没绑联系人 → 引导去工地详情加。
            if selectedPreset == nil {
                Text(String(
                    localized: "先选工地。收件人会显示该工地绑定的联系人。",
                    locale: locale
                ))
                .font(.system(size: 12))
                .foregroundStyle(Ink.fgDim)
                .padding(.horizontal, 4)
            } else if siteContacts.isEmpty {
                Text(String(
                    localized: "本工地还没绑联系人。去「设置 → 工地 → \(siteTag)」添加。",
                    locale: locale
                ))
                .font(.system(size: 12))
                .foregroundStyle(Ink.fgDim)
                .padding(.horizontal, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(siteContacts, id: \.id) { builder in
                        builderRow(builder)
                    }
                }
            }

            Button {
                showsBuildersEditor = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(localized: "管理联系人", locale: locale))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Ink.fg)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private func builderRow(_ contact: Contact) -> some View {
        let checked = selectedBuilderIDs.contains(contact.id)
        let company = companyName(for: contact)
        return Button {
            toggleBuilder(contact.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(checked ? Ink.fg : Ink.fgDim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.fg)
                    if !company.isEmpty {
                        Text(company)
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Ink.card)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 按钮行

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text(String(localized: "取消", locale: locale))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Ink.line, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                startSession()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(String(localized: "开始巡检", locale: locale))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(canStart ? Color.white : Ink.fgDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(canStart ? Ink.fg : Ink.card)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canStart)
        }
        .padding(.top, 4)
    }

    // MARK: - helpers

    private func sectionLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ink.fg)
            Rectangle()
                .fill(Ink.line)
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
    }

    /// 初始化:load presets / contacts / builders,处理 prefill。
    private func initialLoad() {
        sitePresets = SitePresetStorage.load()
        availableContacts = ContactsStorage.load()
        availableBuilders = BuildersStorage.load()

        // 1) prefill 工地
        if let prefilled = prefilledSiteTag?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prefilled.isEmpty {
            siteTag = prefilled
        }

        // 2) 根据已选工地填默认 type / 默认收件人勾选(applyPresetDefaults 内已含单联系人自动勾)
        applyPresetDefaults()
    }

    /// 选了工地之后:自动 prefill 巡检类型 + 默认收件人勾选。
    /// **R7#1**:用户手改过 inspectionType(inspectionTypeUserEdited=true)→ 保留;
    /// 否则始终用新 preset 的 defaultInspectionType(即使旧 preset 已经填了类型)。
    /// 切换工地时清掉不在新 site linked 范围的勾选(避免把别的工地的联系人留下来)。
    private func applyPresetDefaults() {
        guard let preset = selectedPreset else { return }

        if !inspectionTypeUserEdited {
            inspectionType = preset.defaultInspectionType
        }

        // 清掉不在 linked 范围的勾选
        let linkedSet = Set(preset.linkedContactIDs)
        selectedBuilderIDs = selectedBuilderIDs.intersection(linkedSet)

        // 应用 defaultRecipientIDs(必须 ⊆ linkedContactIDs)
        for id in preset.defaultRecipientIDs where linkedSet.contains(id) {
            selectedBuilderIDs.insert(id)
        }

        // 单联系人 site 自动勾上(省一步)
        if selectedBuilderIDs.isEmpty, siteContacts.count == 1, let only = siteContacts.first {
            selectedBuilderIDs.insert(only.id)
        }
    }

    private func toggleBuilder(_ id: UUID) {
        if selectedBuilderIDs.contains(id) {
            selectedBuilderIDs.remove(id)
        } else {
            selectedBuilderIDs.insert(id)
        }
    }

    // MARK: - 启动

    private func startSession() {
        let trimmedTag = siteTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedType = inspectionType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty, !trimmedType.isEmpty else { return }

        let preset = selectedPreset

        // **R8#3**:默认 attn 取联系人的"第一个" — 之前 `selectedBuilderIDs.first` 从 Set 取
        // 顺序未定,可能任意 selected contact。改:按 preset.linkedContactIDs 的固定顺序找
        // 第一个被勾选的,保证用户看到的 UI 顺序 = report.attn 选用顺序。
        let attn: String = {
            if let preset {
                for id in preset.linkedContactIDs where selectedBuilderIDs.contains(id) {
                    if let c = availableContacts.first(where: { $0.id == id }) {
                        return c.name
                    }
                }
            }
            // 无 preset / 没匹配 → fallback 到 preset.defaultAttn
            return preset?.defaultAttn ?? ""
        }()

        let report = InspectionSessionManager.shared.start(
            siteTag: trimmedTag,
            projectNo: preset?.projectNo ?? "",
            projectName: preset?.projectName ?? trimmedTag,
            clientName: preset?.clientName ?? "",
            address: preset?.address ?? "",
            inspectionType: trimmedType,
            defaultAttn: attn,
            in: modelContext
        )

        // **R9 修**:builderID 必须用与 `attn` 同样的 ordered 决议 — 之前 `selectedBuilderIDs.first`
        // 从 Set 取顺序未定 → attn 显示 A 但 builderID 指向 B → 一键邮件发错人。
        // 这里复用 attn 决议的同款逻辑:按 preset.linkedContactIDs 顺序找第一个 selected。
        let chosenBuilderID: UUID? = {
            if let preset {
                for id in preset.linkedContactIDs where selectedBuilderIDs.contains(id) {
                    return id
                }
            }
            return selectedBuilderIDs.first  // 无 preset 时 fallback
        }()
        if let firstID = chosenBuilderID {
            report.builderID = firstID.uuidString
            try? modelContext.save()
        }

        onStarted(report)
        dismiss()
    }
}
