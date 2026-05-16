//
//  MainTabView.swift
//  SiteNote
//
//  v1.2 大减负:PM 从 3 Tab(记/日志/报告)→ 2 Tab(记/报告)。
//  日志台账整套下架(LogEntry 模型保留为数据兼容,UI 不再暴露)。
//  Engineer 仍是 4 Tab:记 / 报告 / 日程 / 设置。
//
//  自定义 TabBar 替代系统 TabView,文字双行(中文 + English),
//  激活指示靠字重+颜色,无背景填充、无下划线、无顶边。
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selection: AppTab = .record
    @State private var showsOnboarding: Bool = OnboardingView.needsToShow
    @State private var router = AppRouter.shared
    @State private var profileManager = UserProfileManager.shared

    private var isEngineer: Bool {
        profileManager.current == .engineer
    }

    var body: some View {
        ZStack {
            mainContent
            if showsOnboarding {
                OnboardingView(isShown: $showsOnboarding)
                    .zIndex(100)
            }
        }
        .onChange(of: router.pendingTab) { _, request in
            // 消费 AppRouter 信号:别处请求切 tab 时切。
            guard let request else { return }
            selection = request.tab
            router.clear()
        }
        .onChange(of: profileManager.current) { _, _ in
            // 切到 Engineer 时如果当前停在 PM 没有的 tab,切回 .record(防御性)。
            // 切到 PM 时,Engineer 的 .schedule / .settings tab 也回 .record。
            if !isEngineer && (selection == .schedule || selection == .settings) {
                selection = .record
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if isEngineer {
            engineerContent
        } else {
            pmContent
        }
    }

    // MARK: - Engineer 独立 4 Tab 软件
    //
    // Engineer 完全独立 UI:不渲染 PM 的 RecordView / ReportsView,
    // 走 EngineerRecordView / EngineerReportsView / EngineerScheduleView / SettingsView。
    //
    // 与 PM 一样保留"tab 常驻"原则,只通过 opacity / hit-testing 切换,
    // 让 EngineerRecordView 的 ViewModel 状态(录音 staged photo)在 Tab 切换时保留。
    private var engineerContent: some View {
        VStack(spacing: 0) {
            ZStack {
                EngineerRecordView()
                    .opacity(selection == .record ? 1 : 0)
                    .allowsHitTesting(selection == .record)
                EngineerReportsView()
                    .opacity(selection == .reports ? 1 : 0)
                    .allowsHitTesting(selection == .reports)
                EngineerScheduleView()
                    .opacity(selection == .schedule ? 1 : 0)
                    .allowsHitTesting(selection == .schedule)
                NavigationStack {
                    SettingsView()
                }
                .opacity(selection == .settings ? 1 : 0)
                .allowsHitTesting(selection == .settings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            IndustrialTabBar(selection: $selection, isEngineerMode: true)
        }
        .background(Ink.bg.ignoresSafeArea())
        .tint(Ink.accent)
        .preferredColorScheme(.light)
    }

    // MARK: - PM 2 Tab 软件(v1.2 大减负后从 3 Tab 缩为 2 Tab)
    private var pmContent: some View {
        VStack(spacing: 0) {
            // tab view 常驻,切换只改 opacity/hit-testing。
            // 不能用 `@ViewBuilder switch`:那会销毁未选中的 view,导致折叠状态、
            // 筛选、搜索、滚动位置一切归零。
            ZStack {
                RecordView()
                    .opacity(selection == .record ? 1 : 0)
                    .allowsHitTesting(selection == .record)
                ReportsView()
                    .opacity(selection == .reports ? 1 : 0)
                    .allowsHitTesting(selection == .reports)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            IndustrialTabBar(selection: $selection)
        }
        .background(Ink.bg.ignoresSafeArea())
        .tint(Ink.accent)
        .preferredColorScheme(.light)
    }
}

/// RecordView 工具栏齿轮的导航目的地类型。
struct SettingsDestination: Hashable {}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, ShareLog.self, configurations: config)
    return MainTabView().modelContainer(container)
}
