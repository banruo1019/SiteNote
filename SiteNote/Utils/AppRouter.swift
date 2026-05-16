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
}
