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
    /// 月视图打点 + 当日列表 + 即将到来段都基于这份。
    /// 只读未完成、未删除的速记;由 SwiftData 按 dueDate 升序提供。
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil && $0.isDone == false },
        sort: \Note.dueDate
    ) private var pendingNotes: [Note]

    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    titleRow
                    ScrollView {
                        VStack(spacing: 0) {
                            headerHint
                            monthHeader
                            calendarGrid
                            divider
                            dayDetailSection
                            divider
                            upcomingSection
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

    // MARK: - Header hint

    private var headerHint: some View {
        Text(String(localized: "按截止日期看待办,点开看当天的速记。", locale: AppLanguageManager.currentLocale))
            .font(.system(size: 12))
            .foregroundStyle(Ink.fgDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
    }

    // MARK: - Month header

    private var monthHeader: some View {
        HStack(spacing: 0) {
            Button {
                if let prev = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        currentMonth = prev
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.fg2)
                    .frame(width: 40, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthLabel)
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Ink.fg)
                .monospacedDigit()

            Spacer()

            Button {
                if let next = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        currentMonth = next
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.fg2)
                    .frame(width: 40, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = AppLanguageManager.currentLocale
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f.string(from: currentMonth)
    }

    // MARK: - Calendar grid

    /// 当月的 cell 列表(含为对齐第一行的占位 cell)。
    /// 用 Calendar.current.firstWeekday 决定第一列是星期几,跟系统设置一致。
    private var calendarCells: [CalendarDayCell] {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
        let range = cal.range(of: .day, in: .month, for: monthStart) ?? 1..<2
        let firstWeekdayOfMonth = cal.component(.weekday, from: monthStart) // 1...7
        let leadingEmpty = (firstWeekdayOfMonth - cal.firstWeekday + 7) % 7

        var cells: [CalendarDayCell] = []
        for _ in 0..<leadingEmpty {
            cells.append(CalendarDayCell(date: nil))
        }
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: monthStart) {
                cells.append(CalendarDayCell(date: d))
            }
        }
        // 末尾占位到 42(6 行)— 固定高度,避免月切换时高度跳变。
        while cells.count < 42 {
            cells.append(CalendarDayCell(date: nil))
        }
        return cells
    }

    private var weekdayLabels: [String] {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = AppLanguageManager.currentLocale
        let symbols = f.veryShortStandaloneWeekdaySymbols ?? [] // index 0 = Sunday
        guard symbols.count == 7 else { return [] }
        let offset = cal.firstWeekday - 1
        return (0..<7).map { symbols[(offset + $0) % 7] }
    }

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Ink.fgDim)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(calendarCells.enumerated()), id: \.offset) { _, cell in
                    cellView(cell)
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
        return pendingNotes.contains { $0.dueDate >= monthStart && $0.dueDate < monthEnd }
    }

    @ViewBuilder
    private func cellView(_ cell: CalendarDayCell) -> some View {
        if let date = cell.date {
            let cal = Calendar.current
            let isToday = cal.isDateInToday(date)
            let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
            let dayNotes = notes(on: date)
            let hasItems = !dayNotes.isEmpty
            let hasHazard = dayNotes.contains(where: { $0.isHazard })
            let day = cal.component(.day, from: date)

            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    selectedDate = cal.startOfDay(for: date)
                }
            } label: {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Ink.fg)
                    } else if isToday {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Ink.fg, lineWidth: 1)
                    }
                    Text("\(day)")
                        .font(.system(size: 14, weight: isToday || isSelected ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(cellTextColor(isSelected: isSelected, isToday: isToday))
                    if hasItems {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Circle()
                                    .fill(dotColor(isSelected: isSelected, isHazard: hasHazard))
                                    .frame(width: 4, height: 4)
                                    .padding(.trailing, 6)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                }
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(height: 38)
        }
    }

    private func cellTextColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return Ink.bg }
        if isToday { return Ink.fg }
        return Ink.fg
    }

    /// 选中态优先反白成背景色,否则隐患红 / 普通 Ink.fg。
    private func dotColor(isSelected: Bool, isHazard: Bool) -> Color {
        if isSelected { return Ink.bg }
        return isHazard ? Ink.red : Ink.fg
    }

    // MARK: - 当日列表

    /// 落在指定日期(同一天)的所有未完成 Note。按时间升序。
    /// 注:Note.deadline 已经在 dueDate(from:) 里推算了具体 dueDate,
    ///     直接按 dueDate 在同一天匹配即可,不需要再判断 deadline 档位。
    private func notes(on date: Date) -> [Note] {
        let cal = Calendar.current
        return pendingNotes
            .filter { cal.isDate($0.dueDate, inSameDayAs: date) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var notesOnSelectedDate: [Note] {
        notes(on: selectedDate)
    }

    private var dayDetailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDateLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Ink.fgDim)
                Spacer()
                Text(String(localized: "\(notesOnSelectedDate.count) 项", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.dim)
                    .monospacedDigit()
            }

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
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    private var selectedDateLabel: String {
        let f = DateFormatter()
        f.locale = AppLanguageManager.currentLocale
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        return f.string(from: selectedDate)
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
            HStack(alignment: .top, spacing: 12) {
                // 左侧 vertical bar — 隐患红,其他 fg
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(note.isHazard ? Ink.red : Ink.fg)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if let tag = note.siteTag, !tag.isEmpty {
                            Text(tag)
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.3)
                                .textCase(.uppercase)
                                .foregroundStyle(Ink.fgDim)
                        }
                        if note.isHazard {
                            Text(String(localized: "隐患", locale: AppLanguageManager.currentLocale))
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.5)
                                .textCase(.uppercase)
                                .foregroundStyle(Ink.red)
                        }
                        Spacer()
                        Text(timeLabel(note.dueDate))
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                            .monospacedDigit()
                    }
                    Text(noteSummary(note))
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.fg)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.dim)
                    .padding(.top, 4)
            }
            .padding(.vertical, 12)
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
        let f = DateFormatter()
        f.locale = AppLanguageManager.currentLocale
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: - 即将到来

    /// 今天起未完成 Note,按 dueDate 升序前 5 条。
    /// dueDate 已经在 Deadline.dueDate(from:) 里推算好;archive/inbox 推 100 年后,
    /// 5 条阈值远小于这个量级,所以不会被它们污染。
    private var upcomingNotes: [Note] {
        let today = Calendar.current.startOfDay(for: Date())
        return pendingNotes
            .filter { $0.dueDate >= today }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(5)
            .map { $0 }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "即将到来", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Ink.fgDim)

            if upcomingNotes.isEmpty {
                Text(String(localized: "近期没有待办的速记", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.fgDim)
                    .padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(upcomingNotes) { note in
                        upcomingRow(note)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 32)
    }

    private func upcomingRow(_ note: Note) -> some View {
        NavigationLink(value: note) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(relativeDateLabel(note.dueDate))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.3)
                        .textCase(.uppercase)
                        .foregroundStyle(Ink.fg)
                        .monospacedDigit()
                    Text(timeLabel(note.dueDate))
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                        .monospacedDigit()
                }
                .frame(width: 76, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(noteSummary(note))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(note.isHazard ? Ink.red : Ink.fg)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let tag = note.siteTag, !tag.isEmpty {
                        Text(tag)
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.dim)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: 1)
        }
    }

    /// "今天" / "明天" / "MMM d"
    private func relativeDateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return String(localized: "今天", locale: AppLanguageManager.currentLocale)
        }
        if cal.isDateInTomorrow(date) {
            return String(localized: "明天", locale: AppLanguageManager.currentLocale)
        }
        let f = DateFormatter()
        f.locale = AppLanguageManager.currentLocale
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: date)
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle().fill(Ink.line).frame(height: 1)
    }
}

// MARK: - Helpers

private struct CalendarDayCell {
    let date: Date?
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, configurations: config)
    return PMCalendarView().modelContainer(container)
}
