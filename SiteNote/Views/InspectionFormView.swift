//
//  InspectionFormView.swift
//  SiteNote
//
//  Engineer 工作流(R3 重写):创建/编辑一份 InspectionReport。
//
//  新数据架构:Note 是一等公民(用户在"记"界面录,含 transcription + photoPaths
//  + floorPlanRef/X/Y + siteTag),InspectionReport 只**聚合**一组 Note IDs +
//  Header 字段,不重复存照片。
//
//  3 段表单:
//    1. Header(项目、客户、日期、Builder、报告号 etc.)
//    2. 选 Note(默认勾上当天的;用户可在 NotePickerSheet 里改范围)
//    3. 主照片 + 每条 Note 的 caption 调整
//  底部:保存草稿 / 导出 PDF。
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - 内置 Inspection 类型选项

/// 工程师常做的几种巡检类型;menu 快选,自由文本仍可手输。
private enum InspectionTypePreset: String, CaseIterable, Identifiable {
    case level1Reo = "Level 1 reo"
    case level2Reo = "Level 2 reo"
    case columnReo = "Column reo"
    case slabReo = "Slab reo"
    case footingReo = "Footing reo"

    var id: String { rawValue }
}

// MARK: - Main view

struct InspectionFormView: View {
    @Bindable var report: InspectionReport

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// 用来在 Section 2 / 3 渲染/反查所选 Note。@Query 拿到全部活的 Note,在
    /// computed property 里按 report.noteIDs 顺序映射。
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.createdAt,
        order: .reverse
    )
    private var allNotes: [Note]

    /// 同项目已存在的报告编号(用于 ReportNumbering 计算下一个 visitIndex)。
    @Query(
        filter: #Predicate<InspectionReport> { $0.deletedAt == nil },
        sort: \InspectionReport.createdAt,
        order: .reverse
    )
    private var allReports: [InspectionReport]

    // Builder 联系簿选择 sheet
    @State private var showsBuilderPicker = false

    // 选 Note sheet
    @State private var showsNotePicker = false

    // 用户是否手工确认 / 编辑过 reportNo。一旦"项目号变化"自动重填只在未确认时生效。
    @State private var reportNoConfirmed: Bool = false

    // 顶部"工地"picker 选中的 siteTag。nil = 未选。
    // 注意:与 report.location 解耦 —— location 是 Header 字段(用户能直接编辑文本),
    // selectedSiteTag 只是 "用哪个工地的预设来反查 SitePreset"。
    @State private var selectedSiteTag: String?

    // 导出 PDF 流程
    @State private var isBuildingPDF = false
    @State private var exportContext: ExportContext?
    @State private var errorMessage: String?

    private struct ExportContext: Identifiable {
        let id = UUID()
        let pdfURL: URL
    }

    var body: some View {
        Form {
            headerSection
            notesSection
            captionsSection
            actionSection
        }
        .industrialForm()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "保存草稿", locale: AppLanguageManager.currentLocale)) {
                    saveDraft()
                }
                .font(.system(size: 15, weight: .semibold))
            }
        }
        .onAppear {
            prefillEngineerNameIfNeeded()
            prefillReportNoIfNeeded()
            prefillSelectedSiteTagIfNeeded()
            // 已经有非空 reportNo 视为"用户已确认或之前已经分配过",别再自动覆盖。
            if !report.reportNo.isEmpty {
                reportNoConfirmed = true
            }
        }
        .onChange(of: report.projectNo) { _, _ in
            // 项目号变化时,如果用户尚未手动确认编号,就重算一次。
            guard !reportNoConfirmed else { return }
            recomputeReportNo()
        }
        // Builder 选择
        .sheet(isPresented: $showsBuilderPicker) {
            BuilderContactPickerSheet { picked in
                report.attn = picked.name
                report.builderID = picked.id.uuidString
                report.updatedAt = Date()
            }
        }
        // 选 Note
        .sheet(isPresented: $showsNotePicker) {
            NotePickerSheet(
                initialSelectedIDs: report.noteIDs,
                defaultDate: report.reportDate,
                defaultSiteTag: selectedSiteTag ?? report.location
            ) { picked in
                report.noteIDs = picked
                report.updatedAt = Date()
            }
        }
        // 错误提示
        .alert(
            String(localized: "出错了", locale: AppLanguageManager.currentLocale),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(String(localized: "知道了", locale: AppLanguageManager.currentLocale), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        // 导出 PDF 后弹邮件 sheet
        .sheet(item: $exportContext) { ctx in
            InspectionExportSheet(report: report, pdfURL: ctx.pdfURL)
        }
    }

    private var navigationTitle: String {
        if report.reportNo.isEmpty {
            return String(localized: "新建巡检", locale: AppLanguageManager.currentLocale)
        }
        return report.reportNo
    }

    // MARK: - Section 1: Header

    @ViewBuilder
    private var headerSection: some View {
        Section {
            sitePresetRow

            TextField(
                String(localized: "Project(项目)", locale: AppLanguageManager.currentLocale),
                text: $report.project
            )
            TextField(
                String(localized: "Project No.(项目编号)", locale: AppLanguageManager.currentLocale),
                text: $report.projectNo
            )
            .textInputAutocapitalization(.characters)

            TextField(
                String(localized: "Client(客户)", locale: AppLanguageManager.currentLocale),
                text: $report.client
            )

            TextField(
                String(localized: "Location(地址)", locale: AppLanguageManager.currentLocale),
                text: $report.location,
                axis: .vertical
            )
            .lineLimit(1...3)

            // Attn + 从联系簿
            HStack(spacing: 8) {
                TextField(
                    String(localized: "Attn(收件人)", locale: AppLanguageManager.currentLocale),
                    text: $report.attn
                )
                Button {
                    showsBuilderPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 14))
                        Text(String(localized: "从联系簿", locale: AppLanguageManager.currentLocale))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Ink.fg)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "从联系簿选", locale: AppLanguageManager.currentLocale))
            }

            DatePicker(
                String(localized: "Date(日期)", locale: AppLanguageManager.currentLocale),
                selection: $report.reportDate,
                displayedComponents: .date
            )

            // Inspection type + 内置菜单
            HStack(spacing: 8) {
                TextField(
                    String(localized: "Inspection type(类型)", locale: AppLanguageManager.currentLocale),
                    text: $report.inspectionType
                )
                Menu {
                    ForEach(InspectionTypePreset.allCases) { preset in
                        Button(preset.rawValue) {
                            report.inspectionType = preset.rawValue
                            report.updatedAt = Date()
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Ink.fg)
                }
                .accessibilityLabel(String(localized: "选择常用类型", locale: AppLanguageManager.currentLocale))
            }

            // Report No.(只读)
            HStack {
                Text(String(localized: "Report No.(报告号)", locale: AppLanguageManager.currentLocale))
                    .foregroundStyle(Ink.fgDim)
                    .font(.system(size: 14))
                Spacer()
                Text(reportNoDisplay)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(reportNoDisplayColor)
                    .monospacedDigit()
            }

            TextField(
                String(localized: "Engineer name(工程师)", locale: AppLanguageManager.currentLocale),
                text: $report.engineerName
            )

            TextField(
                String(localized: "Site Rep status(现场代表状态)", locale: AppLanguageManager.currentLocale),
                text: $report.siteRepStatus
            )
        } header: {
            SectionHeader(String(localized: "Header", locale: AppLanguageManager.currentLocale))
        } footer: {
            SectionFooter(String(localized: "项目编号变动会自动重算报告号(直到你手动确认)。", locale: AppLanguageManager.currentLocale))
        }
    }

    // MARK: - 工地预设(Header 第一行)

    /// 顶部"工地 + 应用预设"行。
    /// - Picker:选项来自 SiteTagsStorage.load(),默认 nil(显示"未选")。
    /// - 应用预设 Button:仅当所选 siteTag 存在 SitePreset 时启用。
    /// - 无预设时:显示一行提示文字,引导去 Settings 添加。
    @ViewBuilder
    private var sitePresetRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker(
                    String(localized: "工地", locale: AppLanguageManager.currentLocale),
                    selection: Binding<String?>(
                        get: { selectedSiteTag },
                        set: { selectedSiteTag = $0 }
                    )
                ) {
                    Text(String(localized: "未选", locale: AppLanguageManager.currentLocale))
                        .tag(String?.none)
                    ForEach(SiteTagsStorage.load(), id: \.self) { tag in
                        Text(tag).tag(String?.some(tag))
                    }
                }
                Spacer()
                Button {
                    applyPreset()
                } label: {
                    Text(String(localized: "应用预设", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(canApplyPreset ? Ink.fg : Ink.dim)
                }
                .buttonStyle(.plain)
                .disabled(!canApplyPreset)
                .accessibilityLabel(String(localized: "应用工地预设到 Header", locale: AppLanguageManager.currentLocale))
            }
            // 选了工地但没有预设 → 提示。
            if let tag = selectedSiteTag, !tag.isEmpty, SitePresetStorage.find(siteTag: tag) == nil {
                Text(String(localized: "未找到此工地的预设。可在 设置 → 工地预设 添加。", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
            }
        }
        .padding(.vertical, 2)
    }

    /// 是否可应用预设:选了工地,且能找到 SitePreset。
    private var canApplyPreset: Bool {
        guard let tag = selectedSiteTag, !tag.isEmpty else { return false }
        return SitePresetStorage.find(siteTag: tag) != nil
    }

    /// 覆盖式把 SitePreset 字段灌到 Header。
    /// 行为:用户已经选了工地 + 主动点了按钮 → 强制覆盖,避免"猜测哪些字段该保留"。
    /// 若 builderID 对应的 Builder 还存在,顺便把 attn 同步为 builder.name(若 preset 自己有 defaultAttn 优先用 preset)。
    private func applyPreset() {
        guard let tag = selectedSiteTag, !tag.isEmpty,
              let preset = SitePresetStorage.find(siteTag: tag) else { return }
        report.project = preset.projectName
        report.projectNo = preset.projectNo
        report.client = preset.clientName
        report.location = preset.address.isEmpty ? tag : preset.address
        // attn 优先用 preset.defaultAttn;若 preset 没填但 builderID 存在 → 用 builder.name
        if !preset.defaultAttn.isEmpty {
            report.attn = preset.defaultAttn
        } else if let bid = preset.defaultBuilderID, let b = BuildersStorage.find(id: bid) {
            report.attn = b.name
        }
        if let bid = preset.defaultBuilderID {
            report.builderID = bid.uuidString
        }
        report.inspectionType = preset.defaultInspectionType
        report.updatedAt = Date()
        // 项目号变了 → 触发自动重算 reportNo(若未手动确认过)。
        // onChange(of: report.projectNo) 已注册,会自动跑;此处不显式调用。
    }

    private var reportNoDisplay: String {
        if !report.reportNo.isEmpty { return report.reportNo }
        if report.projectNo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "(待填项目号)", locale: AppLanguageManager.currentLocale)
        }
        return String(localized: "(自动生成中)", locale: AppLanguageManager.currentLocale)
    }

    private var reportNoDisplayColor: Color {
        report.reportNo.isEmpty ? Ink.fgDim : Ink.fg
    }

    // MARK: - Section 2: 选 Note

    @ViewBuilder
    private var notesSection: some View {
        Section {
            Button {
                showsNotePicker = true
            } label: {
                HStack {
                    Image(systemName: "checklist")
                        .font(.system(size: 16))
                        .foregroundStyle(Ink.fg)
                    Text(
                        String(
                            localized: "选择记录(已选 \(report.noteIDs.count) 条)",
                            locale: AppLanguageManager.currentLocale
                        )
                    )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.fg)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.dim)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if selectedNotes.isEmpty {
                Text(String(localized: "还没选记录。点上方按钮挑当天的现场速记。", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.fgDim)
                    .padding(.vertical, 4)
            } else {
                ForEach(selectedNotes, id: \.id) { note in
                    NavigationLink(value: note) {
                        selectedNoteRow(note)
                    }
                }
            }
        } header: {
            SectionHeader(String(localized: "现场记录", locale: AppLanguageManager.currentLocale))
        } footer: {
            SectionFooter(String(localized: "在选择器里切换:按工地 / 按时间段。", locale: AppLanguageManager.currentLocale))
        }
        // 不在本视图注册 navigationDestination(for: Note.self) —— 父级 NavigationStack
        // (RecordView / ReportsView)已经统一注册过,push 时直接复用,避免双注册告警。
    }

    @ViewBuilder
    private func selectedNoteRow(_ note: Note) -> some View {
        HStack(spacing: 10) {
            if let path = note.photoPaths.first,
               let url = PhotoStorage.absoluteURL(forRelative: path),
               let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Ink.line, lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Ink.card)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "text.bubble")
                            .font(.system(size: 14))
                            .foregroundStyle(Ink.fgDim)
                    )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(noteSummary(note))
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.fg)
                    .lineLimit(2)
                Text(timeLabel(for: note.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Section 3: caption 调整(每条 Note)

    // 主照片 section 已于 v1.x 移除:PDF 封面不再渲染主照片,
    // 所有照片走第 2+ 页网格,每张照片自带 caption(override 优先,否则用
    // Note.transcription)。`report.mainNoteID` / `report.mainCaption`
    // 字段在模型层保留(向后兼容),但 UI 不再暴露。
    @ViewBuilder
    private var captionsSection: some View {
        // 没选 Note → 整段不渲染,Form 上少一段空 Section。
        if !selectedNotes.isEmpty {
            Section {
                ForEach(selectedNotes, id: \.id) { note in
                    captionOverrideRow(note: note)
                }
            } header: {
                SectionHeader(String(localized: "图片说明", locale: AppLanguageManager.currentLocale))
            } footer: {
                SectionFooter(String(localized: "PDF 报告里每张图下方的文字。默认是你的录音转写,这里可以改短或纠正。", locale: AppLanguageManager.currentLocale))
            }
        }
    }

    @ViewBuilder
    private func captionOverrideRow(note: Note) -> some View {
        let binding = Binding<String>(
            get: {
                report.captionOverrides()[note.id] ?? note.transcription
            },
            set: { newValue in
                var map = report.captionOverrides()
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed == note.transcription.trimmingCharacters(in: .whitespacesAndNewlines) {
                    map.removeValue(forKey: note.id)
                } else {
                    map[note.id] = newValue
                }
                report.setCaptionOverrides(map)
                report.updatedAt = Date()
            }
        )
        VStack(alignment: .leading, spacing: 4) {
            Text(timeLabel(for: note.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(Ink.fgDim)
            TextField(
                String(localized: "图片说明", locale: AppLanguageManager.currentLocale),
                text: binding,
                axis: .vertical
            )
            .lineLimit(1...4)
            .font(.system(size: 13))
        }
        .padding(.vertical, 2)
    }

    // MARK: - Section 4: 底部操作

    @ViewBuilder
    private var actionSection: some View {
        Section {
            Button {
                Task { await exportPDF() }
            } label: {
                HStack {
                    if isBuildingPDF {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    } else {
                        Image(systemName: "doc.richtext")
                    }
                    Text(isBuildingPDF
                         ? String(localized: "正在生成…", locale: AppLanguageManager.currentLocale)
                         : String(localized: "导出 PDF", locale: AppLanguageManager.currentLocale))
                    Spacer()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Ink.fg)
            }
            .buttonStyle(.plain)
            .disabled(isBuildingPDF || report.noteIDs.isEmpty)
        } footer: {
            SectionFooter(String(localized: "保存草稿后可继续编辑。导出 PDF 后弹邮件 sheet,一键发给 builder。", locale: AppLanguageManager.currentLocale))
        }
    }

    // MARK: - 选中 Note 推导

    /// 按 report.noteIDs 顺序返回的 Note 数组。找不到的 ID 静默跳过。
    private var selectedNotes: [Note] {
        let map = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.id, $0) })
        return report.noteIDs.compactMap { map[$0] }
    }

    // MARK: - 业务逻辑

    /// 第一次进入时尝试根据已有信息猜出 selectedSiteTag,这样 NotePickerSheet 默认按
    /// "当前工地"过滤。匹配策略:
    ///   1. 若 report.location 完全等于一个已知 siteTag → 用它
    ///   2. 否则,选中的 Note 若全都来自同一个 siteTag → 用那个
    ///   3. 否则保持 nil
    private func prefillSelectedSiteTagIfNeeded() {
        guard selectedSiteTag == nil else { return }
        let tags = SiteTagsStorage.load()
        let loc = report.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !loc.isEmpty, tags.contains(loc) {
            selectedSiteTag = loc
            return
        }
        // 反推:从选中 Note 的 siteTag 找一个共有的
        let noteTags = Set(selectedNotes.compactMap { $0.siteTag }.filter { !$0.isEmpty })
        if noteTags.count == 1, let only = noteTags.first {
            selectedSiteTag = only
        }
    }

    /// 默认填工程师名:首次进入且字段为空时,用 ProfileKind.displayName 占位
    /// (用户在 form 里能直接覆写)。
    private func prefillEngineerNameIfNeeded() {
        guard report.engineerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let role = UserProfileManager.shared.current.displayName
        report.engineerName = role
        if report.siteRepStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            report.siteRepStatus = "Emailed"
        }
    }

    /// 第一次进入(noteIDs 为空)就把当天 Note 默认全选 + 自动算 reportNo。
    /// 注:主照片相关字段(mainNoteID / mainCaption)已不在 UI 暴露,这里也不再预填。
    private func prefillReportNoIfNeeded() {
        if report.noteIDs.isEmpty {
            let today = Calendar.current.startOfDay(for: Date())
            let candidates = allNotes.filter {
                Calendar.current.isDate($0.createdAt, inSameDayAs: today)
            }
            report.noteIDs = candidates.map { $0.id }
        }
        if report.reportNo.isEmpty,
           !report.projectNo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recomputeReportNo()
        }
    }

    /// 用 ReportNumbering.nextNumber 计算下一个报告号。
    private func recomputeReportNo() {
        let proj = report.projectNo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proj.isEmpty else { return }
        let existing = allReports
            .filter { $0.id != report.id }
            .map { $0.reportNo }
            .filter { !$0.isEmpty }
        report.reportNo = ReportNumbering.nextNumber(projectNo: proj, existingNumbers: existing)
        report.updatedAt = Date()
    }

    private func saveDraft() {
        report.updatedAt = Date()
        dismiss()
    }

    /// 异步生成 PDF。R5 agent 改 PDFBuilder 后这里会调到正确签名。
    /// 期间通过 isBuildingPDF flag 禁用按钮 + 显示 spinner。
    @MainActor
    private func exportPDF() async {
        guard !isBuildingPDF else { return }
        isBuildingPDF = true
        defer { isBuildingPDF = false }
        // 把当前选中 Note 实例化喂给 PDF builder(builder 不依赖 modelContext)。
        let notes = selectedNotes
        do {
            let url = try await InspectionReportPDFBuilder.build(report: report, notes: notes)
            let archivedURL = (try? ReportArchiveService.archive(sourceURL: url)) ?? url
            report.lastPDFPath = archivedURL.path
            report.updatedAt = Date()
            exportContext = ExportContext(pdfURL: archivedURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 显示工具

    private func noteSummary(_ note: Note) -> String {
        let t = note.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            return String(localized: "(空记录)", locale: AppLanguageManager.currentLocale)
        }
        return String(t.prefix(60))
    }

    private func timeLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "d MMM HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Builder Picker(联系簿)

/// 从 BuildersStorage 选一个联系人。当前不做"新建" — 那是 Settings 联系簿的事。
private struct BuilderContactPickerSheet: View {
    let onPick: (Builder) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var builders: [Builder] {
        let all = BuildersStorage.load()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        let lower = q.lowercased()
        return all.filter {
            $0.name.lowercased().contains(lower)
                || $0.company.lowercased().contains(lower)
                || $0.email.lowercased().contains(lower)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if BuildersStorage.load().isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(builders) { builder in
                            Button {
                                onPick(builder)
                                dismiss()
                            } label: {
                                row(builder)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Ink.bg)
                        }
                    }
                    .listStyle(.plain)
                    .industrialForm()
                    .searchable(
                        text: $query,
                        prompt: Text(String(localized: "搜索姓名/公司/邮箱", locale: AppLanguageManager.currentLocale))
                    )
                }
            }
            .navigationTitle(String(localized: "从联系簿选", locale: AppLanguageManager.currentLocale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", locale: AppLanguageManager.currentLocale)) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func row(_ b: Builder) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(b.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                if !b.company.isEmpty {
                    Text("· \(b.company)")
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.fgDim)
                }
                Spacer()
            }
            if !b.email.isEmpty {
                Text(b.email)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.fgDim)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Ink.fgDim)
            Text(String(localized: "联系簿还是空的", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 15, weight: .semibold))
            Text(String(localized: "在 Settings → 联系人 里添加 Builder/Foreman。", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 12))
                .foregroundStyle(Ink.fgDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

