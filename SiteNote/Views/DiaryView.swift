//
//  DiaryView.swift
//  SiteNote
//
//  第 4 tab "工地管理":Daily Site Diary 的汇总 + 直接管理视图。
//
//  结构:
//    - 顶:标题 / 日期 / 工地筛选 / 摘要条(共享)
//    - 中:segment 选择器 [人员 / 机械 / 事件 / 速记]
//    - 下:对应 segment 的 **List**(swipeActions 必须在 List 里才认)
//    - 底:一键生成 PDF
//
//  直接管理(用户反馈):
//    - 每行左滑删(软删)
//    - 点行 → 弹 `LogEntryEditSheet`(inline 编辑,不跳 NoteDetail)
//    - 机械开着的 session 行内有"结束"按钮
//    - 源 Note 的入口在编辑 sheet 的底部("查看源速记")
//

import SwiftUI
import SwiftData

struct DiaryView: View {
    var isActive: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: [SortDescriptor(\Note.createdAt)]
    ) private var allNotes: [Note]

    @Query(
        filter: #Predicate<LogEntry> { $0.deletedAt == nil },
        sort: [SortDescriptor(\LogEntry.startAt)]
    ) private var allEntries: [LogEntry]

    @State private var selectedDate: Date = Date()
    @State private var selectedSite: String? = nil
    @State private var availableSites: [String] = []

    @State private var selectedSegment: DiarySegment = .person
    @State private var editingLogEntry: LogEntry?

    @State private var isGenerating: Bool = false
    @State private var sharePDFURL: URL?
    @State private var errorMessage: String?

    enum DiarySegment: Hashable { case person, plant, event, notes }

    // MARK: - Filters

    private var dayStart: Date { Calendar.current.startOfDay(for: selectedDate) }
    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }

    private var todayEntries: [LogEntry] {
        allEntries.filter { e in
            e.startAt >= dayStart && e.startAt < dayEnd
                && (selectedSite == nil || e.siteTag == selectedSite)
        }
    }

    private var todayNotes: [Note] {
        allNotes.filter { n in
            n.createdAt >= dayStart && n.createdAt < dayEnd
                && (selectedSite == nil || n.siteTag == selectedSite)
        }
    }

    private var personEntries: [LogEntry] { todayEntries.filter { $0.kind == .person } }
    private var plantEntries: [LogEntry] { todayEntries.filter { $0.kind == .plant } }
    private var otherEntries: [LogEntry] {
        todayEntries.filter {
            $0.kind == .delivery || $0.kind == .visitor || $0.kind == .event
        }
    }

    private var totalHeadcount: Int {
        personEntries.filter { !$0.isAbsent }.map { $0.quantity ?? 1 }.reduce(0, +)
    }
    private var openPlantCount: Int {
        plantEntries.filter { $0.isOpenPlantSession }.count
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    AIStatusBar()
                    titleRow
                    filterBar
                    summaryStrip
                        .padding(.horizontal, 24)
                        .padding(.bottom, 10)
                    segmentPicker
                    Divider().overlay(Ink.line)
                    segmentContent
                    bottomBar
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Note.self) { note in
                NoteRouter(note: note)
            }
            .navigationDestination(for: SettingsDestination.self) { _ in
                SettingsView()
            }
            .navigationDestination(for: AIStatusDestination.self) { _ in
                InputAISettingsView()
            }
            .onAppear { availableSites = SiteTagsStorage.load() }
            .onChange(of: isActive) { _, active in
                if active { availableSites = SiteTagsStorage.load() }
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

    // MARK: - Title + filters

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("工地管理")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Ink.fg)
            Spacer()
            SearchBarButton()
            TodayBriefButton()
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

    private var filterBar: some View {
        VStack(spacing: 10) {
            dayNavigator
            if !availableSites.isEmpty {
                sitePicker
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    private var dayNavigator: some View {
        HStack(spacing: 10) {
            Button { shiftDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Ink.fgDim)
                    .frame(width: 36, height: 36)
                    .background(Ink.card, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button { selectedDate = Date() } label: {
                VStack(alignment: .center, spacing: 2) {
                    Text(dayLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                    Text(dayWeekdayLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Ink.card, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button { shiftDay(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        Calendar.current.isDateInToday(selectedDate) ? Ink.dim : Ink.fgDim
                    )
                    .frame(width: 36, height: 36)
                    .background(Ink.card, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(Calendar.current.isDateInToday(selectedDate))
        }
    }

    private var sitePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                siteChip(label: "全部", isOn: selectedSite == nil) { selectedSite = nil }
                ForEach(availableSites, id: \.self) { site in
                    siteChip(label: site, isOn: selectedSite == site) { selectedSite = site }
                }
            }
        }
    }

    private func siteChip(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
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

    private var dayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日"
        return f.string(from: selectedDate)
    }

    private var dayWeekdayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        let w = f.string(from: selectedDate)
        if Calendar.current.isDateInToday(selectedDate) { return "今天 · \(w)" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "昨天 · \(w)" }
        return w
    }

    private func shiftDay(_ delta: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) {
            selectedDate = newDate
        }
    }

    // MARK: - Summary strip

    private var summaryStrip: some View {
        HStack(spacing: 10) {
            summaryCell(value: "\(totalHeadcount)", label: "到场人数", color: Ink.fg)
            summaryCell(value: "\(plantEntries.count)", label: "机械记录", color: Ink.fg)
            summaryCell(
                value: openPlantCount > 0 ? "⏱ \(openPlantCount)" : "✓",
                label: openPlantCount > 0 ? "未结束" : "已结束",
                color: openPlantCount > 0 ? Ink.red : Ink.green
            )
            summaryCell(value: "\(todayNotes.count)", label: "速记", color: Ink.fgDim)
        }
    }

    private func summaryCell(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Ink.fgDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Segment picker

    private var segmentPicker: some View {
        HStack(spacing: 0) {
            segmentButton(.person, label: "人员", count: personEntries.count)
            segmentButton(.plant, label: "机械", count: plantEntries.count)
            segmentButton(.event, label: "事件", count: otherEntries.count)
            segmentButton(.notes, label: "速记", count: todayNotes.count)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func segmentButton(_ seg: DiarySegment, label: String, count: Int) -> some View {
        let isOn = selectedSegment == seg
        return Button {
            selectedSegment = seg
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Ink.fg : Ink.fgDim)
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isOn ? Ink.fg : Ink.dim)
                        .monospacedDigit()
                }
                Rectangle()
                    .fill(isOn ? Ink.fg : Color.clear)
                    .frame(height: 1.5)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Segment content

    @ViewBuilder
    private var segmentContent: some View {
        switch selectedSegment {
        case .person: personList
        case .plant:  plantList
        case .event:  eventList
        case .notes:  rawNotesList
        }
    }

    // MARK: - Person list

    @ViewBuilder
    private var personList: some View {
        if personEntries.isEmpty {
            emptyState(icon: "person.3", text: "当天还没人员记录")
        } else {
            List {
                ForEach(personEntries) { entry in
                    personRow(entry)
                        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Ink.bg)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                entry.deletedAt = Date()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .tint(Ink.red)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                entry.isAbsent.toggle()
                                entry.userConfirmed = true
                            } label: {
                                Label(
                                    entry.isAbsent ? "到场" : "缺席",
                                    systemImage: entry.isAbsent ? "checkmark" : "xmark"
                                )
                            }
                            .tint(entry.isAbsent ? Ink.green : Ink.red)
                        }
                }
            }
            .listStyle(.plain)
            .industrialForm()
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    private func personRow(_ e: LogEntry) -> some View {
        Button { editingLogEntry = e } label: {
            HStack(spacing: 10) {
                Text(e.isAbsent ? "🚫" : "👥")
                    .font(.system(size: 18))
                    .frame(width: 28, alignment: .center)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(e.subject)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Ink.fg)
                        if e.isAbsent {
                            Text("缺席")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Ink.red)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Ink.red.opacity(0.1), in: Capsule())
                        } else if let q = e.quantity, q > 0 {
                            Text("×\(q)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Ink.fgDim)
                                .monospacedDigit()
                        }
                        if !e.userConfirmed {
                            Circle().fill(Ink.accent).frame(width: 5, height: 5)
                        }
                    }
                    if let n = e.note, !n.isEmpty {
                        Text(n)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
                Spacer(minLength: 0)
                Text(startTimeLabel(e))
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.dim)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.dim)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 明说了时间显示 HH:mm,没说显示 "—"。
    private func startTimeLabel(_ e: LogEntry) -> String {
        e.startAtExplicit ? timeShort(e.startAt) : "—"
    }

    // MARK: - Plant list

    @ViewBuilder
    private var plantList: some View {
        if plantEntries.isEmpty {
            emptyState(icon: "wrench.and.screwdriver", text: "当天还没机械记录")
        } else {
            List {
                ForEach(plantEntries) { entry in
                    plantRow(entry)
                        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Ink.bg)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                entry.deletedAt = Date()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .tint(Ink.red)
                        }
                }
            }
            .listStyle(.plain)
            .industrialForm()
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    private func plantRow(_ e: LogEntry) -> some View {
        // 两个独立 Button 并排——不要嵌套,否则 SwiftUI 手势会打架。
        // 左侧大块(图标 + 文字) tap → 编辑 sheet
        // 右侧小按钮("结束" 或 chevron) tap → 只关 session,不打开 sheet
        HStack(spacing: 10) {
            Button {
                editingLogEntry = e
            } label: {
                HStack(spacing: 10) {
                    Text("🚜")
                        .font(.system(size: 18))
                        .frame(width: 28, alignment: .center)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(e.subject)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Ink.fg)
                            if !e.userConfirmed {
                                Circle().fill(Ink.accent).frame(width: 5, height: 5)
                            }
                        }
                        plantTimeLabel(e)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if e.isOpenPlantSession {
                Button {
                    closeSession(e)
                } label: {
                    Text("结束")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Ink.fg)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.dim)
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func plantTimeLabel(_ e: LogEntry) -> some View {
        if e.isOpenPlantSession {
            HStack(spacing: 4) {
                Text("⏱ 开启中")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Ink.red)
                Text("·")
                    .foregroundStyle(Ink.dim)
                if e.startAtExplicit {
                    Text("已 \(LogEntryChipSection.durationString(Date().timeIntervalSince(e.startAt)))")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.fgDim)
                        .monospacedDigit()
                } else {
                    Text("未标开始时间")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.dim)
                }
            }
        } else if e.startAt == e.endAt {
            Text("⚠︎ 孤儿记录 · \(startTimeLabel(e))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ink.red)
        } else if let end = e.endAt {
            HStack(spacing: 4) {
                Text("\(startTimeLabel(e))–\(timeShort(end))")
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.fgDim)
                    .monospacedDigit()
                if e.startAtExplicit, let duration = e.duration {
                    Text("·")
                        .foregroundStyle(Ink.dim)
                    Text(LogEntryChipSection.durationString(duration))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                        .monospacedDigit()
                }
            }
        }
    }

    private func closeSession(_ e: LogEntry) {
        e.endAt = Date()
        e.userConfirmed = true
    }

    // MARK: - Event list

    @ViewBuilder
    private var eventList: some View {
        if otherEntries.isEmpty {
            emptyState(icon: "shippingbox", text: "当天还没送达 / 访客 / 事件")
        } else {
            List {
                ForEach(otherEntries) { entry in
                    eventRow(entry)
                        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Ink.bg)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                entry.deletedAt = Date()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .tint(Ink.red)
                        }
                }
            }
            .listStyle(.plain)
            .industrialForm()
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    private func eventRow(_ e: LogEntry) -> some View {
        Button { editingLogEntry = e } label: {
            HStack(spacing: 10) {
                Text(eventIcon(e.kind))
                    .font(.system(size: 18))
                    .frame(width: 28, alignment: .center)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(e.kind.displayName)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.3)
                            .textCase(.uppercase)
                            .foregroundStyle(Ink.dim)
                        Text(e.subject)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Ink.fg)
                        if !e.userConfirmed {
                            Circle().fill(Ink.accent).frame(width: 5, height: 5)
                        }
                    }
                    if let n = e.note, !n.isEmpty {
                        Text(n)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
                Spacer(minLength: 0)
                Text(startTimeLabel(e))
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.dim)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.dim)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func eventIcon(_ k: LogKind) -> String {
        switch k {
        case .delivery: return "📦"
        case .visitor: return "🧑"
        case .event: return "⚠️"
        default: return "•"
        }
    }

    // MARK: - Raw notes list

    @ViewBuilder
    private var rawNotesList: some View {
        if todayNotes.isEmpty {
            emptyState(icon: "doc.text", text: "当天还没速记")
        } else {
            List {
                ForEach(todayNotes) { note in
                    NavigationLink(value: note) {
                        NoteRow(note: note, urgency: nil)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Ink.bg)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            note.deletedAt = Date()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .tint(Ink.red)
                    }
                }
            }
            .listStyle(.plain)
            .industrialForm()
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    // MARK: - Empty state

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 40)
            Image(systemName: icon)
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(Ink.dim)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ink.fgDim)
            Text("去「记」tab 按住 mic 说话,AI 会自动识别。")
                .font(.system(size: 12))
                .foregroundStyle(Ink.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom bar

    /// 底部按钮用的日期文案:今天/昨天/具体日期。区分顶部"今日简报"按钮。
    private var bottomBarDateLabel: String {
        if Calendar.current.isDateInToday(selectedDate) { return "今日" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "昨日" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M/d"
        return f.string(from: selectedDate)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if !todayEntries.isEmpty || !todayNotes.isEmpty {
            VStack(spacing: 0) {
                Divider().overlay(Ink.line)
                Button {
                    generateDiaryPDF()
                } label: {
                    HStack(spacing: 8) {
                        if isGenerating {
                            ProgressView().tint(Color.white)
                        } else {
                            Image(systemName: "doc.richtext")
                        }
                        // 文案带"选中日期" → 区分顶部"📤 简报"(永远是今天)
                        Text(isGenerating ? "生成中…" : "生成 \(bottomBarDateLabel) 日志 PDF")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Ink.fg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
            .background(Ink.bg)
        }
    }

    // MARK: - Helpers

    private func timeShort(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // MARK: - PDF generation

    private func generateDiaryPDF() {
        isGenerating = true
        let date = selectedDate
        let site = selectedSite
        let entries = todayEntries
        let notes = todayNotes
        let dayWeather = notes.compactMap { $0.weatherSummary }.first

        Task {
            do {
                let url = try await SiteDiaryPDFBuilder.build(
                    date: date,
                    siteTag: site,
                    entries: entries,
                    notes: notes,
                    weatherSummary: dayWeather
                )
                sharePDFURL = url
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            isGenerating = false
        }
    }
}

private struct PDFShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, ShareLog.self, configurations: config)
    return DiaryView().modelContainer(container)
}
