//
//  LogTabView+Ledger.swift
//  SiteNote
//
//  台账 mode 的所有视图 + 派生属性 + helper。从 LogTabView 抽出。
//  Overview mode 留在主文件。
//

import SwiftUI
import SwiftData
import UIKit

extension LogTabView {

    // MARK: - Body 入口

    var ledgerBody: some View {
        VStack(spacing: 0) {
            dayNavigator
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 10)
            summaryStrip
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            daySegment
            Divider().overlay(Ink.line)
            daySegmentContent
        }
    }

    // MARK: - 日期过滤 derived

    var dayStart: Date { Calendar.current.startOfDay(for: selectedDate) }
    var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }

    var todayEntries: [LogEntry] {
        allEntries.filter { e in
            e.startAt >= dayStart && e.startAt < dayEnd
                && (selectedSiteFilter == nil || e.siteTag == selectedSiteFilter)
        }
    }

    var todayNotes: [Note] {
        allNotes.filter { n in
            n.createdAt >= dayStart && n.createdAt < dayEnd
                && (selectedSiteFilter == nil || n.siteTag == selectedSiteFilter)
        }
    }

    var personEntries: [LogEntry] { todayEntries.filter { $0.kind == .person } }
    var plantEntries: [LogEntry] { todayEntries.filter { $0.kind == .plant } }
    var otherEntries: [LogEntry] {
        todayEntries.filter {
            $0.kind == .delivery || $0.kind == .visitor || $0.kind == .event
        }
    }

    var totalHeadcount: Int {
        personEntries.filter { !$0.isAbsent }.map { $0.quantity ?? 1 }.reduce(0, +)
    }
    var openPlantCount: Int {
        plantEntries.filter { $0.isOpenPlantSession }.count
    }

    // MARK: - Day navigator

    var dayNavigator: some View {
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

    var dayLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: selectedDate)
    }

    var dayWeekdayLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEEE"
        let w = f.string(from: selectedDate)
        if Calendar.current.isDateInToday(selectedDate) { return String(localized: "今天 · \(w)", locale: AppLanguageManager.currentLocale) }
        if Calendar.current.isDateInYesterday(selectedDate) { return String(localized: "昨天 · \(w)", locale: AppLanguageManager.currentLocale) }
        return w
    }

    func shiftDay(_ delta: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) {
            selectedDate = newDate
        }
    }

    // MARK: - Summary strip

    var summaryStrip: some View {
        HStack(spacing: 10) {
            summaryCell(value: "\(totalHeadcount)", label: String(localized: "到场人数", locale: AppLanguageManager.currentLocale), color: Ink.fg)
            summaryCell(value: "\(plantEntries.count)", label: String(localized: "机械记录", locale: AppLanguageManager.currentLocale), color: Ink.fg)
            summaryCell(
                value: openPlantCount > 0 ? "⏱ \(openPlantCount)" : "✓",
                label: openPlantCount > 0 ? String(localized: "未结束", locale: AppLanguageManager.currentLocale) : String(localized: "已结束", locale: AppLanguageManager.currentLocale),
                color: openPlantCount > 0 ? Ink.red : Ink.green
            )
            summaryCell(value: "\(todayNotes.count)", label: String(localized: "速记", locale: AppLanguageManager.currentLocale), color: Ink.fgDim)
        }
    }

    func summaryCell(value: String, label: String, color: Color) -> some View {
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

    // MARK: - Day segment

    var daySegment: some View {
        HStack(spacing: 0) {
            daySegmentButton(.person, label: String(localized: "人员", locale: AppLanguageManager.currentLocale), count: personEntries.count)
            daySegmentButton(.plant, label: String(localized: "机械", locale: AppLanguageManager.currentLocale), count: plantEntries.count)
            daySegmentButton(.event, label: String(localized: "事件", locale: AppLanguageManager.currentLocale), count: otherEntries.count)
            daySegmentButton(.notes, label: String(localized: "速记", locale: AppLanguageManager.currentLocale), count: todayNotes.count)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    func daySegmentButton(_ seg: DaySegment, label: String, count: Int) -> some View {
        let isOn = selectedDaySegment == seg
        return Button {
            selectedDaySegment = seg
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

    @ViewBuilder
    var daySegmentContent: some View {
        switch selectedDaySegment {
        case .person: personList
        case .plant:  plantList
        case .event:  eventList
        case .notes:  rawNotesList
        }
    }

    // MARK: - Person list

    @ViewBuilder
    var personList: some View {
        if personEntries.isEmpty {
            emptyDayState(icon: "person.3", text: String(localized: "当天还没人员记录", locale: AppLanguageManager.currentLocale))
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

    func personRow(_ e: LogEntry) -> some View {
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

    func startTimeLabel(_ e: LogEntry) -> String {
        e.startAtExplicit ? timeShort(e.startAt) : "—"
    }

    // MARK: - Plant list

    @ViewBuilder
    var plantList: some View {
        if plantEntries.isEmpty {
            emptyDayState(icon: "wrench.and.screwdriver", text: String(localized: "当天还没机械记录", locale: AppLanguageManager.currentLocale))
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

    func plantRow(_ e: LogEntry) -> some View {
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
    func plantTimeLabel(_ e: LogEntry) -> some View {
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

    func closeSession(_ e: LogEntry) {
        e.endAt = Date()
        e.userConfirmed = true
    }

    // MARK: - Event list

    @ViewBuilder
    var eventList: some View {
        if otherEntries.isEmpty {
            emptyDayState(icon: "shippingbox", text: String(localized: "当天还没送达 / 访客 / 事件", locale: AppLanguageManager.currentLocale))
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

    func eventRow(_ e: LogEntry) -> some View {
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

    func eventIcon(_ k: LogKind) -> String {
        switch k {
        case .delivery: return "📦"
        case .visitor: return "🧑"
        case .event: return "⚠️"
        default: return "•"
        }
    }

    // MARK: - Raw notes list

    @ViewBuilder
    var rawNotesList: some View {
        if todayNotes.isEmpty {
            emptyDayState(icon: "doc.text", text: String(localized: "当天还没速记", locale: AppLanguageManager.currentLocale))
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

    // MARK: - 台账 empty state

    func emptyDayState(icon: String, text: String) -> some View {
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

    var bottomBarDateLabel: String {
        if Calendar.current.isDateInToday(selectedDate) { return String(localized: "今日", locale: AppLanguageManager.currentLocale) }
        if Calendar.current.isDateInYesterday(selectedDate) { return String(localized: "昨日", locale: AppLanguageManager.currentLocale) }
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "M/d"
        return f.string(from: selectedDate)
    }

    @ViewBuilder
    var bottomBar: some View {
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

    func timeShort(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // MARK: - PDF generation

    func generateDiaryPDF() {
        isGenerating = true
        let date = selectedDate
        let site = selectedSiteFilter
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
