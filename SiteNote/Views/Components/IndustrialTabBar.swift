//
//  IndustrialTabBar.swift
//  SiteNote
//
//  M1 Linear 风 Tab Bar。文字双行(中文 + English),激活靠字重+颜色。
//  视觉居中:内容 padding 上下对称,不强行 `ignoresSafeArea(edges:.bottom)`,
//  否则在 iPhone Pro Max 这种大底边安全区的机型上,文字会因为背景下沉而显得偏上。
//  安全区交给父级的 `Ink.bg.ignoresSafeArea()` 托底,这里只管 tab 本身的视觉盒子。
//

import SwiftUI

enum AppTab: Int, CaseIterable, Hashable {
    case record, log, reports, schedule, settings

    var zh: String {
        switch self {
        case .record: return "记"
        case .log: return "日志"
        case .reports: return "报告"
        case .schedule: return "日程"
        case .settings: return "设置"
        }
    }

    var en: String {
        switch self {
        case .record: return "Record"
        case .log: return "Log"
        case .reports: return "Reports"
        case .schedule: return "Schedule"
        case .settings: return "Settings"
        }
    }
}

struct IndustrialTabBar: View {
    @Binding var selection: AppTab
    /// Engineer 角色下 LogTab 隐藏(R6)。MainTabView 通过这个开关传入 Profile 状态。
    /// 默认 false 保持 PM 行为不变。
    var hidesLog: Bool = false
    /// Engineer 角色 4 Tab 模式:记 / 报告 / 日程 / 设置(EA)。
    /// 显式开关而非完全靠 `hidesLog` 推断 —— PM 永远是 3 Tab(记/日志/报告);
    /// Engineer 切到这条分支后,Tab bar 会展示 Schedule + Settings 入口。
    var isEngineerMode: Bool = false

    private var visibleTabs: [AppTab] {
        if isEngineerMode {
            return [.record, .reports, .schedule, .settings]
        }
        return hidesLog ? AppTab.allCases.filter { $0 != .log && $0 != .schedule && $0 != .settings }
                        : AppTab.allCases.filter { $0 != .schedule && $0 != .settings }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tab in
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
