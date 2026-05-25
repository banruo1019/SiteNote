//
//  TeamAssignmentNotifier.swift
//  SiteNote
//
//  团队协作:Member 端"被分配新工地"感知。
//
//  设计:
//  - CloudKit 把 Owner 新建并 assignedToUserID = <me> 的 SiteVisitSchedule 拉到本机后,
//    @Query 自动跟着变,但 SwiftUI 层不知道"哪些是新出现的"。
//  - 这里给一个 scanAndNotify(...) 探测入口:对未通知过的新分配弹 local notification +
//    记 UserDefaults Set<UUID.uuidString>。row 上的 NEW badge 通过 isNotified(_:) 反向问。
//  - markRead(_:) 给用户点开 row 后清 badge —— 等于把"未读"也并到这个 set。
//
//  其它 actor 注意:整个 API 标 @MainActor 是因为
//  ① UserDefaults 写读没必要做线程隔离但 SwiftUI 调用点都在主线程
//  ② 入参 [SiteVisitSchedule] 是 SwiftData model,本来就该在 ModelContext 所在线程访问。
//

import Foundation

@MainActor
final class TeamAssignmentNotifier {

    static let shared = TeamAssignmentNotifier()

    /// 已通知过(或已被点开读过)的 schedule.id 集合,UserDefaults 持久化。
    private static let key = "team.assignment.notified.v1"

    private var notifiedIDs: Set<String>

    private init() {
        let arr = UserDefaults.standard.array(forKey: Self.key) as? [String] ?? []
        self.notifiedIDs = Set(arr)
    }

    /// 扫一遍 schedules,对"分给我 + 未通知过"的弹 local notification + 标记。
    /// - Parameter schedules: 当前 @Query 出来的全部 schedule(传 Array(allSchedules) 即可)
    /// - Returns: 本次新发现并通知的条数(调用方一般不需要,留作日志用)
    @discardableResult
    func scanAndNotify(_ schedules: [SiteVisitSchedule]) -> Int {
        let me = ICloudSyncConfig.shared.currentUserRecordName ?? ""
        // 未登录(没拿到 user record)→ 无从判断"分给我",直接 return。
        guard !me.isEmpty else { return 0 }

        var newCount = 0
        for s in schedules {
            guard let assignee = s.assignedToUserID, assignee == me else { continue }
            // 已软删的不弹。
            guard s.deletedAt == nil else { continue }
            let key = s.id.uuidString
            if notifiedIDs.contains(key) { continue }
            NotificationService.shared.notifyNewAssignment(s)
            notifiedIDs.insert(key)
            newCount += 1
        }
        if newCount > 0 {
            save()
        }
        return newCount
    }

    /// 某条 schedule 是否已通知/已读过(用于 row 上 NEW badge 反向展示)。
    func isNotified(_ id: UUID) -> Bool {
        notifiedIDs.contains(id.uuidString)
    }

    /// 用户点开 row → 清 NEW badge。
    /// 与 scanAndNotify 共用 set:已点开过的不会再弹通知。
    func markRead(_ id: UUID) {
        let key = id.uuidString
        guard !notifiedIDs.contains(key) else { return }
        notifiedIDs.insert(key)
        save()
    }

    private func save() {
        UserDefaults.standard.set(Array(notifiedIDs), forKey: Self.key)
    }
}
