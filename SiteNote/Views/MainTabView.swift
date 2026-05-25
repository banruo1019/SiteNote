//
//  MainTabView.swift
//  SiteNote
//
//  v1.3:统一 3 Tab —— 记 / 日历 / 报告。
//  PM 和 Engineer 用同一 RecordView / 同一 SettingsView(齿轮入口)。
//  日历和报告内容根据角色差异化:
//   - PM 日历 = Note.dueDate 视图
//   - Engineer 日历 = SiteVisitSchedule + InspectionReport 视图
//   - PM 报告 = 直接跳 PDFExportView
//   - Engineer 报告 = 走 PDFHubView 选 SVR 或 PDF 巡检日志
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selection: AppTab = MainTabView.initialTabFromLaunchArg()
    @State private var showsOnboarding: Bool = OnboardingView.needsToShow
    @State private var router = AppRouter.shared
    @State private var profileManager = UserProfileManager.shared

    /// 截图用 — `-StartTab record|calendar|reports` 决定 app 启动停留在哪个 tab。
    private static func initialTabFromLaunchArg() -> AppTab {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-StartTab"), i + 1 < args.count {
            switch args[i + 1] {
            case "calendar": return .calendar
            case "reports": return .reports
            default: return .record
            }
        }
        return .record
    }

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
            guard let request else { return }
            selection = request.tab
            router.clear()
        }
        // v1.6 (en-v1):切 tab 时所有 tab 的 NavigationStack 弹回 root。
        // 用户预期"离开 Log tab 进 Calendar 再回来 → Log 应该回到根,不是停留在 Settings"。
        .onChange(of: selection) { old, new in
            if old != new {
                router.popAllToRoot()
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            ZStack {
                // v1.6 (en-v1):每个 tab view 用 .id(router.popAllTrigger) 钉 —
                // tab 切换时 trigger 自增 → SwiftUI 重建 view tree → NavigationStack
                // + @State 全部回 root,实现"离开 tab 就重置"的预期。
                RecordView()
                    .id(router.popAllTrigger)
                    .opacity(selection == .record ? 1 : 0)
                    .allowsHitTesting(selection == .record)

                // 日历:角色决定走 PM 还是 Engineer 实现。
                Group {
                    if isEngineer {
                        EngineerScheduleView()
                    } else {
                        PMCalendarView()
                    }
                }
                .id(router.popAllTrigger)
                .opacity(selection == .calendar ? 1 : 0)
                .allowsHitTesting(selection == .calendar)

                // 报告:角色决定走 PM 还是 Engineer 实现。
                Group {
                    if isEngineer {
                        EngineerReportsView()
                    } else {
                        ReportsView()
                    }
                }
                .id(router.popAllTrigger)
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

/// RecordView / ReportsView / PMCalendarView / EngineerScheduleView 工具栏齿轮的
/// 导航目的地类型 —— 任何 view 加 navigationDestination(for: SettingsDestination)
/// 就能用同一个 SettingsView 入口。
struct SettingsDestination: Hashable {}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, ShareLog.self, configurations: config)
    return MainTabView().modelContainer(container)
}
