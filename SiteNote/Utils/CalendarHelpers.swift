//
//  CalendarHelpers.swift
//  SiteNote
//
//  日历视图共享 helper —— 月视图的 cell 序列生成。
//
//  PMCalendarView + EngineerScheduleView 都需要"给定月份,产出 42 个 cell
//  (6 行 × 7 列)"的逻辑,前面用各自的 private struct 包装 `Date?`。统一成
//  `[Date?]` 数组,nil 表示该 cell 在月份范围外的占位。
//

import Foundation

enum CalendarHelpers {
    /// 给定一个月份锚点,返回 42 个 `Date?` cell:
    /// - 前导 nil(为对齐 Calendar.firstWeekday)
    /// - 该月 1...N 日 Date
    /// - 后导 nil(补满到 42 个,固定 6 行,避免月切换时 grid 高度跳变)
    static func monthCells(for anchor: Date) -> [Date?] {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: anchor)) ?? anchor
        let range = cal.range(of: .day, in: .month, for: monthStart) ?? 1..<2
        let firstWeekdayOfMonth = cal.component(.weekday, from: monthStart) // 1...7
        let leadingEmpty = (firstWeekdayOfMonth - cal.firstWeekday + 7) % 7

        var cells: [Date?] = []
        for _ in 0..<leadingEmpty {
            cells.append(nil)
        }
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: monthStart) {
                cells.append(d)
            }
        }
        while cells.count < 42 {
            cells.append(nil)
        }
        return cells
    }
}
