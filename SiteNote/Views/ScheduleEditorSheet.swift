//
//  ScheduleEditorSheet.swift
//  SiteNote
//
//  Engineer Profile · 日程新建 / 编辑 sheet。
//  Form 风格,industrialForm() 白底,Section header 11pt 600 大写 fgDim。
//
//  字段:标题 · 日期(+可选具体时间) · 工地 · 备注 · 启用提醒(+提前 1/2)。
//  保存后 NotificationService.scheduleVisit(_:) 自动按当前 reminderEnabled 重排。
//  reminderEnabled 关 / 改为 cancelled / 已完成 → cancelVisit 清通知。
//

import SwiftUI
import SwiftData
import os

struct ScheduleEditorSheet: View {
    private static let logger = Logger(subsystem: "com.banruo.sitenote", category: "ScheduleEditor")

    /// nil = 新建模式;非 nil = 编辑模式。
    let schedule: SiteVisitSchedule?

    /// 新建模式下预填的日期(月视图点中的某一天)。nil = 用今天。
    let prefilledDate: Date?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var scheduledDate: Date = Date()
    @State private var hasSpecificTime: Bool = false
    @State private var scheduledTime: Date = Date()
    @State private var siteTag: String? = nil
    @State private var reminderEnabled: Bool = true
    @State private var reminder1Minutes: Int = 1440
    /// v1.3 起 UI 不再暴露第二条提醒。@State 保留仅为 model 字段兼容,
    /// 永远设 0(NotificationService 据此跳过第二条调度)。
    @State private var reminder2Minutes: Int = 0
    @State private var assignedToUserID: String? = nil

    /// 真团队成员(v1.6 接通,删 mock)。无团队时数组空 → picker 隐藏。
    @Query private var teamMembers: [TeamMember]

    /// 提前时长选项(分钟)。0 = 关闭(只第二条用)。
    /// 设计:覆盖工地常见预约心智 — 1 天前 / 当天早上(隐式)/ 1 小时前临门一脚。
    private let leadOptionsPrimary: [(label: LocalizedStringKey, minutes: Int)] = [
        ("5 分钟前", 5),
        ("15 分钟前", 15),
        ("30 分钟前", 30),
        ("1 小时前", 60),
        ("2 小时前", 120),
        ("当天早上", 720),     // 12h - 在前一天晚上"打表";粗略,够用
        ("1 天前", 1440),
        ("2 天前", 2880),
        ("3 天前", 4320)
    ]
    private let leadOptionsSecondary: [(label: LocalizedStringKey, minutes: Int)] = [
        ("关闭", 0),
        ("5 分钟前", 5),
        ("15 分钟前", 15),
        ("30 分钟前", 30),
        ("1 小时前", 60),
        ("2 小时前", 120),
        ("1 天前", 1440)
    ]

    private let siteTags: [String] = SiteTagsStorage.load()

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                timeSection
                siteSection
                assignmentSection
                notesSection
                reminderSection
            }
            .industrialForm()
            .navigationTitle(schedule == nil
                ? String(localized: "新建日程", locale: AppLanguageManager.currentLocale)
                : String(localized: "编辑日程", locale: AppLanguageManager.currentLocale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", locale: AppLanguageManager.currentLocale)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存", locale: AppLanguageManager.currentLocale)) {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: loadInitialState)
        }
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section {
            TextField(
                String(localized: "FFL steel / Roof slab / Level 1 reo", locale: AppLanguageManager.currentLocale),
                text: $title
            )
            .font(.system(size: 15))
        } header: {
            SectionHeader(String(localized: "标题", locale: AppLanguageManager.currentLocale))
        }
    }

    private var timeSection: some View {
        Section {
            DatePicker(
                String(localized: "日期", locale: AppLanguageManager.currentLocale),
                selection: $scheduledDate,
                displayedComponents: .date
            )
            .font(.system(size: 15))

            Toggle(
                String(localized: "指定时间", locale: AppLanguageManager.currentLocale),
                isOn: $hasSpecificTime
            )
            .font(.system(size: 15))

            if hasSpecificTime {
                DatePicker(
                    String(localized: "时间", locale: AppLanguageManager.currentLocale),
                    selection: $scheduledTime,
                    displayedComponents: .hourAndMinute
                )
                .font(.system(size: 15))
            }
        } header: {
            SectionHeader(String(localized: "时间", locale: AppLanguageManager.currentLocale))
        } footer: {
            if !hasSpecificTime {
                SectionFooter(String(localized: "全天日程将按当天上午 9 点触发提醒", locale: AppLanguageManager.currentLocale))
            }
        }
    }

    private var siteSection: some View {
        Section {
            if siteTags.isEmpty {
                Text(String(localized: "尚未添加工地。可到 Settings → 工地预设 添加。", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.fgDim)
            } else {
                Picker(
                    String(localized: "工地", locale: AppLanguageManager.currentLocale),
                    selection: $siteTag
                ) {
                    Text(String(localized: "(未指定)", locale: AppLanguageManager.currentLocale))
                        .tag(String?.none)
                    ForEach(siteTags, id: \.self) { tag in
                        Text(tag).tag(String?.some(tag))
                    }
                }
                .font(.system(size: 15))
            }
        } header: {
            SectionHeader(String(localized: "工地", locale: AppLanguageManager.currentLocale))
        }
    }

    /// Picker 显示的成员列表,**按 userID 去重**(同 userID 多条 stale 只显示一条)。
    /// 老 zone 里 Jamie 端在 oscillation 修复前用 UUID() 多次推 TeamMember CKRecord,
    /// 留下了多条同 userID 不同 memberID 的孤儿,SwiftData @Query 全拉进来 → picker
    /// 里同一个人出现 N 次。zone 端清理由 Owner 端 fetchAndSyncAll 自动做,picker 层
    /// dedup 是用户立即可见的保护。
    private var uniqueTeamMembers: [TeamMember] {
        var seen: Set<String> = []
        var out: [TeamMember] = []
        for m in teamMembers.sorted(by: { $0.joinedAt < $1.joinedAt }) {
            let key = m.userID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(m)
        }
        return out
    }

    private var assignmentSection: some View {
        Section {
            if uniqueTeamMembers.isEmpty {
                Text(String(localized: "还没有团队成员。先到 设置 → 团队 邀请成员。", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.fgDim)
            } else {
                Picker(
                    String(localized: "分配给", locale: AppLanguageManager.currentLocale),
                    selection: $assignedToUserID
                ) {
                    Text(String(localized: "未分配", locale: AppLanguageManager.currentLocale))
                        .tag(String?.none)
                    ForEach(uniqueTeamMembers, id: \.id) { m in
                        Text(m.displayName.isEmpty ? String(m.userID.prefix(8)) : m.displayName)
                            .tag(String?.some(m.userID))
                    }
                }
                .font(.system(size: 15))
            }
        } header: {
            SectionHeader(String(localized: "分配", locale: AppLanguageManager.currentLocale))
        }
    }

    private var notesSection: some View {
        Section {
            TextEditor(text: $notes)
                .font(.system(size: 15))
                .frame(minHeight: 80)
        } header: {
            SectionHeader(String(localized: "备注", locale: AppLanguageManager.currentLocale))
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle(
                String(localized: "启用提醒", locale: AppLanguageManager.currentLocale),
                isOn: $reminderEnabled
            )
            .font(.system(size: 15))

            if reminderEnabled {
                Picker(
                    String(localized: "提前提醒", locale: AppLanguageManager.currentLocale),
                    selection: $reminder1Minutes
                ) {
                    ForEach(leadOptionsPrimary, id: \.minutes) { opt in
                        Text(opt.label).tag(opt.minutes)
                    }
                }
                .font(.system(size: 15))
            }
        } header: {
            SectionHeader(String(localized: "提醒", locale: AppLanguageManager.currentLocale))
        } footer: {
            SectionFooter(String(localized: "提醒只在 pending 状态下触发,完成或取消后自动失效", locale: AppLanguageManager.currentLocale))
        }
    }

    // MARK: - Lifecycle

    private func loadInitialState() {
        if let existing = schedule {
            title = existing.title
            notes = existing.notes
            scheduledDate = existing.scheduledDate
            if let t = existing.scheduledTime {
                hasSpecificTime = true
                scheduledTime = t
            } else {
                hasSpecificTime = false
                scheduledTime = Calendar.current.date(
                    bySettingHour: 9, minute: 0, second: 0, of: existing.scheduledDate
                ) ?? Date()
            }
            siteTag = existing.siteTag
            reminderEnabled = existing.reminderEnabled
            reminder1Minutes = existing.reminder1Minutes
            // v1.3 不再用第二条提醒,旧数据强制覆盖为 0(下次保存关闭)。
            reminder2Minutes = 0
            assignedToUserID = existing.assignedToUserID
        } else {
            // 新建模式:用预填日期,时间默认 09:00。
            let base = prefilledDate ?? Date()
            scheduledDate = base
            scheduledTime = Calendar.current.date(
                bySettingHour: 9, minute: 0, second: 0, of: base
            ) ?? base
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let timeToStore: Date? = hasSpecificTime ? scheduledTime : nil

        let target: SiteVisitSchedule
        if let existing = schedule {
            existing.title = trimmedTitle
            existing.notes = notes
            existing.scheduledDate = scheduledDate
            existing.scheduledTime = timeToStore
            existing.siteTag = siteTag
            existing.reminderEnabled = reminderEnabled
            existing.reminder1Minutes = reminder1Minutes
            existing.reminder2Minutes = reminder2Minutes
            existing.assignedToUserID = assignedToUserID
            // P1 #194:save 失败写日志 — 失败时 UI 显示已改但磁盘没改,NotificationService 用脏数据
            do {
                try modelContext.save()
            } catch {
                Self.logger.error("save edit schedule failed: \(error.localizedDescription)")
            }
            NotificationService.shared.scheduleVisit(existing)
            target = existing
        } else {
            let new = SiteVisitSchedule(
                scheduledDate: scheduledDate,
                scheduledTime: timeToStore,
                siteTag: siteTag,
                title: trimmedTitle,
                notes: notes,
                reminderEnabled: reminderEnabled,
                reminder1Minutes: reminder1Minutes,
                reminder2Minutes: reminder2Minutes,
                assignedToUserID: assignedToUserID
            )
            modelContext.insert(new)
            do {
                try modelContext.save()
            } catch {
                Self.logger.error("save new schedule failed: \(error.localizedDescription)")
            }
            NotificationService.shared.scheduleVisit(new)
            target = new
        }
        // 团队 mirror:日历页新建/改 schedule 也得推到 share zone,member 才能收到分配。
        // 之前忘加这条,Owner 在日历页分配 hh 的所有 schedule 都没上云 → hh 永远收不到。
        let ctx = modelContext
        Task { await TeamDataMirrorService.shared.mirrorSchedule(target, in: ctx) }
        dismiss()
    }
}

#Preview("New") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SiteVisitSchedule.self, configurations: config)
    return ScheduleEditorSheet(schedule: nil, prefilledDate: nil)
        .modelContainer(container)
}
