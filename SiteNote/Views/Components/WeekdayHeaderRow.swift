//
//  WeekdayHeaderRow.swift
//  SiteNote
//
//  日历 7 列 grid 上方的"一二三四五六日"星期 header。
//  PMCalendarView + EngineerScheduleView 共用。
//
//  weekday 顺序跟系统 Calendar.firstWeekday 一致(中文区一般是周一,
//  美区一般是周日),用 DateFormatter.veryShortStandaloneWeekdaySymbols
//  拿本地化的 1 字标签后按 firstWeekday rotate。
//

import SwiftUI

struct WeekdayHeaderRow: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Self.weekdayLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Ink.fgDim)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }

    /// 7 个 1 字本地化 weekday 标签,按 Calendar.firstWeekday 旋转后顺序。
    /// 静态计算 — locale 变了用户得重启 app(本项目已有提示),所以缓存安全。
    static let weekdayLabels: [String] = {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = AppLanguageManager.currentLocale
        let symbols = f.veryShortStandaloneWeekdaySymbols ?? [] // index 0 = Sunday
        guard symbols.count == 7 else { return [] }
        let offset = cal.firstWeekday - 1
        return (0..<7).map { symbols[(offset + $0) % 7] }
    }()
}
