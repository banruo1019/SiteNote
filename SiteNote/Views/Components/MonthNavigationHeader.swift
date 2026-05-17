//
//  MonthNavigationHeader.swift
//  SiteNote
//
//  M1 共享组件 — 月视图的"前一月 / 月份标签 / 后一月"导航 header。
//  PMCalendarView + EngineerScheduleView 都用。
//
//  视觉:chevron.left (40×32) + 居中月份(18pt 600 -0.2 tracking 等宽数字)+ chevron.right。
//  交互:左右点击切月,带 0.18s easeInOut 动画。
//
//  caller 通过 `@Binding currentMonth: Date` 传入月锚点;label 用 `Formatters.monthYear`。
//

import SwiftUI

struct MonthNavigationHeader: View {
    @Binding var currentMonth: Date

    var body: some View {
        HStack(spacing: 0) {
            navButton(systemName: "chevron.left", offset: -1)

            Spacer()

            Text(Formatters.monthYear.string(from: currentMonth))
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Ink.fg)
                .monospacedDigit()

            Spacer()

            navButton(systemName: "chevron.right", offset: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    /// 月切换按钮(chevron + 40×32 hit-area)。
    private func navButton(systemName: String, offset: Int) -> some View {
        Button {
            if let next = Calendar.current.date(byAdding: .month, value: offset, to: currentMonth) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    currentMonth = next
                }
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ink.fg2)
                .frame(width: 40, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
