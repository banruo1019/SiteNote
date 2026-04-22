//
//  BrowseView.swift
//  SiteNote
//
//  M1 "Linear 极简白"总帐:
//  - 大标题 "笔记"(28pt 600)
//  - 搜索框(Ink.card 底 8pt 圆角)
//  - 文字式 filter chips(无胶囊,激活=字重+下边线)
//  - 分组列表(分组 header 11pt 600 大写 + 右侧 count)
//  - 每行:左 6pt 色点 + 正文 14pt + 元信息 11pt
//

import SwiftUI
import SwiftData

struct BrowseView: View {
    /// 本 tab 是否当前激活。MainTabView 用 ZStack 常驻三个 tab view,
    /// 所以 `onAppear` 只触发一次(app 启动)。切到别的 tab 改了工地标签/子标签再回来时,
    /// 需要靠 `isActive` 变成 true 的边缘来重读 UserDefaults。
    var isActive: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.createdAt,
        order: .reverse
    ) private var allNotes: [Note]

    @State private var selectedSiteFilter: String?
    @State private var selectedSubTagFilter: String?
    @State private var availableTags: [String] = []
    @State private var availableSubTags: [SubTag] = []
    @State private var searchText: String = ""

    @State private var aiSearchEnabled: Bool = false
    @State private var semanticResults: [Note]?
    @State private var isSemanticSearching = false

    // 每个分组的折叠状态(独立 binding,不复用)
    @State private var inboxExpanded = true
    @State private var hazardExpanded = true
    @State private var overdueExpanded = true
    @State private var todayExpanded = true
    @State private var threeDayExpanded = true
    @State private var weekExpanded = true
    @State private var laterExpanded = false
    @State private var diaryExpanded = false
    @State private var archivedExpanded = false
    @State private var doneExpanded = false

    private let listVM = NoteListViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    AIStatusBar()
                    titleAndSearch
                    filterRow
                    Divider().overlay(Ink.line)
                    listArea
                }
            }
            .navigationBarHidden(true)
            .onAppear { reloadTagCaches() }
            .onChange(of: isActive) { _, becoming in
                if becoming { reloadTagCaches() }
            }
            .onChange(of: searchText) { _, _ in runSemanticSearchIfNeeded() }
            .onChange(of: aiSearchEnabled) { _, _ in runSemanticSearchIfNeeded() }
            .navigationDestination(for: Note.self) { note in
                NoteRouter(note: note)
            }
            .navigationDestination(for: AIStatusDestination.self) { _ in
                InputAISettingsView()
            }
        }
    }

    // MARK: - Derived

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

    // 隐患和各紧迫度组**互斥**:hazard 优先吃掉其他档。
    // 这样一条"逾期的隐患"只出现在隐患组,不在逾期组重复。
    //
    // 施工日记(isDiaryRecord)**只从 inbox/待分类 里退出**,汇总到独立的 diaryGroup。
    // urgency 组不过滤——"水工来了 4 个,今天下午验收"这种混合 note 应该同时出现在今天组和 diary 组。
    // hazard 组不过滤——安全信号永远要看到。
    private var hazardGroup: [Note] {
        (sections.pending + sections.inbox).filter { $0.isHazard }
    }
    private var overdueGroup: [Note] {
        sections.pending.filter {
            !$0.isHazard && listVM.urgency(for: $0) == .overdue
        }
    }
    private var todayGroup: [Note] {
        sections.pending.filter {
            !$0.isHazard && listVM.urgency(for: $0) == .day
        }
    }
    private var threeDayGroup: [Note] {
        sections.pending.filter {
            !$0.isHazard && listVM.urgency(for: $0) == .threeDays
        }
    }
    private var weekGroup: [Note] {
        sections.pending.filter {
            !$0.isHazard && listVM.urgency(for: $0) == .week
        }
    }
    private var laterGroup: [Note] {
        sections.pending.filter {
            !$0.isHazard && listVM.urgency(for: $0) == .future
        }
    }
    /// inbox 非 hazard 非施工日记(inbox 的 hazard 归 hazard 组,日记归 diary 组)。
    private var inboxNonHazard: [Note] {
        sections.inbox.filter { !$0.isHazard && !$0.isDiaryRecord }
    }
    /// 施工日记:任何被 AI 抽出过 LogEntry 的条目(pending 或 inbox)。
    private var diaryGroup: [Note] {
        (sections.pending + sections.inbox).filter { $0.isDiaryRecord }
    }

    // MARK: - Title + search

    private var titleAndSearch: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("笔记")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.8)
                    .foregroundStyle(Ink.fg)
                Spacer()
                NavigationLink(value: SettingsDestination()) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Ink.fgDim)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Ink.fgDim)
                TextField("搜索笔记", text: $searchText)
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
        .navigationDestination(for: SettingsDestination.self) { _ in
            SettingsView()
        }
    }

    // MARK: - Filter row (text style)

    private var filterRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 第 1 排:工地(含"全部")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    filterChip(
                        label: "全部 \(allNotes.count)",
                        isOn: selectedSiteFilter == nil && selectedSubTagFilter == nil
                    ) {
                        selectedSiteFilter = nil
                        selectedSubTagFilter = nil
                    }
                    ForEach(availableTags, id: \.self) { tag in
                        let count = allNotes.filter { $0.siteTag == tag }.count
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

            // 第 2 排:其他(子标签),整排按 dim 色,视觉次于工地
            // 只有存在至少一个非空子标签时才显示
            if hasSubTagsWithNotes {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        // 辅助性"其他"标签文字,视觉上和工地分层
                        Text("其他")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Ink.dim)
                            .padding(.trailing, 2)

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

    /// 是否有至少一个"实际被笔记使用"的子标签。没有就不渲染第二排。
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

    /// 子标签 chip(次级,字号 12,带色点,激活加粗)。
    /// 不用下划线,用色点区分分层。
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

    private func filterChip(
        label: String,
        isOn: Bool,
        dotColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    if let dotColor {
                        Circle().fill(dotColor).frame(width: 6, height: 6)
                    }
                    Text(label)
                        .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Ink.fg : Ink.fgDim)
                }
                Rectangle()
                    .fill(isOn ? Ink.fg : Color.clear)
                    .frame(height: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - List (用 List 驱动 swipeActions,每 section 可折叠)

    @ViewBuilder
    private var listArea: some View {
        if sections.inbox.isEmpty && sections.pending.isEmpty
            && sections.archived.isEmpty && sections.done.isEmpty {
            emptyState
        } else {
            List {
                if !hazardGroup.isEmpty {
                    section(title: "隐患", color: Ink.red, notes: hazardGroup, expanded: $hazardExpanded)
                }
                if !overdueGroup.isEmpty {
                    section(title: "逾期", color: Ink.red, notes: overdueGroup, expanded: $overdueExpanded)
                }
                if !todayGroup.isEmpty {
                    section(title: "今天", color: Ink.fg, notes: todayGroup, expanded: $todayExpanded)
                }
                if !threeDayGroup.isEmpty {
                    section(title: "3 天内", color: Ink.fgDim, notes: threeDayGroup, expanded: $threeDayExpanded)
                }
                if !weekGroup.isEmpty {
                    section(title: "本周", color: Ink.fgDim, notes: weekGroup, expanded: $weekExpanded)
                }
                if !laterGroup.isEmpty {
                    section(title: "以后", color: Ink.fgDim, notes: laterGroup, expanded: $laterExpanded)
                }
                if !inboxNonHazard.isEmpty {
                    section(title: "待分类", color: Ink.fgDim, notes: inboxNonHazard, expanded: $inboxExpanded)
                }
                if !diaryGroup.isEmpty {
                    section(title: "施工日记", color: Ink.accentBlue, notes: diaryGroup, expanded: $diaryExpanded)
                }
                if !sections.archived.isEmpty {
                    section(title: "备忘", color: Ink.fgDim, notes: sections.archived, expanded: $archivedExpanded)
                }
                if !sections.done.isEmpty {
                    section(title: "已完成", color: Ink.fgDim, notes: sections.done, expanded: $doneExpanded)
                }
            }
            .listStyle(.plain)
            .industrialForm()
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    /// 一个可折叠的 Section:
    /// - header 是按钮,点击 toggle `expanded`
    /// - 展开时 ForEach 渲染 NoteRow,每行带 leading/trailing swipeActions
    /// - List 结构是必须的,否则 swipeActions 不会被识别
    @ViewBuilder
    private func section(
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
            .textCase(nil) // 防止 List 的 section header 默认 uppercase 重叠我的样式
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(Ink.dim)
            Text(searchText.isEmpty ? "还没有笔记" : "没有匹配的笔记")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Ink.fgDim)
            Text("切回「记」按住麦克风开始")
                .font(.system(size: 12))
                .foregroundStyle(Ink.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

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

    /// 重读工地 / 子标签列表,并清掉已不存在的过滤。在 onAppear 和 tab 激活时调。
    private func reloadTagCaches() {
        availableTags = SiteTagsStorage.load()
        availableSubTags = SubTagsStorage.load()
        if let s = selectedSiteFilter, !availableTags.contains(s) {
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

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, configurations: config)
    return BrowseView().modelContainer(container)
}
