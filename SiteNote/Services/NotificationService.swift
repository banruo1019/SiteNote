//
//  NotificationService.swift
//  SiteNote
//
//  本地推送调度。两级策略 + 可选每日汇总。
//
//  - Normal(非隐患):每天早上 1 次,7 天内为限
//  - Hazard(隐患):每天早上 + 晚上 2 次,Day 3+ 加中午,10 天为限
//  - `.inbox` / `.archive` / `isDone=true` 都不排
//  - 每日汇总(可选):repeats=true 的定时 "查看今日任务" 提醒
//
//  调度逻辑 `computeSchedule` 是纯函数,方便单元测试。
//

import Foundation
import SwiftData
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationService()

    /// 每日汇总的固定 identifier。
    private static let dailyDigestIdentifier = "sitenote.daily-digest"

    private let center = UNUserNotificationCenter.current()

    // MARK: - 在飞 task 跟踪(防 schedule 异步化引入的竞态)
    //
    // schedule(for:) 改成异步后内部启 Task 跑 ensureAuthorized + add。
    // 如果不跟踪,后续的 cancel(for:) 抓不到还在 await 的 Task,会导致:
    //   - 删除/撤销/标完成的 note 仍然到点响
    //   - 同一 note 连排两次时序不定,后排的可能被先排的覆盖
    // updateDailyDigest 也有相同问题(开后秒关时,关那次拦不住前一次 add)。
    private let stateLock = NSLock()
    private var inFlightSchedules: [UUID: (gen: Int, task: Task<Void, Never>)] = [:]
    private var scheduleGenerations: [UUID: Int] = [:]
    private var digestTask: Task<Void, Never>?

    private override init() {
        super.init()
        center.delegate = self
    }

    /// 注册一个新的 in-flight schedule task,返回它的 generation。
    /// **同时取消同 note 上一次的 task**(原子)。
    /// 完成后用 `clearScheduleIfCurrent(_:for:)` 自清,避免字典只增不减。
    private func registerSchedule(_ task: Task<Void, Never>, for id: UUID) -> Int {
        stateLock.lock()
        let nextGen = (scheduleGenerations[id] ?? 0) + 1
        scheduleGenerations[id] = nextGen
        let old = inFlightSchedules[id]?.task
        inFlightSchedules[id] = (gen: nextGen, task: task)
        stateLock.unlock()
        old?.cancel()
        return nextGen
    }

    /// cancel(for:) 用:取消当前 in-flight,并清条目。
    private func cancelSchedule(for id: UUID) {
        stateLock.lock()
        let old = inFlightSchedules.removeValue(forKey: id)?.task
        stateLock.unlock()
        old?.cancel()
    }

    /// Task 自然结束时调用:仅当字典里仍是自己时才移除条目。
    /// 如果中途被新一轮 schedule 替换了,什么都不做(替换时 registerSchedule 已 cancel 老 task)。
    private func clearScheduleIfCurrent(_ gen: Int, for id: UUID) {
        stateLock.lock()
        if inFlightSchedules[id]?.gen == gen {
            inFlightSchedules.removeValue(forKey: id)
        }
        stateLock.unlock()
    }

    /// 替换 digest task,同时取消老的(原子)。
    private func setDigestTask(_ task: Task<Void, Never>?) {
        stateLock.lock()
        let old = digestTask
        digestTask = task
        stateLock.unlock()
        old?.cancel()
    }

    // MARK: - 权限

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch { return false }
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    /// 排推送前的统一授权门。
    /// - `.notDetermined`: 弹系统对话框,等用户选择。
    /// - `.authorized` / `.provisional`: 直接放行。
    /// - `.denied`: 返回 false,后续 add 全部跳过(避免无效系统调用 + 误判"已排上")。
    private func ensureAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await requestAuthorization()
        @unknown default:
            return false
        }
    }

    // MARK: - 排推送

    /// 给一条 Note 排推送(先 cancel 再重排)。
    /// 不排推送的情况:已完成 / deadline 不要求(.inbox / .archive)/ **施工日记**(它不是 todo)。
    /// 异步:内部走 `ensureAuthorized` 等系统授权完成后才 add,避免首装时 .notDetermined → add 落空。
    func schedule(for note: Note) {
        cancel(for: note)
        guard !note.isDone, !note.isDiaryRecord, note.deadline.shouldSchedule else { return }

        let config = ScheduleConfig.current()
        let items = Self.computeSchedule(
            for: ScheduleInput(
                noteID: note.id,
                dueDate: note.dueDate,
                transcription: note.transcription,
                isHazard: note.isHazard
            ),
            now: Date(),
            config: config
        )
        guard !items.isEmpty else { return }

        let noteID = note.id
        let task = Task { @MainActor [center] in
            guard await Self.shared.ensureAuthorized() else {
                print("[SiteNote] NotificationService.schedule: 通知未授权,跳过 \(items.count) 条")
                return
            }
            // 授权 await 期间可能被 cancel(for:) 取消;退出避免给已被取消的 note 重新排上。
            if Task.isCancelled { return }
            for item in items {
                if Task.isCancelled { return }
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default

                let cal = Calendar.current
                let components = cal.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: item.fireDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
                do {
                    try await center.add(request)
                } catch is CancellationError {
                    return
                } catch {
                    print("[SiteNote] NotificationService.schedule add 失败: \(item.identifier) · \(error.localizedDescription)")
                }
            }
        }
        let gen = registerSchedule(task, for: noteID)
        // Task 完成后自清字典条目(只在仍是当前 gen 时)。
        Task { @MainActor in
            await task.value
            Self.shared.clearScheduleIfCurrent(gen, for: noteID)
        }
    }

    /// 取消一条 Note 的所有可能推送(枚举所有可能 identifier)。
    /// 同时 cancel 还在 await 中的 in-flight schedule Task,避免它醒来再 add。
    func cancel(for note: Note) {
        cancelSchedule(for: note.id)
        let ids = Self.possibleIdentifiers(noteID: note.id)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// App 启动时对全部未完成未归档重排。同时更新每日汇总。
    func rescheduleAll(notes: [Note]) {
        for note in notes where !note.isDone && note.deadline.shouldSchedule {
            schedule(for: note)
        }
        updateDailyDigest()
    }

    // MARK: - 每日汇总

    /// 按用户设置开关 + 早上时间安排每日汇总(repeats=true 一次排永续)。
    /// 异步:同样走 `ensureAuthorized` 授权门,避免首装"看着开了但实际没排"。
    /// 竞态防护:跟踪 digestTask 并在新一轮调用时 cancel 老 task;在 await 后再读一次
    /// UserDefaults,防止"开了又秒关"的情况下被旧 task 抢着 add。
    func updateDailyDigest() {
        setDigestTask(nil)
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyDigestIdentifier])

        let enabled = UserDefaults.standard.bool(forKey: "settings.dailyDigestEnabled")
        guard enabled else { return }

        let task = Task { @MainActor [center] in
            guard await Self.shared.ensureAuthorized() else {
                print("[SiteNote] NotificationService.updateDailyDigest: 通知未授权,跳过")
                return
            }
            if Task.isCancelled { return }

            // 授权 await 期间用户可能已经把开关关回去,或者改了时间。重读一次 settings。
            let stillEnabled = UserDefaults.standard.bool(forKey: "settings.dailyDigestEnabled")
            guard stillEnabled else {
                print("[SiteNote] NotificationService.updateDailyDigest: 授权后再读发现已关,放弃")
                return
            }
            let morningHour = UserDefaults.standard.object(forKey: "settings.morningReminderHour") as? Int ?? 7
            let morningMinute = UserDefaults.standard.object(forKey: "settings.morningReminderMinute") as? Int ?? 30

            let content = UNMutableNotificationContent()
            content.title = String(localized: "SiteNote · 今日检查", locale: AppLanguageManager.currentLocale)
            content.body = String(localized: "打开查看今日待处理任务", locale: AppLanguageManager.currentLocale)
            content.sound = .default

            var components = DateComponents()
            components.hour = morningHour
            components.minute = morningMinute

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: Self.dailyDigestIdentifier,
                content: content,
                trigger: trigger
            )
            if Task.isCancelled { return }
            do {
                try await center.add(request)
            } catch is CancellationError {
                return
            } catch {
                print("[SiteNote] NotificationService.updateDailyDigest add 失败: \(error.localizedDescription)")
            }
        }
        setDigestTask(task)
    }

    // MARK: - 前台展示

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // MARK: - 纯函数调度计算(给单元测试用)

    struct ScheduleInput {
        let noteID: UUID
        let dueDate: Date
        let transcription: String
        let isHazard: Bool
    }

    struct ScheduleConfig {
        let morningHour: Int
        let morningMinute: Int
        let noonHour: Int
        let eveningHour: Int
        let normalMaxDays: Int
        let normalMaxSlots: Int
        let hazardMaxDays: Int
        let hazardMaxSlots: Int

        static func current() -> ScheduleConfig {
            let morningHour = UserDefaults.standard.object(forKey: "settings.morningReminderHour") as? Int ?? 7
            let morningMinute = UserDefaults.standard.object(forKey: "settings.morningReminderMinute") as? Int ?? 30
            return ScheduleConfig(
                morningHour: morningHour,
                morningMinute: morningMinute,
                noonHour: 12,
                eveningHour: 18,
                normalMaxDays: 7,
                normalMaxSlots: 7,
                hazardMaxDays: 10,
                hazardMaxSlots: 15
            )
        }

        static let defaultForTests = ScheduleConfig(
            morningHour: 7, morningMinute: 30,
            noonHour: 12, eveningHour: 18,
            normalMaxDays: 7, normalMaxSlots: 7,
            hazardMaxDays: 10, hazardMaxSlots: 15
        )
    }

    struct ScheduledItem: Equatable {
        let identifier: String
        let fireDate: Date
        let title: String
        let body: String
    }

    /// 核心调度算法——纯函数,不依赖 UNUserNotificationCenter,可单元测试。
    /// - Parameters:
    ///   - input: note 的调度相关字段
    ///   - now: 参考时间(测试注入固定值)
    ///   - config: 时段和上限
    /// - Returns: 应该排的所有 (identifier, fireDate, title, body) 条目
    static func computeSchedule(
        for input: ScheduleInput,
        now: Date,
        config: ScheduleConfig
    ) -> [ScheduledItem] {
        let cal = Calendar.current
        let dueDay = cal.startOfDay(for: input.dueDate)

        let maxDays = input.isHazard ? config.hazardMaxDays : config.normalMaxDays
        let maxSlots = input.isHazard ? config.hazardMaxSlots : config.normalMaxSlots

        // 隐私脱敏:推送 body **不带任何原始 transcription**。锁屏/通知中心是公开面,
        // 工地业务文本对路人/同事/家人都不该可见。原文交给用户点开 App 看。
        let title: String
        let body: String
        if input.isHazard {
            title = String(localized: "🚨 SiteNote 隐患待处理", locale: AppLanguageManager.currentLocale)
            body = String(localized: "请打开 App 查看详情", locale: AppLanguageManager.currentLocale)
        } else {
            title = String(localized: "SiteNote 提醒", locale: AppLanguageManager.currentLocale)
            body = String(localized: "你有 1 条速记到期 · 请打开 App 查看", locale: AppLanguageManager.currentLocale)
        }

        var out: [ScheduledItem] = []

        for dayOffset in 0...maxDays {
            if out.count >= maxSlots { break }
            guard let targetDay = cal.date(byAdding: .day, value: dayOffset, to: dueDay) else { continue }

            let slots = daySlots(dayOffset: dayOffset, isHazard: input.isHazard, config: config)

            for slot in slots {
                if out.count >= maxSlots { break }
                guard let fireDate = cal.date(
                    bySettingHour: slot.hour,
                    minute: slot.minute,
                    second: 0,
                    of: targetDay
                ) else { continue }
                guard fireDate > now else { continue }

                let identifier = "\(input.noteID.uuidString)-d\(dayOffset)-h\(slot.hour)m\(slot.minute)"
                out.append(ScheduledItem(
                    identifier: identifier,
                    fireDate: fireDate,
                    title: title,
                    body: body
                ))
            }
        }
        return out
    }

    /// 一天内要推的时段列表(hour, minute)。比老版简化很多。
    private static func daySlots(
        dayOffset: Int,
        isHazard: Bool,
        config: ScheduleConfig
    ) -> [(hour: Int, minute: Int)] {
        let morning = (config.morningHour, config.morningMinute)
        let noon = (config.noonHour, 0)
        let evening = (config.eveningHour, 0)

        if isHazard {
            if dayOffset < 3 {
                return [morning, evening]       // Day 0-2:早 + 晚
            } else {
                return [morning, noon, evening] // Day 3+:早 + 中 + 晚
            }
        } else {
            return [morning] // Normal:每天只早推一次
        }
    }

    /// 枚举一条 note 在理论上可能存在的所有 identifier(用于 cancel)。
    private static func possibleIdentifiers(noteID: UUID) -> [String] {
        var ids: [String] = []
        // 过去各种配置可能产生的 hour/minute 组合都列出来,以便老数据也能清掉。
        let hours = [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
        let minutes = [0, 15, 30, 45]
        for dayOffset in 0...14 {
            for h in hours {
                for m in minutes {
                    ids.append("\(noteID.uuidString)-d\(dayOffset)-h\(h)m\(m)")
                }
            }
        }
        return ids
    }
}

// MARK: - SiteVisitSchedule(Engineer 日程)推送

extension NotificationService {

    /// 日程通知 identifier 前缀(集中一处,方便 cancel / 调试)。
    /// 形如 `visit-<uuid>-r1` / `visit-<uuid>-r2`。
    static let scheduleIdentifierPrefix = "visit"

    /// 同一条 schedule 最多 2 条提醒,固定 r1 / r2 后缀。
    static func scheduleIdentifiers(for scheduleID: UUID) -> [String] {
        [
            "\(scheduleIdentifierPrefix)-\(scheduleID.uuidString)-r1",
            "\(scheduleIdentifierPrefix)-\(scheduleID.uuidString)-r2"
        ]
    }

    /// 排日程提醒。先 cancel 老的再排新的。
    /// 不排的情况:reminderEnabled = false / status != .pending / fireDate 已过 /
    /// reminder 触发点也已过(reminder1Minutes / reminder2Minutes 减出来在 now 之前)。
    /// 同一 schedule 可能有 2 条通知(reminder1Minutes 和 reminder2Minutes,后者 0 = 关闭)。
    func scheduleVisit(_ schedule: SiteVisitSchedule) {
        cancelVisit(schedule.id)
        guard schedule.reminderEnabled, schedule.status == .pending, schedule.deletedAt == nil else { return }

        let fireDate = schedule.fireDate
        let now = Date()
        // fireDate 本身已过 → 不再排。
        guard fireDate > now else { return }

        // 业务标题:优先 "标题 · 工地",其次 "标题",再次 "日程提醒"。
        let body: String = {
            if let tag = schedule.siteTag, !tag.isEmpty {
                return tag
            }
            return ""
        }()
        let title: String = {
            if !schedule.title.isEmpty { return schedule.title }
            return String(localized: "日程提醒", locale: AppLanguageManager.currentLocale)
        }()

        // 候选两条提醒:r1 必有(reminder1Minutes 总有值),r2 仅在 reminder2Minutes > 0 时排。
        struct Reminder {
            let suffix: String
            let triggerDate: Date
            let leadMinutes: Int
        }
        var reminders: [Reminder] = []
        if let t1 = Calendar.current.date(byAdding: .minute, value: -schedule.reminder1Minutes, to: fireDate),
           t1 > now {
            reminders.append(.init(suffix: "r1", triggerDate: t1, leadMinutes: schedule.reminder1Minutes))
        }
        if schedule.reminder2Minutes > 0,
           let t2 = Calendar.current.date(byAdding: .minute, value: -schedule.reminder2Minutes, to: fireDate),
           t2 > now {
            reminders.append(.init(suffix: "r2", triggerDate: t2, leadMinutes: schedule.reminder2Minutes))
        }
        guard !reminders.isEmpty else { return }

        let scheduleID = schedule.id
        let task = Task { @MainActor [center] in
            guard await Self.shared.ensureAuthorized() else {
                print("[SiteNote] NotificationService.scheduleVisit: 通知未授权,跳过 \(reminders.count) 条")
                return
            }
            if Task.isCancelled { return }
            for r in reminders {
                if Task.isCancelled { return }
                let content = UNMutableNotificationContent()
                content.title = title
                let leadLabel = Self.leadTimeLabel(minutes: r.leadMinutes)
                if body.isEmpty {
                    content.body = leadLabel
                } else {
                    content.body = "\(body) · \(leadLabel)"
                }
                content.sound = .default

                let cal = Calendar.current
                let components = cal.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: r.triggerDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let identifier = "\(Self.scheduleIdentifierPrefix)-\(scheduleID.uuidString)-\(r.suffix)"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                do {
                    try await center.add(request)
                } catch is CancellationError {
                    return
                } catch {
                    print("[SiteNote] NotificationService.scheduleVisit add 失败: \(identifier) · \(error.localizedDescription)")
                }
            }
        }
        // 复用 Note 的竞态防护(同一 UUID 空间不冲突 — Note 和 Schedule 的 UUID 不会撞)。
        let gen = registerSchedule(task, for: scheduleID)
        Task { @MainActor in
            await task.value
            Self.shared.clearScheduleIfCurrent(gen, for: scheduleID)
        }
    }

    /// 取消某 schedule 的全部通知 + in-flight task。
    func cancelVisit(_ scheduleID: UUID) {
        cancelSchedule(for: scheduleID)
        let ids = Self.scheduleIdentifiers(for: scheduleID)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// 全量重排所有 pending 的日程(启动时 + 时区改变时调)。
    /// 注意:不在这里清"老 schedule 的孤儿通知"——通过 cancelVisit 在删/改时已经清过。
    @MainActor
    func rescheduleAllVisits(in context: ModelContext) {
        let descriptor = FetchDescriptor<SiteVisitSchedule>(
            predicate: #Predicate<SiteVisitSchedule> { $0.deletedAt == nil && $0.statusRaw == "pending" }
        )
        guard let schedules = try? context.fetch(descriptor) else { return }
        for s in schedules {
            scheduleVisit(s)
        }
    }

    /// 团队协作:Owner 给 Member 分配新工地时,Member 端 1 秒后弹 local notification 提醒。
    /// 调用方:`TeamAssignmentNotifier.scanAndNotify(_:)` 内,已做"分给我 + 未通知过"过滤。
    /// 用 UNTimeIntervalNotificationTrigger(1s) 是因为这是"探测时立即提醒",不需要业务时间排程,
    /// 而 add(request) 本身要求 trigger ≥ now,所以给个最小的 1s。
    /// identifier 用 "assign-<scheduleID>" 防同一条 schedule 重弹(系统层面 dedupe)。
    func notifyNewAssignment(_ schedule: SiteVisitSchedule) {
        let content = UNMutableNotificationContent()
        content.title = String(
            localized: "新工地分配",
            locale: AppLanguageManager.currentLocale
        )
        let label: String = {
            let title = schedule.title.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return title }
            if let tag = schedule.siteTag, !tag.isEmpty { return tag }
            return String(localized: "工地", locale: AppLanguageManager.currentLocale)
        }()
        content.body = String(
            format: String(localized: "你被分配到「%@」", locale: AppLanguageManager.currentLocale),
            label
        )
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "assign-\(schedule.id.uuidString)",
            content: content,
            trigger: trigger
        )
        center.add(request, withCompletionHandler: nil)
    }

    /// 把提前分钟数翻译成人话:1d / 2h / 30m。
    private static func leadTimeLabel(minutes: Int) -> String {
        if minutes <= 0 {
            return String(localized: "现在", locale: AppLanguageManager.currentLocale)
        }
        if minutes % 1440 == 0 {
            let days = minutes / 1440
            if days == 1 {
                return String(localized: "明天", locale: AppLanguageManager.currentLocale)
            }
            return String(localized: "\(days) 天后", locale: AppLanguageManager.currentLocale)
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return String(localized: "\(hours) 小时后", locale: AppLanguageManager.currentLocale)
        }
        return String(localized: "\(minutes) 分钟后", locale: AppLanguageManager.currentLocale)
    }
}
