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

    var body: some View {
        VStack(spacing: 0) {
            // 3 个 tab view 常驻,切换只改 opacity/hit-testing。
            // 不能用 `@ViewBuilder switch`:那会销毁未选中的 view,导致折叠状态、
            // 筛选、搜索、滚动位置一切归零(用户反馈:笔记折叠后换页自己又弹开)。
            ZStack {
                RecordView()
                    .opacity(selection == .record ? 1 : 0)
                    .allowsHitTesting(selection == .record)
                BrowseView(isActive: selection == .browse)
                    .opacity(selection == .browse ? 1 : 0)
                    .allowsHitTesting(selection == .browse)
                DiaryView(isActive: selection == .diary)
                    .opacity(selection == .diary ? 1 : 0)
                    .allowsHitTesting(selection == .diary)
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
/// 在原 HomeView.swift 里定义,Phase 9 删 HomeView 后搬到这里。
struct SettingsDestination: Hashable {}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, configurations: config)
    return MainTabView().modelContainer(container)
}
