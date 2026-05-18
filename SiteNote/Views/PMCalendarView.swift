//
//  PMCalendarView.swift
//  SiteNote
//
//  PM Profile · 日历 tab(v1.3 3-Tab 重构新增)。
//  数据源:Note.dueDate(未完成、未删除的速记)。
//  与 EngineerScheduleView 结构对齐,但只读 — 不在月视图里改状态,
//  点击当日 row 直接进 NoteDetailView 编辑。
//
//  Layout:
//  - 顶部 titleRow:"日历" + 齿轮按钮(进 SettingsDestination)
//  - 月视图(7 列 LazyVGrid):dot 表示当天有 dueDate;隐患 dot 用红色,普通用 Ink.fg
//  - 当日列表:siteTag · transcription 摘要 · 时间(小字),NavigationLink 进 NoteRouter
//  - 即将到来:今天往后未完成 Note 按 dueDate 升序前 5 条
//

import SwiftUI
import SwiftData

struct PMCalendarView: View {
    /// 月视图打点 + 当日列表都基于这份。
    /// **包括已完成的 Note**(用户要求:当日完成的也显示)。
    /// 不再过滤 isDone — 完成的也在 dueDate 当天显示,UI 用 ✓ 标记。
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.dueDate
    ) private var pendingNotes: [Note]

    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    /// 工地过滤器:nil = 全部工地。用户在顶部 menu 切换。
    @State private var siteFilter: String? = nil
    /// v1.6:已完成段是否展开 — 默认折叠(待办优先视野)。
    @State private var doneExpanded: Bool = false
    /// v1.6:待办段也可折叠,默认展开。
    @State private var pendingExpanded: Bool = true
    /// v1.6:NavigationStack path — 改成 path-based 让 noteRow 用 Button 跳详情(避免 List
    /// 自动给 NavigationLink 加 chevron — 用户要求行末不显示箭头)。
    /// 用 type-erased `NavigationPath` 支持混合类型 push:Note(详情)+ SettingsDestination(齿轮)。
    /// 之前用 `[Note]` 类型化 path 导致齿轮 NavigationLink push 不进去 — 点击无反应。
    @State private var navPath: NavigationPath = NavigationPath()

    /// 应用工地 filter 后的 Note 池(月视图打点 + 当日列表都基于这份)。
    private var notesForCalendar: [Note] {
        if let site = siteFilter {
            return pendingNotes.filter { $0.siteTag == site }
        }
        return Array(pendingNotes)
    }

    /// 已知工地 tag(从 Note + SiteTagsStorage 合并),给顶部 picker 用。
    private var allSiteTags: [String] {
        let fromNotes = Set(pendingNotes.compactMap { $0.siteTag })
        let configured = Set(SiteTagsStorage.load())
        return Array(fromNotes.union(configured)).sorted()
    }

    var body: some View {
        // v1.6:整 body 改 List(原 ScrollView)以支持 .swipeActions(必须 List 内才生效)。
        // monthHeader / grid / 当日详情都进 List section,plain style + 透明背景保持原视觉。
        NavigationStack(path: $navPath) {
            ZStack {
                Ink.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    titleRow
                    List {
                        Section {
                            monthHeader
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                            calendarGrid
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                        }
                        dayDetailListSections
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: SettingsDestination.self) { _ in
                SettingsView()
            }
            .navigationDestination(for: Note.self) { note in
                NoteRouter(note: note)
            }
        }
    }

    // MARK: - Title row

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "日历", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Ink.fg)
            Spacer()
            siteFilterMenu
            NavigationLink(value: SettingsDestination()) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Ink.fgDim)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    /// 工地过滤 menu — 共享组件 `SiteFilterMenu`。
    private var siteFilterMenu: some View {
        SiteFilterMenu(allTags: allSiteTags, selection: $siteFilter)
    }

    // MARK: - Month header

    private var monthHeader: some View {
        MonthNavigationHeader(currentMonth: $currentMonth)
    }

    // MARK: - Calendar grid

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(spacing: 6) {
            WeekdayHeaderRow()

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(CalendarHelpers.monthCells(for: currentMonth).enumerated()), id: \.offset) { _, date in
                    cellView(for: date)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    /// 月视图本月有 dueDate 的 Note 总数,用于"空态"判断(没有 → 中央提示)。
    private var monthHasAnyNote: Bool {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth)),
              let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return false }
        return notesForCalendar.contains { $0.dueDate >= monthStart && $0.dueDate < monthEnd }
    }

    @ViewBuilder
    private func cellView(for cellDate: Date?) -> some View {
        if let date = cellDate {
            let cal = Calendar.current
            let isToday = cal.isDateInToday(date)
            let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
            let dayNotes = notes(on: date)
            let hasHazard = dayNotes.contains(where: { $0.isHazard })
            let dotCount = min(dayNotes.count, 3)
            let day = cal.component(.day, from: date)
            // M1:今天 = 黑圆填充;选中(非今天)= 1px Ink.fg 描边圆,对比更明确;否则透明
            let bgFill: Color = isToday ? Ink.fg : .clear
            let textColor: Color = isToday ? Ink.bg : Ink.fg
            let selectedBorder: Bool = isSelected && !isToday

            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    selectedDate = cal.startOfDay(for: date)
                }
            } label: {
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(bgFill)
                            .frame(width: 26, height: 26)
                        if selectedBorder {
                            Circle()
                                .stroke(Ink.fg, lineWidth: 1.5)
                                .frame(width: 26, height: 26)
                        }
                        Text("\(day)")
                            .font(.system(size: 13, weight: isToday || selectedBorder ? .semibold : .medium))
                            .monospacedDigit()
                            .foregroundStyle(textColor)
                    }
                    HStack(spacing: 2.5) {
                        ForEach(0..<dotCount, id: \.self) { idx in
                            Circle()
                                .fill(dotColorAt(index: idx, hasHazard: hasHazard, isToday: isToday))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
                .frame(height: 42)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(height: 42)
        }
    }

    /// 每颗 dot 的颜色:第一颗如果有 hazard 用红,其他用 Ink.fg(今天的反白处理)。
    private func dotColorAt(index: Int, hasHazard: Bool, isToday: Bool) -> Color {
        if index == 0 && hasHazard { return Ink.red }
        return isToday ? Ink.bg : Ink.fg.opacity(0.55)
    }

    // MARK: - 当日列表

    /// 落在指定日期(同一天)的所有未完成 Note。按时间升序。
    /// 注:Note.deadline 已经在 dueDate(from:) 里推算了具体 dueDate,
    ///     直接按 dueDate 在同一天匹配即可,不需要再判断 deadline 档位。
    private func notes(on date: Date) -> [Note] {
        let cal = Calendar.current
        return notesForCalendar
            .filter { cal.isDate($0.dueDate, inSameDayAs: date) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var notesOnSelectedDate: [Note] {
        notes(on: selectedDate)
    }

    /// 当日详情段 — 拆 待办 / 已完成,各自一个 Section + 可选折叠。
    /// 以 @ViewBuilder 返回 多 Section 直接在 body 的 List 里展开。
    @ViewBuilder
    private var dayDetailListSections: some View {
        // 日期 header(作为单独一行,顶部 padding 跟原版一致)
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(selectedDateLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Ink.fg)
                if Calendar.current.isDateInToday(selectedDate) {
                    Text(String(localized: "· 今天", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }

        if !monthHasAnyNote {
            Section {
                emptyMonthState
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        } else if notesOnSelectedDate.isEmpty {
            Section {
                emptyDayState
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        } else {
            let pending = notesOnSelectedDate.filter { !$0.isDone }
            let done = notesOnSelectedDate.filter { $0.isDone }

            if !pending.isEmpty {
                Section {
                    if pendingExpanded {
                        ForEach(pending) { note in
                            calNoteRowItem(note)
                        }
                    }
                } header: {
                    sectionHeader(
                        title: String(localized: "待办", locale: AppLanguageManager.currentLocale),
                        count: pending.count,
                        foldable: true,
                        expanded: $pendingExpanded
                    )
                }
            }
            if !done.isEmpty {
                Section {
                    if doneExpanded {
                        ForEach(done) { note in
                            calNoteRowItem(note)
                        }
                    }
                } header: {
                    sectionHeader(
                        title: String(localized: "已完成", locale: AppLanguageManager.currentLocale),
                        count: done.count,
                        foldable: true,
                        expanded: $doneExpanded
                    )
                }
            }
        }
    }

    /// 选中日的友好标签 — 例如 "周三 5 月 17"。
    private var selectedDateLabel: String {
        Formatters.weekdayMonthDay.string(from: selectedDate)
    }

    private var emptyDayState: some View {
        Text(String(localized: "这天没有待办的速记", locale: AppLanguageManager.currentLocale))
            .font(.system(size: 13))
            .foregroundStyle(Ink.fgDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
    }

    private var emptyMonthState: some View {
        Text(String(localized: "这个月没有待办的速记", locale: AppLanguageManager.currentLocale))
            .font(.system(size: 14))
            .foregroundStyle(Ink.fgDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
    }

    /// 单行(v1.6 改 Button + swipe + contextMenu):
    /// - Button 替代 NavigationLink(去 List 自动 chevron)
    /// - 左滑 → [✓ 完成] / [↺ 未完成] 胶囊,必须点击(allowsFullSwipe: false 防误触)
    /// - 长按 → contextMenu「删除」(软删进垃圾桶)
    /// - 行末**不**显示 chevron(用户要求)
    @ViewBuilder
    private func calNoteRowItem(_ note: Note) -> some View {
        Button {
            navPath.append(note)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(note.isHazard ? Ink.red : Ink.fg)
                    .frame(width: 6, height: 6)
                Text(timeLabel(note.dueDate))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.fgDim)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(noteSummary(note))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            note.isHazard ? Ink.red : (note.isDone ? Ink.fgDim : Ink.fg)
                        )
                        .strikethrough(note.isDone)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    if let site = note.siteTag, !site.isEmpty {
                        Text(site)
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: 1)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Ink.bg)
        // v1.6:右滑(leading)→ 完成 toggle;左滑(trailing)→ 删除。
        // 两个方向都允许 full swipe(滑到底直接触发),贴近 Apple Mail 习惯。
        // contextMenu 长按删除保留作 backup 入口。
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                softDelete(note)
            } label: {
                Label(String(localized: "删除", locale: AppLanguageManager.currentLocale), systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                softDelete(note)
            } label: {
                Label(String(localized: "删除", locale: AppLanguageManager.currentLocale), systemImage: "trash")
            }
        }
    }

    /// Section header — 标题左 + 计数 chip + (可选)折叠 chevron。
    /// 跟 RecordView.sectionHeader 同款,本地复刻保持视觉一致。
    private func sectionHeader(
        title: String,
        count: Int,
        foldable: Bool,
        expanded: Binding<Bool>
    ) -> some View {
        Button {
            if foldable {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.wrappedValue.toggle()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Ink.fgDim)
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Ink.fg2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Ink.card)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Spacer()
                if foldable {
                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.dim)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!foldable)
        .textCase(nil)
    }

    /// 切换 isDone — 完成时取消通知,反向切回时重新排通知。
    private func toggleDone(_ note: Note) {
        note.isDone.toggle()
        if note.isDone {
            NotificationService.shared.cancel(for: note)
        } else {
            NotificationService.shared.schedule(for: note)
        }
    }

    /// 软删进垃圾桶(30 天可恢复)。取消任何已排通知。
    private func softDelete(_ note: Note) {
        NotificationService.shared.cancel(for: note)
        note.deletedAt = Date()
    }

    /// transcription 摘要 — 空时给个回落占位,避免一行空白。
    private func noteSummary(_ note: Note) -> String {
        let text = note.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return String(localized: "(无内容)", locale: AppLanguageManager.currentLocale)
        }
        return text
    }

    private func timeLabel(_ date: Date) -> String {
        Formatters.hourMinute.string(from: date)
    }

    // v1.3:删整段 "即将到来" — 用户只想看当日。

    // MARK: - Divider

    private var divider: some View {
        Rectangle().fill(Ink.line).frame(height: 1)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, configurations: config)
    return PMCalendarView().modelContainer(container)
}
