//
//  IPadRootView.swift
//  SiteNote
//
//  iPad 三栏布局根 view(R2 — 占位骨架)。
//
//  当前实现:NavigationSplitView 三栏 + sidebar 5 sections,
//  detail 区域全部是 placeholder。R3 起逐 section 接入真实 view。
//
//  约束(`IPAD_PLAN.md`):
//  - sidebar 240pt(min 200 max 280)
//  - content list 340pt(min 300 max 400)
//  - detail 剩余宽度
//  - `.navigationSplitViewStyle(.balanced)` 让竖屏自动 stack
//  - **不引用 MainTabView**(那是 iPhone 路径)
//  - 复用所有现有 detail view(RecordView / EngineerReportsView 等)
//

import SwiftUI

/// iPad sidebar 5 sections。固定顺序,按使用频率。
enum IPadSection: String, Hashable, CaseIterable, Identifiable {
    case record       // 记
    case schedule     // 日程
    case reports      // 报告
    case team         // 团队
    case settings     // 设置

    var id: String { rawValue }

    var label: String {
        switch self {
        case .record:   return String(localized: "记", locale: AppLanguageManager.currentLocale)
        case .schedule: return String(localized: "日程", locale: AppLanguageManager.currentLocale)
        case .reports:  return String(localized: "报告", locale: AppLanguageManager.currentLocale)
        case .team:     return String(localized: "团队", locale: AppLanguageManager.currentLocale)
        case .settings: return String(localized: "设置", locale: AppLanguageManager.currentLocale)
        }
    }

    var systemImage: String {
        switch self {
        case .record:   return "mic.circle.fill"
        case .schedule: return "calendar"
        case .reports:  return "doc.text"
        case .team:     return "person.2.fill"
        case .settings: return "gearshape"
        }
    }
}

struct IPadRootView: View {
    @State private var selection: IPadSection? = .record

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        } detail: {
            detailFor(selection)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Ink.accent)
        .preferredColorScheme(.light)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(IPadSection.allCases, selection: $selection) { section in
            NavigationLink(value: section) {
                Label(section.label, systemImage: section.systemImage)
                    .font(.system(size: 14, weight: .medium))
            }
        }
        .navigationTitle(String(localized: "SiteNote", locale: AppLanguageManager.currentLocale))
        .listStyle(.sidebar)
    }

    // MARK: - Detail dispatch(R3+ 逐个接入)

    @ViewBuilder
    private func detailFor(_ section: IPadSection?) -> some View {
        switch section {
        case .record, .none:
            // R3 占位 — R6 切到 RecordView 三栏布局
            placeholder("录音 / 速记", systemImage: "mic.circle.fill")
        case .schedule:
            // R3 占位 — R5 切到 EngineerScheduleView 三栏布局
            placeholder("日程", systemImage: "calendar")
        case .reports:
            // R3 占位 — R4 切到 EngineerReportsView 三栏布局
            placeholder("报告", systemImage: "doc.text")
        case .team:
            // R3 占位 — v2 切到 TeamManagementView 三栏布局
            placeholder("团队", systemImage: "person.2.fill")
        case .settings:
            // R3 占位 — 复用 EngineerSettingsRoot
            placeholder("设置", systemImage: "gearshape")
        }
    }

    /// R2/R3 阶段所有 detail 都是这个占位 — 灰底 + icon + 文字 + "即将接入" 提示。
    private func placeholder(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Ink.dim)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Ink.fg2)
            Text(String(localized: "iPad 三栏布局占位 — 后续 Phase 接入", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 12))
                .foregroundStyle(Ink.fgDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.bg)
    }
}

#Preview("iPad Pro 13") {
    IPadRootView()
}
