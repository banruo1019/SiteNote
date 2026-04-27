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
            content.title = "SiteNote · 今日检查"
            content.body = "打开查看今日待处理任务"
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
            title = "🚨 SiteNote 隐患待处理"
            body = "请打开 App 查看详情"
        } else {
            title = "SiteNote 提醒"
            body = "你有 1 条速记到期 · 请打开 App 查看"
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
