//
//  LogTabView.swift
//  SiteNote
//
//  Tab "日志":合并原 BrowseView(查)+ DiaryView(工地)。
//  顶部 mode segment 切两个视角:
//   - 纵览(overview):跨日总帐,沿用原 BrowseView 的 10 段折叠列表(含隐患/逾期/今天/3天/本周/以后/待分类/施工日记/备忘/已完成)
//   - 台账(ledger):当日明细,沿用原 DiaryView 的 dayNavigator + summary + segment(人员/机械/事件/速记) + PDF 生成
//
//  共用顶部:AIStatusBar + 标题 "日志" + SearchBar + 工地 chip / 分类 chip 两行
//  共用 state:`selectedSiteFilter` 同时驱动纵览 list 过滤和台账当日 LogEntry/Note 过滤
//  搜索语义:`searchText` 非空时自动切回 overview(避免"台账模式搜不到昨天的"困惑)
//

import SwiftUI
import SwiftData

struct LogTabView: View {
    /// 本 tab 是否当前激活。MainTabView 用 ZStack 常驻所有 tab,
    /// 切到别 tab 改了工地/分类再回来时,需要 `isActive` 边缘触发重读 UserDefaults。
    var isActive: Bool = true

    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.createdAt,
        order: .reverse
    ) var allNotes: [Note]

    @Query(
        filter: #Predicate<LogEntry> { $0.deletedAt == nil },
        sort: [SortDescriptor(\LogEntry.startAt)]
    ) var allEntries: [LogEntry]

    // MARK: - Mode

    /// 顶部 segment 的两个视角。
    /// - overview: 跨日纵览(原 BrowseView)
    /// - ledger:   当日台账(原 DiaryView)
    enum Mode: Hashable { case overview, ledger }

    @State private var mode: Mode = .overview

    // MARK: - 共用 state(顶部公共栏)

    @State private var searchText: String = ""
    @State var selectedSiteFilter: String?
    @State private var selectedSubTagFilter: String?
    @State private var availableSites: [String] = []
    @State private var availableSubTags: [SubTag] = []

    // MARK: - 纵览 mode 专属 state

    @State private var aiSearchEnabled: Bool = false
    @State private var semanticResults: [Note]?
    @State private var isSemanticSearching = false

    // 每个分组的折叠状态(独立 binding)
    // P1-2:纵览 mode 4 大段折叠状态。要盯/今天/待分类默认展开,归档默认折叠。
    @State private var urgentExpanded = true       // 要盯 = 隐患 + 逾期
    @State private var todayExpanded = true        // 今天到期
    @State private var inboxExpanded = true        // 待分类 = inbox(非隐患非日记) + 施工日记
    @State private var archivedExpanded = false    // 归档 = 3天/本周/以后/备忘/已完成

    private let listVM = NoteListViewModel()

    // MARK: - 台账 mode 专属 state

    @State var selectedDate: Date = Date()
    @State var selectedDaySegment: DaySegment = .person
    @State var editingLogEntry: LogEntry?

    @State var isGenerating: Bool = false
    @State var sharePDFURL: URL?
    @State var errorMessage: String?

    /// 台账 mode 内部的 4 个子 tab。
    /// 名字带 "Day" 前缀,避免和顶部 mode 的 segment 概念混淆。
    enum DaySegment: Hashable { case person, plant, event, notes }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    AIStatusBar()
                    titleAndSearch
                    filterRow
                    modeSegment
                    Divider().overlay(Ink.line)
                    mainContent
                    if mode == .ledger { bottomBar }
                }
            }
            .navigationBarHidden(true)
            .onAppear { reloadTagCaches() }
            .onChange(of: isActive) { _, becoming in
                if becoming { reloadTagCaches() }
            }
            .onChange(of: searchText) { _, newValue in
                // 搜索文本非空 → 自动切回纵览(原 Browse 行为)
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   mode != .overview {
                    mode = .overview
                }
                runSemanticSearchIfNeeded()
            }
            .onChange(of: aiSearchEnabled) { _, _ in runSemanticSearchIfNeeded() }
            .onChange(of: AppRouter.shared.pendingTab) { _, request in
                // 消费 AppRouter 信号的 logMode 部分。MainTabView 已切到 .log,这里切 mode。
                guard let r = request, r.tab == .log, let m = r.logMode else { return }
                mode = m
                if m == .ledger {
                    // 跳进台账时,默认看今天的"速记"段——这正是用户刚存的日志会出现的地方。
                    // 同时清掉残留的工地 / 分类 filter,否则用户原先筛着别的工地,
                    // 刚存的这条日志会被过滤掉看不见。
                    selectedSiteFilter = nil
                    selectedSubTagFilter = nil
                    selectedDate = Date()
                    selectedDaySegment = .notes
                }
                AppRouter.shared.clear()
            }
            .navigationDestination(for: Note.self) { note in
                NoteRouter(note: note)
            }
            .navigationDestination(for: SettingsDestination.self) { _ in
                SettingsView()
            }
            .navigationDestination(for: AIStatusDestination.self) { _ in
                InputAISettingsView()
            }
            .sheet(item: $editingLogEntry) { entry in
                LogEntryEditSheet(entry: entry) { deleted in
                    if deleted {
                        entry.deletedAt = Date()
                    }
                }
            }
            .sheet(item: Binding(
                get: { sharePDFURL.map { PDFShareItem(url: $0) } },
                set: { _ in sharePDFURL = nil }
            )) { item in
                ShareSheet(items: [item.url])
            }
            .alert("生成出错", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - 顶部公共栏:标题 + 搜索

    private var titleAndSearch: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("日志")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.8)
                    .foregroundStyle(Ink.fg)
                Spacer()
                SearchBarButton()
                NavigationLink(value: SettingsDestination()) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Ink.fgDim)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Ink.fgDim)
                TextField("搜索速记", text: $searchText)
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.fg)
                    .tint(Ink.fg)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Ink.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - 顶部公共栏:工地 chip + 分类 chip

    /// 两 mode 共用 chip 行。台账 mode 下,工地 chip 同时驱动当日 LogEntry/Note 的 site 过滤。
    /// 分类 chip 仅在纵览 mode 用得上(LogEntry 没 otherTags 概念),台账 mode 下隐藏第二行。
    private var filterRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 第 1 排:工地(含"全部")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    filterChip(
                        label: String(localized: "全部 \(siteAllCount)", locale: AppLanguageManager.currentLocale),
                        isOn: selectedSiteFilter == nil && selectedSubTagFilter == nil
                    ) {
                        selectedSiteFilter = nil
                        selectedSubTagFilter = nil
                    }
                    ForEach(availableSites, id: \.self) { tag in
                        let count = siteCount(tag)
                        filterChip(
                            label: "\(tag) \(count)",
                            isOn: selectedSiteFilter == tag
                        ) {
                            selectedSiteFilter = tag
                            selectedSubTagFilter = nil
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            // 第 2 排:分类(只在纵览 mode 显示;台账 mode 没 otherTags 概念)
            if mode == .overview, hasSubTagsWithNotes {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(availableSubTags) { sub in
                            let count = allNotes.filter { $0.otherTags.contains(sub.name) }.count
                            if count > 0 {
                                subFilterChip(
                                    label: "\(sub.name) \(count)",
                                    isOn: selectedSubTagFilter == sub.name,
                                    dotColor: sub.color
                                ) {
                                    selectedSubTagFilter = selectedSubTagFilter == sub.name ? nil : sub.name
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 8)
            } else {
                Spacer().frame(height: 8)
            }
        }
    }

    /// "全部" chip 显示的 count:纵览=所有 notes;台账=当日 notes(更直观)
    private var siteAllCount: Int {
        mode == .overview ? allNotes.count : todayNotes.count
    }

    /// 单个工地 chip 的 count:纵览=所有该工地 note;台账=当日该工地 note
    private func siteCount(_ tag: String) -> Int {
        if mode == .overview {
            return allNotes.filter { $0.siteTag == tag }.count
        }
        // 台账 mode:用 dayStart/dayEnd 限定
        return allNotes.filter {
            $0.siteTag == tag && $0.createdAt >= dayStart && $0.createdAt < dayEnd
        }.count
    }

    /// 是否有至少一个"实际被速记使用"的分类。没有就不渲染第二排。
    private var hasSubTagsWithNotes: Bool {
        availableSubTags.contains { sub in
            allNotes.contains(where: { $0.otherTags.contains(sub.name) })
        }
    }

    /// 工地筛选 chip(主级,字号 13,激活带下边线)。
    private func filterChip(
        label: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? Ink.fg : Ink.fgDim)
                Rectangle()
                    .fill(isOn ? Ink.fg : Color.clear)
                    .frame(height: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    /// 分类 chip(次级,字号 12,带色点,激活加粗)。
    private func subFilterChip(
        label: String,
        isOn: Bool,
        dotColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle().fill(dotColor).frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? Ink.fg : Ink.fgDim)
            }
            .padding(.vertical, 6)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mode segment(顶部两 mode 切换)

    private var modeSegment: some View {
        HStack(spacing: 0) {
            modeButton(.overview, label: String(localized: "纵览", locale: AppLanguageManager.currentLocale))
            modeButton(.ledger, label: String(localized: "台账", locale: AppLanguageManager.currentLocale))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func modeButton(_ m: Mode, label: String) -> some View {
        let isOn = mode == m
        return Button {
            mode = m
        } label: {
            VStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 14, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? Ink.fg : Ink.fgDim)
                Rectangle()
                    .fill(isOn ? Ink.fg : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main content router

    @ViewBuilder
    private var mainContent: some View {
        switch mode {
        case .overview: overviewBody
        case .ledger:   ledgerBody
        }
    }

    // ========================================================================
    // MARK: - 纵览 mode(原 BrowseView)
    // ========================================================================

    private var overviewBody: some View {
        listArea
    }

    // MARK: - Derived(纵览过滤)

    private var filtered: [Note] {
        var notes = allNotes
        if let filter = selectedSiteFilter {
            notes = notes.filter { $0.siteTag == filter }
        }
        if let subFilter = selectedSubTagFilter {
            notes = notes.filter { $0.otherTags.contains(subFilter) }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return notes }

        if aiSearchEnabled, let ai = semanticResults {
            let filterSet = Set(notes.map { $0.id })
            return ai.filter { filterSet.contains($0.id) }
        }

        let lower = q.lowercased()
        return notes.filter { note in
            note.transcription.lowercased().contains(lower)
                || (note.locationAddress?.lowercased().contains(lower) ?? false)
                || (note.siteTag?.lowercased().contains(lower) ?? false)
                || note.otherTags.contains(where: { $0.lowercased().contains(lower) })
                || (note.templateName?.lowercased().contains(lower) ?? false)
                || (note.contractClauseRef?.lowercased().contains(lower) ?? false)
        }
    }

    private var sections: NoteListViewModel.Sections {
        listVM.partition(filtered)
    }

    // P1-2 4 段聚合:
    //  - 要盯 = 隐患(任何状态)+ 逾期非隐患
    //  - 今天到期 = 今日到期非隐患
    //  - 待分类 = inbox(非隐患非日记)+ 施工日记
    //  - 归档 = 3 天/本周/以后/备忘/已完成 全部塞这里
    // 隐患优先级最高:从 inbox 和 pending 里都剔出来,避免一条隐患在两段重复出现。

    private var urgentGroup: [Note] {
        let hazards = (sections.pending + sections.inbox).filter { $0.isHazard }
        let overdue = sections.pending.filter {
            !$0.isHazard && listVM.urgency(for: $0) == .overdue
        }
        return hazards + overdue
    }

    private var todayGroup: [Note] {
        sections.pending.filter {
            !$0.isHazard && listVM.urgency(for: $0) == .day
        }
    }

    private var inboxGroup: [Note] {
        let inboxClean = sections.inbox.filter { !$0.isHazard && !$0.isDiaryRecord }
        let diary = (sections.pending + sections.inbox).filter { $0.isDiaryRecord }
        return inboxClean + diary
    }

    private var archivedGroup: [Note] {
        let futures = sections.pending.filter {
            !$0.isHazard && [.threeDays, .week, .future].contains(listVM.urgency(for: $0))
        }
        return futures + sections.archived + sections.done
    }

    // MARK: - 纵览列表

    @ViewBuilder
    private var listArea: some View {
        if sections.inbox.isEmpty && sections.pending.isEmpty
            && sections.archived.isEmpty && sections.done.isEmpty {
            emptyOverviewState
        } else {
            List {
                if !urgentGroup.isEmpty {
                    overviewSection(title: String(localized: "要盯", locale: AppLanguageManager.currentLocale), color: Ink.red, notes: urgentGroup, expanded: $urgentExpanded)
                }
                if !todayGroup.isEmpty {
                    overviewSection(title: String(localized: "今天到期", locale: AppLanguageManager.currentLocale), color: Ink.fg, notes: todayGroup, expanded: $todayExpanded)
                }
                if !inboxGroup.isEmpty {
                    overviewSection(title: String(localized: "待分类", locale: AppLanguageManager.currentLocale), color: Ink.fgDim, notes: inboxGroup, expanded: $inboxExpanded)
                }
                if !archivedGroup.isEmpty {
                    overviewSection(title: String(localized: "归档", locale: AppLanguageManager.currentLocale), color: Ink.dim, notes: archivedGroup, expanded: $archivedExpanded)
                }
            }
            .listStyle(.plain)
            .industrialForm()
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    /// 纵览 mode 的可折叠 Section。
    @ViewBuilder
    private func overviewSection(
        title: String,
        color: Color,
        notes: [Note],
        expanded: Binding<Bool>
    ) -> some View {
        Section {
            if expanded.wrappedValue {
                ForEach(notes) { note in
                    NavigationLink(value: note) {
                        NoteRow(note: note, urgency: listVM.urgency(for: note))
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Ink.bg)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            toggleDone(note)
                        } label: {
                            Label(
                                note.isDone ? "未完成" : "完成",
                                systemImage: note.isDone ? "arrow.uturn.left" : "checkmark"
                            )
                        }
                        .tint(Ink.fg)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            softDelete(note)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .tint(Ink.red)
                    }
                }
            }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(color)
                    Spacer()
                    Text("\(notes.count)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Ink.dim)
                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Ink.dim)
                        .padding(.leading, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .textCase(nil)
        }
    }

    private var emptyOverviewState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(Ink.dim)
            Text(searchText.isEmpty ? "还没有速记" : "没有匹配的速记")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Ink.fgDim)
            Text("切回「记」按住麦克风开始")
                .font(.system(size: 12))
                .foregroundStyle(Ink.dim)
            // 没建过工地?加个 CTA。AI 分类离了它跑不准。
            if availableSites.isEmpty {
                NavigationLink(value: SettingsDestination()) {
                    HStack(spacing: 6) {
                        Image(systemName: "building.2")
                        Text("先建第一个工地")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Ink.fg, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 纵览 actions

    private func toggleDone(_ note: Note) {
        note.isDone.toggle()
        if note.isDone {
            NotificationService.shared.cancel(for: note)
        } else {
            NotificationService.shared.schedule(for: note)
        }
    }

    private func softDelete(_ note: Note) {
        NotificationService.shared.cancel(for: note)
        note.deletedAt = Date()
    }

    /// 重读工地 / 分类列表,并清掉已不存在的过滤。在 onAppear 和 tab 激活时调。
    private func reloadTagCaches() {
        availableSites = SiteTagsStorage.load()
        availableSubTags = SubTagsStorage.load()
        if let s = selectedSiteFilter, !availableSites.contains(s) {
            selectedSiteFilter = nil
        }
        if let s = selectedSubTagFilter,
           !availableSubTags.contains(where: { $0.name == s }) {
            selectedSubTagFilter = nil
        }
    }

    private func runSemanticSearchIfNeeded() {
        guard aiSearchEnabled else {
            semanticResults = nil
            return
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            semanticResults = nil
            return
        }
        isSemanticSearching = true
        let snapshot = allNotes
        Task {
            let results = await SemanticSearchService.shared.search(query: q, in: snapshot)
            semanticResults = results
            isSemanticSearching = false
        }
    }

}

/// PDF 分享 sheet 用的包装。台账 mode 生成 PDF 后丢给系统分享。
private struct PDFShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, ShareLog.self, configurations: config)
    return LogTabView().modelContainer(container)
}
