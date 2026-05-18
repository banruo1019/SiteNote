//
//  IndustrialTabBar.swift
//  SiteNote
//
//  v1.3:PM 和 Engineer 统一 3 Tab —— 记 / 日历 / 报告。
//  设置走齿轮入口,不占 Tab。
//
//  v1.6 (en-v1):单行 localized 标签 — catalog 翻译 zh keys 到当前 locale。
//  原双行(中+英)在 en App Store 版本里看着像 bug,改成 SwiftUI 自动 i18n。
//

import SwiftUI

enum AppTab: Int, CaseIterable, Hashable {
    case record, calendar, reports

    /// Localized via xcstrings catalog — zh-Hans device shows "记 / 日历 / 报告",
    /// en device shows "Log / Calendar / Reports".
    var localizedTitle: String {
        let locale = AppLanguageManager.currentLocale
        switch self {
        case .record: return String(localized: "记", locale: locale)
        case .calendar: return String(localized: "日历", locale: locale)
        case .reports: return String(localized: "报告", locale: locale)
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
            Text(tab.localizedTitle)
                .font(.system(size: 14, weight: isOn ? .semibold : .regular))
                .tracking(0.2)
                .foregroundStyle(isOn ? Ink.fg : Ink.fgDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
