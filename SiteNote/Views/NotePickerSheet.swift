//
//  NotePickerSheet.swift
//  SiteNote
//
//  Inspection 报告里"选记录"的多选 sheet,从 InspectionFormView 抽出。
//  两种模式:按工地 + 最近 N 天 / 按时间段 + 工地可选。
//

import SwiftUI
import SwiftData
import UIKit

/// 选记录的多选 sheet,两种模式:
/// - **按工地**:固定一个 siteTag,看"最近 N 天"内的记录(N 默认 30,可调 7/14/30/60/90)
/// - **按时间段**:起止日期,工地可选"全部"或具体 tag
///
/// 用 @State filterMode 切换两种 filter UI,共用同一个 list + 多选逻辑。
/// 完成回调 [UUID] 按用户选择顺序给 InspectionFormView。
struct NotePickerSheet: View {
    let initialSelectedIDs: [UUID]
    let defaultDate: Date
    let defaultSiteTag: String

    /// 完成回调:[UUID] 按用户选择顺序。
    let onDone: ([UUID]) -> Void

    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.createdAt,
        order: .reverse
    )
    private var allNotes: [Note]

    enum FilterMode: String, CaseIterable, Identifiable {
        case bySite
        case byDateRange
        var id: String { rawValue }
    }

    @State private var filterMode: FilterMode

    @State private var siteModeTag: String
    @State private var siteModeRecentDays: Int

    @State private var rangeModeStart: Date
    @State private var rangeModeEnd: Date
    @State private var rangeModeTag: String

    @State private var selectedIDs: [UUID]

    private let allSitesTag: String = ""
    private let recentDayOptions: [Int] = [7, 14, 30, 60, 90]

    init(
        initialSelectedIDs: [UUID],
        defaultDate: Date,
        defaultSiteTag: String,
        onDone: @escaping ([UUID]) -> Void
    ) {
        self.initialSelectedIDs = initialSelectedIDs
        self.defaultDate = defaultDate
        self.defaultSiteTag = defaultSiteTag
        self.onDone = onDone

        let initialMode: FilterMode = defaultSiteTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .byDateRange
            : .bySite
        _filterMode = State(initialValue: initialMode)

        _siteModeTag = State(initialValue: defaultSiteTag)
        _siteModeRecentDays = State(initialValue: 30)

        let today = Calendar.current.startOfDay(for: Date())
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: today) ?? today
        _rangeModeStart = State(initialValue: weekAgo)
        _rangeModeEnd = State(initialValue: today)
        _rangeModeTag = State(initialValue: defaultSiteTag)

        _selectedIDs = State(initialValue: initialSelectedIDs)
    }

    private var availableSiteTags: [String] {
        SiteTagsStorage.load()
    }

    private var filteredNotes: [Note] {
        switch filterMode {
        case .bySite:
            return filterBySite()
        case .byDateRange:
            return filterByDateRange()
        }
    }

    /// 已选但不在当前筛选范围内的 Note(保证 header 显示的"已选 N"和列表能对上)。
    private var selectedOutsideFilter: [Note] {
        let inFilter = Set(filteredNotes.map(\.id))
        return allNotes.filter { selectedIDs.contains($0.id) && !inFilter.contains($0.id) }
    }

    private var displayedNotes: [Note] {
        (filteredNotes + selectedOutsideFilter).sorted { $0.createdAt > $1.createdAt }
    }

    private func filterBySite() -> [Note] {
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -siteModeRecentDays, to: now) ?? now
        return allNotes.filter { note in
            guard note.createdAt >= cutoff else { return false }
            if siteModeTag.isEmpty { return true }
            return (note.siteTag ?? "") == siteModeTag
        }
    }

    private func filterByDateRange() -> [Note] {
        let startDay = Calendar.current.startOfDay(for: rangeModeStart)
        let endDayStart = Calendar.current.startOfDay(for: rangeModeEnd)
        let endDay = Calendar.current.date(byAdding: .day, value: 1, to: endDayStart) ?? endDayStart
        return allNotes.filter { note in
            guard note.createdAt >= startDay, note.createdAt < endDay else { return false }
            if rangeModeTag.isEmpty { return true }
            return (note.siteTag ?? "") == rangeModeTag
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                modeSwitchSection
                filterSection
                listSection
            }
            .industrialForm()
            .navigationTitle(String(localized: "选记录", locale: AppLanguageManager.currentLocale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", locale: AppLanguageManager.currentLocale)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成", locale: AppLanguageManager.currentLocale)) {
                        onDone(selectedIDs)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }

    @ViewBuilder
    private var modeSwitchSection: some View {
        Section {
            Picker(
                String(localized: "模式", locale: AppLanguageManager.currentLocale),
                selection: $filterMode
            ) {
                Text(String(localized: "按工地", locale: AppLanguageManager.currentLocale))
                    .tag(FilterMode.bySite)
                Text(String(localized: "按时间段", locale: AppLanguageManager.currentLocale))
                    .tag(FilterMode.byDateRange)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var filterSection: some View {
        Section {
            switch filterMode {
            case .bySite:
                Picker(
                    String(localized: "工地", locale: AppLanguageManager.currentLocale),
                    selection: $siteModeTag
                ) {
                    Text(String(localized: "全部工地", locale: AppLanguageManager.currentLocale))
                        .tag(allSitesTag)
                    ForEach(availableSiteTags, id: \.self) { tag in
                        Text(tag).tag(tag)
                    }
                }
                Picker(
                    String(localized: "时间窗口", locale: AppLanguageManager.currentLocale),
                    selection: $siteModeRecentDays
                ) {
                    ForEach(recentDayOptions, id: \.self) { n in
                        Text(String(localized: "最近 \(n) 天", locale: AppLanguageManager.currentLocale))
                            .tag(n)
                    }
                }
            case .byDateRange:
                Picker(
                    String(localized: "工地", locale: AppLanguageManager.currentLocale),
                    selection: $rangeModeTag
                ) {
                    Text(String(localized: "全部工地", locale: AppLanguageManager.currentLocale))
                        .tag(allSitesTag)
                    ForEach(availableSiteTags, id: \.self) { tag in
                        Text(tag).tag(tag)
                    }
                }
                DatePicker(
                    String(localized: "起", locale: AppLanguageManager.currentLocale),
                    selection: $rangeModeStart,
                    in: ...rangeModeEnd,
                    displayedComponents: .date
                )
                DatePicker(
                    String(localized: "止", locale: AppLanguageManager.currentLocale),
                    selection: $rangeModeEnd,
                    in: rangeModeStart...,
                    displayedComponents: .date
                )
            }
        } header: {
            SectionHeader(String(localized: "筛选", locale: AppLanguageManager.currentLocale))
        }
    }

    @ViewBuilder
    private var listSection: some View {
        Section {
            if displayedNotes.isEmpty {
                Text(String(localized: "当前筛选条件下没有记录。", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.fgDim)
                    .padding(.vertical, 6)
            } else {
                let outsideIDs = Set(selectedOutsideFilter.map(\.id))
                ForEach(displayedNotes, id: \.id) { note in
                    row(note, outsideFilter: outsideIDs.contains(note.id))
                }
            }
        } header: {
            SectionHeader(
                String(
                    localized: "记录(\(displayedNotes.count) · 已选 \(selectedIDs.count))",
                    locale: AppLanguageManager.currentLocale
                )
            )
        } footer: {
            if !selectedOutsideFilter.isEmpty {
                SectionFooter(
                    String(
                        localized: "\(selectedOutsideFilter.count) 条已选记录不在当前筛选范围内,标灰显示在末尾,可在此取消勾选。",
                        locale: AppLanguageManager.currentLocale
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func row(_ note: Note, outsideFilter: Bool = false) -> some View {
        let isOn = selectedIDs.contains(note.id)
        Button {
            toggle(note.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? Ink.accent : Ink.dim)
                    .frame(width: 22)
                if let path = note.photoPaths.first,
                   let url = PhotoStorage.absoluteURL(forRelative: path),
                   let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Ink.card)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "text.bubble")
                                .font(.system(size: 12))
                                .foregroundStyle(Ink.fgDim)
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(summary(note))
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.fg)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if outsideFilter {
                            Text(String(localized: "超出筛选", locale: AppLanguageManager.currentLocale))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Ink.fgDim)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Ink.card)
                                .clipShape(Capsule())
                        }
                    }
                    HStack(spacing: 6) {
                        Text(timeLabel(note.createdAt))
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                        if let tag = note.siteTag, !tag.isEmpty {
                            Text("· \(tag)")
                                .font(.system(size: 11))
                                .foregroundStyle(Ink.fgDim)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .opacity(outsideFilter ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private func toggle(_ id: UUID) {
        if let idx = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: idx)
        } else {
            selectedIDs.append(id)
        }
    }

    private func summary(_ note: Note) -> String {
        let t = note.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            return String(localized: "(空记录)", locale: AppLanguageManager.currentLocale)
        }
        return String(t.prefix(60))
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
