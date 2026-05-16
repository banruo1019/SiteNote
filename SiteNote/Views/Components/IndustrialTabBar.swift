//
//  IndustrialTabBar.swift
//  SiteNote
//
//  v1.3:PM 和 Engineer 统一 3 Tab —— 记 / 日历 / 报告。
//  设置走齿轮入口,不占 Tab。
//
//  M1 Linear 风。文字双行(中文 + English),激活靠字重+颜色。
//

import SwiftUI

enum AppTab: Int, CaseIterable, Hashable {
    case record, calendar, reports

    var zh: String {
        switch self {
        case .record: return "记"
        case .calendar: return "日历"
        case .reports: return "报告"
        }
    }

    var en: String {
        switch self {
        case .record: return "Record"
        case .calendar: return "Calendar"
        case .reports: return "Reports"
        }
    }
}

struct IndustrialTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(
            Ink.bg
                .overlay(alignment: .top) {
                    Rectangle().fill(Ink.line).frame(height: 1)
                }
        )
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isOn = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Text(tab.zh)
                    .font(.system(size: 15, weight: isOn ? .semibold : .regular))
                    .tracking(-0.2)
                    .foregroundStyle(isOn ? Ink.fg : Ink.fgDim)
                Text(tab.en)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(isOn ? Ink.fgDim : Ink.dim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
