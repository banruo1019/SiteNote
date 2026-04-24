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

    private override init() {
        super.init()
        center.delegate = self
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

    // MARK: - 排推送

    /// 给一条 Note 排推送(先 cancel 再重排)。
    func schedule(for note: Note) {
        cancel(for: note)
        guard !note.isDone, note.deadline.shouldSchedule else { return }

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

        for item in items {
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
            center.add(request)
        }
    }

    /// 取消一条 Note 的所有可能推送(枚举所有可能 identifier)。
    func cancel(for note: Note) {
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
    func updateDailyDigest() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyDigestIdentifier])

        let enabled = UserDefaults.standard.bool(forKey: "settings.dailyDigestEnabled")
        guard enabled else { return }

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
        center.add(request)
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
