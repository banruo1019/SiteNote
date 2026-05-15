//
//  EngineerScheduleView.swift
//  SiteNote
//
//  Engineer Profile · 日程 tab。
//  Linear 极简白风格(参考 ReportsView 的 titleRow / 卡片 padding):
//  - titleRow:"日程" + "+ 新建"
//  - 月视图(LazyVGrid 7 列):点选日期 + 当天 dot
//  - 当日详情列表:vertical bar 状态 / 时间 / 标题 / siteTag / 完成 icon / contextMenu
//  - 即将到来:未完成 + scheduledDate >= 今天,按 fireDate 升序前 10 条
//

import SwiftUI
import SwiftData

struct EngineerScheduleView: View {
    @Environment(\.modelContext) private var modelContext

    /// 所有未删除日程 — 月视图 dot + 当日列表 + 即将到来都用它过滤。
    /// 不在 query 里 predicate 状态,因为月视图需要看所有状态的日程。
    @Query(
        filter: #Predicate<SiteVisitSchedule> { $0.deletedAt == nil },
        sort: [SortDescriptor(\SiteVisitSchedule.scheduledDate)]
    ) private var allSchedules: [SiteVisitSchedule]

    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showEditor: Bool = false
    @State private var editingSchedule: SiteVisitSchedule? = nil

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
                            divider
                            upcomingSection
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showEditor, onDismiss: {
                editingSchedule = nil
            }) {
                ScheduleEditorSheet(
                    schedule: editingSchedule,
                    prefilledDate: editingSchedule == nil ? selectedDate : nil
                )
            }
        }
    }

    // MARK: - Title row

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "日程", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Ink.fg)
            Spacer()
            Button {
                editingSchedule = nil
                showEditor = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text(String(localized: "新建", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Ink.fg)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Ink.line2, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
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
                .font(.system(size: 16, weight: .semibold))
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
        .padding(.top, 8)
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
    private var calendarCells: [CalendarCell] {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
        let range = cal.range(of: .day, in: .month, for: monthStart) ?? 1..<2
        let firstWeekdayOfMonth = cal.component(.weekday, from: monthStart) // 1...7
        let leadingEmpty = (firstWeekdayOfMonth - cal.firstWeekday + 7) % 7

        var cells: [CalendarCell] = []
        for _ in 0..<leadingEmpty {
            cells.append(CalendarCell(date: nil))
        }
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: monthStart) {
                cells.append(CalendarCell(date: d))
            }
        }
        // 末尾占位到 42(6 行)— 月视图固定高度,避免月切换时高度跳变。
        while cells.count < 42 {
            cells.append(CalendarCell(date: nil))
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

    @ViewBuilder
    private func cellView(_ cell: CalendarCell) -> some View {
        if let date = cell.date {
            let cal = Calendar.current
            let isToday = cal.isDateInToday(date)
            let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
            let hasItems = hasSchedules(on: date)
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
                            .strokeBorder(Ink.accentBlue, lineWidth: 1)
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
                                    .fill(isSelected ? Ink.bg : Ink.accentBlue)
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
        if isToday { return Ink.accentBlue }
        return Ink.fg
    }

    // MARK: - 当日详情

    private var schedulesOnSelectedDate: [SiteVisitSchedule] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: selectedDate)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return allSchedules
            .filter { $0.scheduledDate >= dayStart && $0.scheduledDate < dayEnd }
            .sorted { $0.fireDate < $1.fireDate }
    }

    private func hasSchedules(on date: Date) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return false }
        return allSchedules.contains { $0.scheduledDate >= start && $0.scheduledDate < end }
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
                Text(String(localized: "\(schedulesOnSelectedDate.count) 项", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.dim)
                    .monospacedDigit()
            }

            if schedulesOnSelectedDate.isEmpty {
                emptyDayState
            } else {
                VStack(spacing: 0) {
                    ForEach(schedulesOnSelectedDate) { s in
                        scheduleRow(s)
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
        VStack(spacing: 12) {
            Text(String(localized: "今天没有安排", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 13))
                .foregroundStyle(Ink.fgDim)
            Button {
                editingSchedule = nil
                showEditor = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(String(localized: "新建", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Ink.fg)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Ink.line2, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func scheduleRow(_ s: SiteVisitSchedule) -> some View {
        Button {
            editingSchedule = s
            showEditor = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // 左侧 vertical bar
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(statusColor(s.status))
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(timeLabel(s))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Ink.fgDim)
                            .monospacedDigit()
                        if s.status == .completed {
                            Text(String(localized: "已完成", locale: AppLanguageManager.currentLocale))
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.5)
                                .textCase(.uppercase)
                                .foregroundStyle(Ink.fgDim)
                        } else if s.status == .cancelled {
                            Text(String(localized: "已取消", locale: AppLanguageManager.currentLocale))
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.5)
                                .textCase(.uppercase)
                                .foregroundStyle(Ink.dim)
                        }
                    }
                    Text(s.title.isEmpty ? String(localized: "(无标题)", locale: AppLanguageManager.currentLocale) : s.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(s.status == .cancelled ? Ink.fgDim : Ink.fg)
                        .strikethrough(s.status == .cancelled)
                        .lineLimit(2)
                    if let tag = s.siteTag, !tag.isEmpty {
                        Text(tag)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 右侧完成 / 未完成 icon — 直接点切换状态
                Button {
                    toggleCompletion(s)
                } label: {
                    Image(systemName: s.status == .completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(s.status == .completed ? Ink.fg : Ink.dim)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: 1)
        }
        .contextMenu {
            if s.status != .completed {
                Button {
                    markCompleted(s)
                } label: {
                    Label(
                        String(localized: "标记完成", locale: AppLanguageManager.currentLocale),
                        systemImage: "checkmark.circle"
                    )
                }
            } else {
                Button {
                    markPending(s)
                } label: {
                    Label(
                        String(localized: "重置为待办", locale: AppLanguageManager.currentLocale),
                        systemImage: "arrow.uturn.backward"
                    )
                }
            }
            if s.status != .cancelled {
                Button {
                    markCancelled(s)
                } label: {
                    Label(
                        String(localized: "标记取消", locale: AppLanguageManager.currentLocale),
                        systemImage: "xmark.circle"
                    )
                }
            }
            Divider()
            Button(role: .destructive) {
                deleteSchedule(s)
            } label: {
                Label(
                    String(localized: "删除", locale: AppLanguageManager.currentLocale),
                    systemImage: "trash"
                )
            }
        }
    }

    private func statusColor(_ status: ScheduleStatus) -> Color {
        switch status {
        case .pending: return Ink.accentBlue
        case .completed: return Ink.green
        case .cancelled: return Ink.dim
        }
    }

    private func timeLabel(_ s: SiteVisitSchedule) -> String {
        guard let t = s.scheduledTime else {
            return String(localized: "全天", locale: AppLanguageManager.currentLocale)
        }
        let f = DateFormatter()
        f.locale = AppLanguageManager.currentLocale
        f.dateFormat = "HH:mm"
        return f.string(from: t)
    }

    // MARK: - 即将到来

    /// 未删除 + pending + scheduledDate >= 今天起;按 fireDate 升序前 10。
    private var upcomingSchedules: [SiteVisitSchedule] {
        let today = Calendar.current.startOfDay(for: Date())
        return allSchedules
            .filter { $0.status == .pending && $0.scheduledDate >= today }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(10)
            .map { $0 }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "即将到来", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Ink.fgDim)

            if upcomingSchedules.isEmpty {
                Text(String(localized: "近期没有待办日程", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.fgDim)
                    .padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(upcomingSchedules) { s in
                        upcomingRow(s)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 32)
    }

    private func upcomingRow(_ s: SiteVisitSchedule) -> some View {
        Button {
            // 跳到该日期 + 直接进入编辑
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDate = Calendar.current.startOfDay(for: s.scheduledDate)
                currentMonth = s.scheduledDate
            }
            editingSchedule = s
            showEditor = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(relativeDateLabel(s.scheduledDate))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.3)
                        .textCase(.uppercase)
                        .foregroundStyle(Ink.fg)
                        .monospacedDigit()
                    Text(timeLabel(s))
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                        .monospacedDigit()
                }
                .frame(width: 76, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title.isEmpty ? String(localized: "(无标题)", locale: AppLanguageManager.currentLocale) : s.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.fg)
                        .lineLimit(2)
                    if let tag = s.siteTag, !tag.isEmpty {
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

    // MARK: - 状态操作

    private func toggleCompletion(_ s: SiteVisitSchedule) {
        if s.status == .completed {
            markPending(s)
        } else {
            markCompleted(s)
        }
    }

    private func markCompleted(_ s: SiteVisitSchedule) {
        s.status = .completed
        s.completedAt = Date()
        try? modelContext.save()
        // 完成 → 不再提醒
        NotificationService.shared.cancelVisit(s.id)
    }

    private func markPending(_ s: SiteVisitSchedule) {
        s.status = .pending
        s.completedAt = nil
        try? modelContext.save()
        // 重新进入 pending,如启用提醒 → 重排
        NotificationService.shared.scheduleVisit(s)
    }

    private func markCancelled(_ s: SiteVisitSchedule) {
        s.status = .cancelled
        try? modelContext.save()
        NotificationService.shared.cancelVisit(s.id)
    }

    private func deleteSchedule(_ s: SiteVisitSchedule) {
        // 软删 + 清通知。先抓 id 再改 model,防止扩展属性访问的微妙顺序问题。
        let id = s.id
        s.deletedAt = Date()
        try? modelContext.save()
        NotificationService.shared.cancelVisit(id)
    }
}

// MARK: - Helpers

private struct CalendarCell {
    let date: Date?
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SiteVisitSchedule.self, configurations: config)
    return EngineerScheduleView().modelContainer(container)
}
