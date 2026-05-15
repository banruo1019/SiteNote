//
//  SiteVisitSchedule.swift
//  SiteNote
//
//  Engineer Profile 专属:工程师自己的排期表。
//  日历形式记录"几号去哪个工地做什么巡检 + 完成状态 + 提醒"。
//  与 Apple 系统日历**不强同步**(可后续扩展)— 本模型独立 SwiftData 表。
//

import Foundation
import SwiftData

@Model
final class SiteVisitSchedule {
    var id: UUID

    /// 计划日期(只取日期部分,时间用 scheduledTime 单独存)。
    var scheduledDate: Date

    /// 具体时间(可选)。如果 nil,视为"全天",通知按当天 9 AM 触发。
    var scheduledTime: Date?

    /// 关联工地(SiteTagsStorage 的字符串 tag),可空。
    var siteTag: String?

    /// 标题。每次只改这个,如 "FFL steel"、"Roof slab"、"Level 1 reo"。
    var title: String

    /// 备注。
    var notes: String

    /// 状态原始值,通过 `status` 计算属性读写。
    var statusRaw: String

    /// 完成时间(只 .completed 状态有)。
    var completedAt: Date?

    /// 是否启用提醒。
    var reminderEnabled: Bool

    /// 提前提醒分钟数 1(默认 1440 = 1 天)。
    var reminder1Minutes: Int

    /// 提前提醒分钟数 2(默认 60 = 1 小时)。0 = 关闭第二条。
    var reminder2Minutes: Int

    /// 创建时间。
    var createdAt: Date

    /// 软删时间。
    var deletedAt: Date?

    /// 关联的 InspectionReport ID(完成后用户点"基于此日程出报告"时回填)。
    var linkedReportID: UUID?

    var status: ScheduleStatus {
        get { ScheduleStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    /// 计算实际通知触发时间(scheduledDate + scheduledTime,如果有)。
    var fireDate: Date {
        if let time = scheduledTime {
            let cal = Calendar.current
            let dateComps = cal.dateComponents([.year, .month, .day], from: scheduledDate)
            let timeComps = cal.dateComponents([.hour, .minute], from: time)
            var combined = DateComponents()
            combined.year = dateComps.year
            combined.month = dateComps.month
            combined.day = dateComps.day
            combined.hour = timeComps.hour
            combined.minute = timeComps.minute
            return cal.date(from: combined) ?? scheduledDate
        } else {
            // 全天日程:当天 9 AM
            return Calendar.current.date(
                bySettingHour: 9, minute: 0, second: 0, of: scheduledDate
            ) ?? scheduledDate
        }
    }

    init(
        id: UUID = UUID(),
        scheduledDate: Date,
        scheduledTime: Date? = nil,
        siteTag: String? = nil,
        title: String = "",
        notes: String = "",
        reminderEnabled: Bool = true,
        reminder1Minutes: Int = 1440,
        reminder2Minutes: Int = 60
    ) {
        self.id = id
        self.scheduledDate = scheduledDate
        self.scheduledTime = scheduledTime
        self.siteTag = siteTag
        self.title = title
        self.notes = notes
        self.statusRaw = ScheduleStatus.pending.rawValue
        self.completedAt = nil
        self.reminderEnabled = reminderEnabled
        self.reminder1Minutes = reminder1Minutes
        self.reminder2Minutes = reminder2Minutes
        self.createdAt = Date()
        self.deletedAt = nil
        self.linkedReportID = nil
    }
}

enum ScheduleStatus: String, Codable {
    case pending      // 待执行
    case completed    // 已完成
    case cancelled    // 取消
}
