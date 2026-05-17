//
//  PDFExportView.swift
//  SiteNote
//
//  导出 PDF 巡检日志。
//  流程:选日期范围(精确到小时)+ 工地筛选 → 点"选择记录" → 勾选要包含的 note → 生成 PDF。
//

import SwiftUI
import SwiftData

struct PDFExportView: View {
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.createdAt
    ) private var allNotes: [Note]

    @State private var startDate: Date = defaultStartDate()
    @State private var endDate: Date = Date()
    @State private var selectedTag: String? = nil
    @State private var availableTags: [String] = []
    @State private var availableSubTags: [SubTag] = []
    /// 分类过滤。空集 = 不过滤。分类是全局的,不受工地选择影响。
    @State private var selectedSubTags: Set<String> = []

    @State private var showsPicker: Bool = false
    @State private var exportURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            dateRangeSection
            siteFilterSection
            subTagFilterSection
            countSection
            actionSection
        }
        .navigationTitle("导出 PDF 日志")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .onAppear {
            availableTags = SiteTagsStorage.load()
            availableSubTags = SubTagsStorage.load()
            // 清理已删除的分类选择
            let validNames = Set(availableSubTags.map { $0.name })
            selectedSubTags = selectedSubTags.intersection(validNames)
        }
        .sheet(isPresented: $showsPicker) {
            NoteSelectionSheet(
                candidates: filteredNotes,
                dateRange: rangeDescription,
                onConfirm: { selected in
                    showsPicker = false
                    generatePDF(with: selected)
                }
            )
        }
        .sheet(item: Binding(
            get: { exportURL.map { PDFShareItem(url: $0) } },
            set: { _ in exportURL = nil }
        )) { item in
            ShareSheet(items: [item.url])
        }
        .alert("生成失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var dateRangeSection: some View {
        Section("日期范围(精确到小时)") {
            DatePicker(
                "开始",
                selection: $startDate,
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.system(size: DesignTokens.FontSize.body))

            DatePicker(
                "结束",
                selection: $endDate,
                in: startDate...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.system(size: DesignTokens.FontSize.body))

            Text(rangeDescription)
                .font(.system(size: DesignTokens.FontSize.body))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var siteFilterSection: some View {
        if !availableTags.isEmpty {
            Section {
                Picker("工地", selection: $selectedTag) {
                    Text("全部").tag(nil as String?)
                    ForEach(availableTags, id: \.self) { tag in
                        Text(tag).tag(tag as String?)
                    }
                }
                .font(.system(size: DesignTokens.FontSize.body))
            } header: {
                Text("工地筛选")
            }
        }
    }

    @ViewBuilder
    private var subTagFilterSection: some View {
        if !availableSubTags.isEmpty {
            Section {
                ForEach(availableSubTags) { sub in
                    subTagFilterRow(sub: sub)
                }
            } header: {
                Text("分类筛选(可多选,空=全部)")
            } footer: {
                Text("只勾 \"RFI\" 就只导出 RFI 的记录。空着不勾等于不过滤。")
                    .font(.system(size: 12))
            }
        }
    }

    private func subTagFilterRow(sub: SubTag) -> some View {
        let isSelected = selectedSubTags.contains(sub.name)
        return Button {
            if isSelected {
                selectedSubTags.remove(sub.name)
            } else {
                selectedSubTags.insert(sub.name)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 22)
                Circle()
                    .fill(sub.color)
                    .frame(width: 12, height: 12)
                Text(sub.name)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var countSection: some View {
        Section("范围内记录") {
            HStack {
                Text("符合条件的速记")
                    .font(.system(size: DesignTokens.FontSize.body))
                Spacer()
                Text("\(filteredNotes.count) 条")
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                showsPicker = true
            } label: {
                HStack {
                    Image(systemName: "checklist")
                    Text("选择记录并生成 PDF")
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .disabled(filteredNotes.isEmpty)
        } footer: {
            Text("PDF 每条占一页,含转写、位置、天气、巡检模板、照片,以及(若标了位置)平面图 + 当前图钉示意。")
                .font(.system(size: DesignTokens.FontSize.body))
        }
    }

    /// 按用户条件筛出的 note(日期精确到分,含两端)。
    private var filteredNotes: [Note] {
        allNotes
            .filter { note in
                let inRange = note.createdAt >= startDate && note.createdAt <= endDate
                let tagMatch = selectedTag == nil || note.siteTag == selectedTag
                let subMatch: Bool
                if selectedSubTags.isEmpty {
                    subMatch = true
                } else {
                    subMatch = !selectedSubTags.isDisjoint(with: Set(note.otherTags))
                }
                return inRange && tagMatch && subMatch
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// 统一的日期范围文案,精确到分钟。
    private var rangeDescription: String {
        let formatter = PDFExportView.rangeFormatter
        let s = formatter.string(from: startDate)
        let e = formatter.string(from: endDate)
        return String(localized: "\(s)  至  \(e)", locale: AppLanguageManager.currentLocale)
    }

    static let rangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func defaultStartDate() -> Date {
        let cal = Calendar.current
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return cal.date(bySettingHour: 0, minute: 0, second: 0, of: weekAgo) ?? weekAgo
    }

    private func generatePDF(with notes: [Note]) {
        guard !notes.isEmpty else {
            errorMessage = String(localized: "没有选中任何记录。", locale: AppLanguageManager.currentLocale)
            return
        }
        let title = selectedTag.map { String(localized: "\($0) 巡检日志", locale: AppLanguageManager.currentLocale) } ?? String(localized: "SiteNote 巡检日志", locale: AppLanguageManager.currentLocale)
        Task {
            do {
                let url = try PDFExportService.generatePDF(
                    notes: notes,
                    startDate: startDate,
                    endDate: endDate,
                    title: title
                )
                // 按选中的工地分文件夹存(没选 = "全部工地" → "未分类")
                let archivedURL = (try? ReportArchiveService.archive(
                    sourceURL: url,
                    projectFolder: selectedTag
                )) ?? url
                exportURL = archivedURL
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

// MARK: - 记录勾选 sheet

/// 让用户在生成 PDF 前勾选要包含的 note。默认全勾。
private struct NoteSelectionSheet: View {
    let candidates: [Note]
    let dateRange: String
    let onConfirm: ([Note]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBar
                Divider()
                List {
                    ForEach(candidates) { note in
                        row(for: note)
                    }
                }
                .listStyle(.plain)
                bottomBar
            }
            .navigationTitle("选要包含的记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                selectedIDs = Set(candidates.map { $0.id })
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateRange)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                Text("\(selectedIDs.count) / \(candidates.count) 条已选")
                    .font(.system(size: DesignTokens.FontSize.body))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if selectedIDs.count == candidates.count {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(candidates.map { $0.id })
                }
            } label: {
                Text(selectedIDs.count == candidates.count ? "全不选" : "全选")
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
            }
        }
        .padding(DesignTokens.Spacing.medium)
    }

    private func row(for note: Note) -> some View {
        let isSelected = selectedIDs.contains(note.id)
        return Button {
            if isSelected {
                selectedIDs.remove(note.id)
            } else {
                selectedIDs.insert(note.id)
            }
        } label: {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if note.isHazard {
                            Text("🚨").font(.system(size: 13))
                        }
                        Text(PDFExportView.rangeFormatter.string(from: note.createdAt))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(preview(note))
                        .font(.system(size: DesignTokens.FontSize.body))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        if let tag = note.siteTag {
                            chipInline(text: tag)
                        }
                        if !note.photoPaths.isEmpty {
                            Image(systemName: "photo").font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        if note.audioFilePath != nil {
                            Image(systemName: "waveform").font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        if note.floorPlanRef != nil {
                            Image(systemName: "map.fill").font(.system(size: 11))
                                .foregroundStyle(Ink.fgDim)
                        }
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chipInline(text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.2))
            .clipShape(Capsule())
    }

    private func preview(_ note: Note) -> String {
        if !note.transcription.isEmpty {
            let limit = 60
            return note.transcription.count > limit
                ? String(note.transcription.prefix(limit)) + "…"
                : note.transcription
        }
        return String(localized: "(仅录音/照片)", locale: AppLanguageManager.currentLocale)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                let selected = candidates.filter { selectedIDs.contains($0.id) }
                onConfirm(selected)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                    Text("生成 \(selectedIDs.count) 条的 PDF")
                }
                .font(.system(size: DesignTokens.FontSize.body, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(selectedIDs.isEmpty ? Color.gray : Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(selectedIDs.isEmpty)
            .padding(DesignTokens.Spacing.medium)
        }
    }
}

private struct PDFShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
