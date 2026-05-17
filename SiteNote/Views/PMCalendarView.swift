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
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    titleRow
                    ScrollView {
                        VStack(spacing: 0) {
                            monthHeader
                            calendarGrid
                            divider
                            dayDetailSection
                            // v1.3 用户决定:删"近期"段。日历就只看当日。
                        }
                    }
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

    private var dayDetailSection: some View {
        VStack(alignment: .leading, spacing: 6) {
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

            if !monthHasAnyNote {
                emptyMonthState
            } else if notesOnSelectedDate.isEmpty {
                emptyDayState
            } else {
                VStack(spacing: 0) {
                    ForEach(notesOnSelectedDate) { note in
                        noteRow(note)
                    }
                }
            }
        }
        .padding(.bottom, 20)
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

    private func noteRow(_ note: Note) -> some View {
        NavigationLink(value: note) {
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
                        .foregroundStyle(note.isHazard ? Ink.red : Ink.fg)
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.dim)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: 1)
        }
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
