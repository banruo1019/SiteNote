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

    /// 当前 site preset linked 的联系人列表(从 BuildersStorage 拉)。
    /// 没绑联系人 → 空(空态引导用户去设置 → 工地详情加联系人)。
    /// v1.4:从"按 clientName 公司匹配"改成"按 SitePreset.linkedContactIDs 显式绑定"。
    private var siteContacts: [Builder] {
        guard let preset = selectedPreset else { return [] }
        let ids = Set(preset.linkedContactIDs)
        return availableBuilders.filter { ids.contains($0.id) }
    }

    /// 表单是否可提交:必须选工地 + 填类型。
    private var canStart: Bool {
        !siteTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !inspectionType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 预览用的下一个报告号 — 实际生成在 manager.start 时,这里只展示占位提示。
    /// 不复用 manager 的内部序号生成器(避免提前消耗 counter),用占位文本即可。
    private var previewReportNoPlaceholder: String {
        String(localized: "自动分配", locale: locale)
    }

    // MARK: - body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    siteSection
                    inspectionTypeSection
                    recipientsSection
                    previewSection
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
                text: $inspectionType
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

    private func builderRow(_ builder: Builder) -> some View {
        let checked = selectedBuilderIDs.contains(builder.id)
        return Button {
            toggleBuilder(builder.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(checked ? Ink.fg : Ink.fgDim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(builder.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.fg)
                    if !builder.company.isEmpty {
                        Text(builder.company)
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

    // MARK: - 预览 section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Rectangle().fill(Ink.line).frame(height: 1)
                Text(String(localized: "预览", locale: locale))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Ink.fgDim)
                Rectangle().fill(Ink.line).frame(height: 1)
            }
            .padding(.horizontal, 4)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.fg)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(previewReportNoPlaceholder)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                    Text(previewSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.fg2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Ink.card)
            )
        }
    }

    private var previewSubtitle: String {
        let site = siteTag.isEmpty
            ? String(localized: "未选工地", locale: locale)
            : siteTag
        let type = inspectionType.isEmpty
            ? String(localized: "未填类型", locale: locale)
            : inspectionType
        return "\(site) · \(type)"
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

    /// 初始化:load presets / builders,处理 prefill。
    private func initialLoad() {
        sitePresets = SitePresetStorage.load()
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
    /// 用户已经手改过类型时不覆盖。
    /// 切换工地时清掉不在新 site linked 范围的勾选(避免把别的工地的联系人留下来)。
    private func applyPresetDefaults() {
        guard let preset = selectedPreset else { return }

        if inspectionType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

        // 默认 attn:选了 builder 取第一个;否则 fallback 到 preset.defaultAttn。
        let attn: String = {
            if let firstSelected = selectedBuilderIDs.first,
               let b = availableBuilders.first(where: { $0.id == firstSelected }) {
                return b.name
            }
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

        // 若选了多个 builder,把第一个 builderID 写到 report,方便后续一键发邮件。
        // 其余多收件人由 export 流程从 selectedBuilderIDs 取(本 sheet 暂不持久化多选,后续可扩展)。
        // TODO: 多收件人持久化 — 当前 InspectionReport 只存单个 builderID,
        //       多收件人交给 EndInspection / Export 时再让用户确认列表。
        if let firstID = selectedBuilderIDs.first {
            report.builderID = firstID.uuidString
            try? modelContext.save()
        }

        onStarted(report)
        dismiss()
    }
}
