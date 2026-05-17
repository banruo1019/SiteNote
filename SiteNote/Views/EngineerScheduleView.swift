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

    /// 所有未删除的巡检报告 — 当日列表用于展示当天 reportDate 的报告。
    @Query(
        filter: #Predicate<InspectionReport> { $0.deletedAt == nil },
        sort: \InspectionReport.reportDate
    ) private var allInspectionReports: [InspectionReport]

    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showEditor: Bool = false
    @State private var editingSchedule: SiteVisitSchedule? = nil
    /// 工地过滤器:nil = 全部工地。
    @State private var siteFilter: String? = nil

    // MARK: - v1.4 巡检 session 集成

    /// 顶部 banner / 一键开巡检 / 完成弹窗 都接它。
    @State private var sessionManager = InspectionSessionManager.shared
    /// 顶部 banner 的"完成巡检"按下后弹 EndInspectionSheet。
    @State private var showsEndSheet: Bool = false
    /// 当日详情段落切换:全部 / 仅日程 / 仅报告。
    @State private var dayDetailScope: DayDetailScope = .all
    /// 点已关联报告的日程 → 跳报告详情。NavigationStack path-style 仍走旧 NavigationLink,
    /// 这里只是给 sheet/导航触发用,实际跳转走 navigationDestination(item:)。
    @State private var navigateToReportID: UUID? = nil

    /// 当日详情段切换枚举。
    enum DayDetailScope: String, CaseIterable, Hashable {
        case all
        case schedules
        case reports
    }

    /// 应用工地 filter 后的 schedules / reports。
    private var filteredSchedules: [SiteVisitSchedule] {
        if let site = siteFilter {
            return allSchedules.filter { $0.siteTag == site }
        }
        return Array(allSchedules)
    }
    private var filteredReports: [InspectionReport] {
        if let site = siteFilter {
            return allInspectionReports.filter { $0.projectNo == site }
        }
        return Array(allInspectionReports)
    }

    /// 工地列表(从 schedules + reports + SiteTagsStorage 合并)。
    private var allSiteTags: [String] {
        let fromSchedules = Set(allSchedules.compactMap { $0.siteTag })
        let fromReports = Set(allInspectionReports.compactMap { $0.projectNo.isEmpty ? nil : $0.projectNo })
        let configured = Set(SiteTagsStorage.load())
        return Array(fromSchedules.union(fromReports).union(configured)).sorted()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    titleRow
                    ScrollView {
                        VStack(spacing: 0) {
                            // v1.4:active session 时显示顶部 banner;点"完成巡检"弹 EndInspectionSheet
                            InspectionSessionBanner(onComplete: { _ in
                                showsEndSheet = true
                            })
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)

                            monthHeader
                            calendarGrid
                            divider
                            dayDetailSection
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: SettingsDestination.self) { _ in
                SettingsView()
            }
            // 已关联报告的日程 → 直接跳报告详情(复用 InspectionFormView 当作详情入口)
            .navigationDestination(item: $navigateToReportID) { id in
                if let report = fetchReport(for: id) {
                    InspectionFormView(report: report)
                }
            }
            .sheet(isPresented: $showEditor, onDismiss: {
                editingSchedule = nil
            }) {
                ScheduleEditorSheet(
                    schedule: editingSchedule,
                    prefilledDate: editingSchedule == nil ? selectedDate : nil
                )
            }
            .sheet(isPresented: $showsEndSheet) {
                if let report = sessionManager.currentReport(in: modelContext) {
                    EndInspectionSheet(report: report) { _, _ in
                        showsEndSheet = false
                    }
                }
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
            siteFilterMenu
            Button {
                editingSchedule = nil
                showEditor = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(String(localized: "新建", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Ink.bg)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Ink.fg))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
        .padding(.bottom, 16)
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

    @ViewBuilder
    private func cellView(for cellDate: Date?) -> some View {
        if let date = cellDate {
            let cal = Calendar.current
            let isToday = cal.isDateInToday(date)
            let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
            let scheduleN = scheduleCount(on: date)
            let reportN = reportCount(on: date)
            let day = cal.component(.day, from: date)
            // M1:今天 = 黑圆填充;选中(非今天)= 灰底圆;否则透明
            let bgFill: Color = isToday ? Ink.fg : (isSelected ? Ink.card : .clear)
            let textColor: Color = isToday ? Ink.bg : Ink.fg

            // dot 分色:先报告(黑/今天反色为白)再日程(蓝),总数 ≤ 3
            let reportDots = min(reportN, 3)
            let scheduleDots = min(scheduleN, max(0, 3 - reportDots))

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
                        Text("\(day)")
                            .font(.system(size: 13, weight: isToday ? .semibold : .medium))
                            .monospacedDigit()
                            .foregroundStyle(textColor)
                    }
                    HStack(spacing: 2.5) {
                        // 已出报告 — 黑 dot(今天反色为白,以保对比)
                        ForEach(0..<reportDots, id: \.self) { _ in
                            Circle()
                                .fill(isToday ? Ink.bg : Ink.fg)
                                .frame(width: 4, height: 4)
                        }
                        // 未做日程 — 蓝 dot
                        ForEach(0..<scheduleDots, id: \.self) { _ in
                            Circle()
                                .fill(Ink.accentBlue)
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

    /// 某一天落在月格里的 schedule 条数(用于决定 dot 数,最多 3)。
    private func scheduleCount(on date: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return filteredSchedules.filter { $0.scheduledDate >= start && $0.scheduledDate < end }.count
    }

    /// 某一天的 InspectionReport 数(reportDate 落在当天,用于黑 dot)。
    private func reportCount(on date: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return filteredReports.filter { $0.reportDate >= start && $0.reportDate < end }.count
    }

    // MARK: - 当日详情

    private var schedulesOnSelectedDate: [SiteVisitSchedule] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: selectedDate)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return filteredSchedules
            .filter { $0.scheduledDate >= dayStart && $0.scheduledDate < dayEnd }
            .sorted { $0.fireDate < $1.fireDate }
    }

    private func hasSchedules(on date: Date) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return false }
        return filteredSchedules.contains { $0.scheduledDate >= start && $0.scheduledDate < end }
    }

    private var reportsOnSelectedDate: [InspectionReport] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: selectedDate)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return filteredReports
            .filter { $0.reportDate >= dayStart && $0.reportDate < dayEnd }
            .sorted { $0.reportDate < $1.reportDate }
    }

    private var dayDetailSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 日期主标题:周三 5 月 17 · 今天
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

            // 段落 segmented:全部 / 日程 N / 报告 N
            Picker("", selection: $dayDetailScope) {
                Text(String(localized: "全部", locale: AppLanguageManager.currentLocale))
                    .tag(DayDetailScope.all)
                Text(scopeLabel(
                    base: String(localized: "日程", locale: AppLanguageManager.currentLocale),
                    count: schedulesOnSelectedDate.count
                ))
                    .tag(DayDetailScope.schedules)
                Text(scopeLabel(
                    base: String(localized: "报告", locale: AppLanguageManager.currentLocale),
                    count: reportsOnSelectedDate.count
                ))
                    .tag(DayDetailScope.reports)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 4)

            // 当日巡检日程 — scope=.all 或 .schedules 时显示
            if dayDetailScope == .all || dayDetailScope == .schedules {
                VStack(alignment: .leading, spacing: 6) {
                    sectionMiniHeader(
                        String(localized: "当日巡检日程", locale: AppLanguageManager.currentLocale),
                        count: schedulesOnSelectedDate.count
                    )
                    if schedulesOnSelectedDate.isEmpty {
                        emptyDayState
                    } else {
                        cardGroup {
                            VStack(spacing: 0) {
                                ForEach(Array(schedulesOnSelectedDate.enumerated()), id: \.element.id) { idx, s in
                                    scheduleRow(s, isLast: idx == schedulesOnSelectedDate.count - 1)
                                }
                            }
                        }
                    }
                }
            }

            // 当日巡检报告 — scope=.all 或 .reports 时显示
            if dayDetailScope == .all || dayDetailScope == .reports {
                VStack(alignment: .leading, spacing: 6) {
                    sectionMiniHeader(
                        String(localized: "当日巡检报告", locale: AppLanguageManager.currentLocale),
                        count: reportsOnSelectedDate.count
                    )
                    if reportsOnSelectedDate.isEmpty {
                        Text(String(localized: "当日无报告", locale: AppLanguageManager.currentLocale))
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.fgDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                    } else {
                        cardGroup {
                            VStack(spacing: 0) {
                                ForEach(Array(reportsOnSelectedDate.enumerated()), id: \.element.id) { idx, r in
                                    reportRow(r, isLast: idx == reportsOnSelectedDate.count - 1)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 20)
    }

    /// segmented tab 文本:无内容时不挂数字,避免 "日程 0" 视觉负担。
    private func scopeLabel(base: String, count: Int) -> String {
        count > 0 ? "\(base) \(count)" : base
    }

    /// "当日巡检日程" 这种 mini 段头(uppercase + count chip)。
    private func sectionMiniHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Ink.fgDim)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Ink.fg2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Ink.card)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
    }

    /// 描边圆角卡片容器,用于当日两段内容。
    private func cardGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Ink.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)
    }

    private func reportRow(_ r: InspectionReport, isLast: Bool) -> some View {
        NavigationLink {
            InspectionFormView(report: r)
        } label: {
            InspectionReportRowContent(report: r, isLast: isLast)
        }
        .buttonStyle(.plain)
    }

    /// 友好日期标签 — "周三 5 月 17"。
    private var selectedDateLabel: String {
        Formatters.weekdayMonthDay.string(from: selectedDate)
    }

    private var emptyDayState: some View {
        Text(String(localized: "这天没有日程", locale: AppLanguageManager.currentLocale))
            .font(.system(size: 13))
            .foregroundStyle(Ink.fgDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
    }

    private func scheduleRow(_ s: SiteVisitSchedule, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            // 行主体:沿用 ScheduleRowContent,外包 Button → 点开编辑
            Button {
                editingSchedule = s
                showEditor = true
            } label: {
                ScheduleRowContent(schedule: s, isLast: true)  // 内部 hairline 让位给外部
            }
            .buttonStyle(.plain)

            // 智能按钮区:未关联 → [▶ 开始巡检];已关联 → [→ SVR-xxx]
            scheduleActionRow(for: s)

            // 行底分隔线(最后一行不画)
            if !isLast {
                Rectangle().fill(Ink.line).frame(height: 1)
            }
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

    // MARK: - v1.4 智能按钮 + session 启动

    /// 日程行下方的操作按钮:
    /// - linkedReportID == nil → [▶ 开始巡检](一键开 session 并双向绑定)
    /// - linkedReportID != nil → [→ SVR-xxx >](跳报告详情)
    @ViewBuilder
    private func scheduleActionRow(for s: SiteVisitSchedule) -> some View {
        HStack {
            Spacer()
            if let rid = s.linkedReportID {
                Button {
                    navigateToReportID = rid
                } label: {
                    HStack(spacing: 4) {
                        Text(String(
                            format: String(localized: "→ %@", locale: AppLanguageManager.currentLocale),
                            reportNo(for: rid)
                        ))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.fgDim)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Ink.dim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    startSessionFromSchedule(s)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(String(localized: "开始巡检", locale: AppLanguageManager.currentLocale))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Ink.bg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Ink.fg))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    /// 从日程一键启动巡检 session(双向绑定 schedule ↔ report)。
    private func startSessionFromSchedule(_ s: SiteVisitSchedule) {
        let preset = s.siteTag.flatMap { SitePresetStorage.find(siteTag: $0) }
        _ = sessionManager.startFromSchedule(
            s,
            siteTag: s.siteTag ?? "",
            preset: preset,
            defaultAttn: preset?.defaultAttn ?? "",
            in: modelContext
        )
    }

    /// 用 reportID 反查 reportNo(navigation chip 显示用)。找不到时回退 short uuid。
    private func reportNo(for id: UUID) -> String {
        if let r = fetchReport(for: id) {
            let no = r.reportNo.trimmingCharacters(in: .whitespaces)
            if !no.isEmpty { return no }
        }
        return String(id.uuidString.prefix(6))
    }

    /// 用 reportID 反查 InspectionReport,供导航 destination 使用。
    private func fetchReport(for id: UUID) -> InspectionReport? {
        let desc = FetchDescriptor<InspectionReport>(
            predicate: #Predicate<InspectionReport> { $0.id == id }
        )
        return try? modelContext.fetch(desc).first
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

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SiteVisitSchedule.self, configurations: config)
    return EngineerScheduleView().modelContainer(container)
}
