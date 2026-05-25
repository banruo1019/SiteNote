//
//  AppRouter.swift
//  SiteNote
//
//  全局路由信号:任何地方想"切到 X tab"时,
//  写 `AppRouter.shared.requestTab(...)` 即可。MainTabView 监听 pending 字段并消费一次后清空。
//
//  消费一次即清:避免重复触发(如 view 重 render 时再次跳)。
//
//  v1.2 大减负后简化:删 logMode 参数(LogTab 已下架)。
//

import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    /// 待处理的 tab 切换请求。MainTabView 监听 → 消费 → 置 nil。
    var pendingTab: PendingTab?

    /// v1.6 (en-v1):tab 切换时各 view 的 NavigationStack 应弹回 root。
    /// MainTabView 在 selection change 时 bump 这个 counter;
    /// 每个 tab 的根 view(RecordView / PMCalendarView / ReportsView 等)
    /// 监听这个值,变化时 navPath = NavigationPath()。
    /// 用 Int 而不是 Bool 避免"已经是 true 就不触发 onChange"的坑。
    var popAllTrigger: Int = 0

    private init() {}

    struct PendingTab: Equatable {
        let tab: AppTab
    }

    /// 请求切到指定 tab。
    func requestTab(_ tab: AppTab) {
        pendingTab = PendingTab(tab: tab)
    }

    /// 由 MainTabView 调,标记请求已被消费。
    func clear() {
        pendingTab = nil
    }

    /// MainTabView selection change 时调 — 通知所有 tab 弹回 root。
    func popAllToRoot() {
        popAllTrigger &+= 1  // 溢出回卷,只用来变化通知
    }
}
