//
//  MainTabView.swift
//  SiteNote
//
//  3 个主 Tab 的根视图(M1 Linear 极简白)。
//  自定义 TabBar 替代系统 TabView,文字双行(中文 + English),
//  激活指示靠字重+颜色,无背景填充、无下划线、无顶边。
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selection: AppTab = .record
    @State private var showsOnboarding: Bool = OnboardingView.needsToShow
    @State private var router = AppRouter.shared
    /// 角色管理。Engineer 模式下隐藏 LogTab —— 工程师主流程是
    /// 「主屏速记 + 报告 Tab 做巡检」,日志台账只是 PM 视角需要的。
    @State private var profileManager = UserProfileManager.shared

    /// 当前角色下 LogTab 是否可见。Engineer 角色不显示日志。
    private var isLogTabVisible: Bool {
        profileManager.current != .engineer
    }

    /// Engineer 角色:走独立的 4 Tab 软件(记/报告/日程/设置)。
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
            // 消费 AppRouter 信号:别处(HomeViewModel.convertLastSaveToDiary 等)请求切 tab 时切。
            // logMode 由 LogTabView 自己再监听一次消费,这里只负责切顶层 tab。
            guard let request else { return }
            // Engineer 模式下 .log Tab 不存在 —— 把任何切到 .log 的请求 fallback 到 .reports
            // (例如 Profile 切换 banner 上"打开日志"按钮,在 Engineer 模式按下时跳报告)。
            let target: AppTab = (request.tab == .log && !isLogTabVisible) ? .reports : request.tab
            selection = target
            // 如果请求里没带 logMode 或不是切到 .log,直接清掉信号。
            // 切到 .log 且带 logMode 的,留给 LogTabView 消费完再清。
            // 被 fallback 到 .reports 的请求,这里直接清,不留给 LogTabView。
            if target != .log || request.logMode == nil {
                router.clear()
            }
        }
        .onChange(of: profileManager.current) { _, _ in
            // 切到 Engineer 时如果当前停在 PM 才有的 tab(.log),防御性切回 .record。
            // 切离 Engineer 时如果停在 Engineer 才有的 tab(.schedule / .settings),也切回 .record。
            if isEngineer && (selection == .log) {
                selection = .record
            } else if !isEngineer && (selection == .schedule || selection == .settings) {
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
    // Engineer 完全独立 UI:不渲染 PM 的 RecordView / LogTabView / ReportsView,
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

    // MARK: - PM 原 3 Tab 路由(保持不变)
    private var pmContent: some View {
        VStack(spacing: 0) {
            // tab view 常驻,切换只改 opacity/hit-testing。
            // 不能用 `@ViewBuilder switch`:那会销毁未选中的 view,导致折叠状态、
            // 筛选、搜索、滚动位置一切归零(用户反馈:速记折叠后换页自己又弹开)。
            ZStack {
                RecordView()
                    .opacity(selection == .record ? 1 : 0)
                    .allowsHitTesting(selection == .record)
                LogTabView(isActive: selection == .log)
                    .opacity(selection == .log ? 1 : 0)
                    .allowsHitTesting(selection == .log)
                ReportsView()
                    .opacity(selection == .reports ? 1 : 0)
                    .allowsHitTesting(selection == .reports)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            IndustrialTabBar(selection: $selection, hidesLog: !isLogTabVisible)
        }
        .background(Ink.bg.ignoresSafeArea())
        .tint(Ink.accent)
        .preferredColorScheme(.light)
    }
}

/// RecordView 工具栏齿轮的导航目的地类型。
/// 在原 HomeView.swift 里定义,Phase 9 删 HomeView 后搬到这里。
struct SettingsDestination: Hashable {}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, ShareLog.self, configurations: config)
    return MainTabView().modelContainer(container)
}
