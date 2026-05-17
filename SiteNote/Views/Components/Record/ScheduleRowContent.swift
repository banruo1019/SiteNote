//
//  ScheduleRowContent.swift
//  SiteNote
//
//  EngineerScheduleView 当日日程卡片里的单行视觉。
//  纯渲染:左侧 status 色条 + HH:MM + 标题 + 工地副标 + 完成 seal 图标。
//
//  parent 负责包 Button(进入编辑)+ contextMenu(标记完成/取消/删除)+ 行底分隔线,
//  这里只关心视觉本身。`isLast` 控制是否绘制底部 hairline。
//

import SwiftUI

struct ScheduleRowContent: View {
    let schedule: SiteVisitSchedule
    let isLast: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Self.statusColor(schedule.status))
                .frame(width: 3, height: 28)
            Text(Self.timeLabel(schedule))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.fgDim)
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.title.isEmpty
                     ? String(localized: "(无标题)", locale: AppLanguageManager.currentLocale)
                     : schedule.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(schedule.status == .cancelled ? Ink.fgDim : Ink.fg)
                    .strikethrough(schedule.status == .cancelled)
                    .lineLimit(1)
                if let tag = schedule.siteTag, !tag.isEmpty {
                    Text(tag)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if schedule.status == .completed {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 16))
                    .foregroundStyle(Ink.fgDim)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Ink.line).frame(height: 1)
            }
        }
    }

    /// 不同 status 对应的左侧色条颜色。
    static func statusColor(_ status: ScheduleStatus) -> Color {
        switch status {
        case .pending: return Ink.accentBlue
        case .completed: return Ink.green
        case .cancelled: return Ink.dim
        }
    }

    /// HH:MM 或 "全天"(scheduledTime nil)。
    static func timeLabel(_ s: SiteVisitSchedule) -> String {
        guard let t = s.scheduledTime else {
            return String(localized: "全天", locale: AppLanguageManager.currentLocale)
        }
        return Formatters.hourMinute.string(from: t)
    }
}
