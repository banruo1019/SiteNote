//
//  AppRouter.swift
//  SiteNote
//
//  全局路由信号:任何地方想"切到 X tab"或"让 LogTabView 切到 Y mode"时,
//  写 `AppRouter.shared.requestTab(...)` 即可。MainTabView 和 LogTabView
//  各自监听 pending 字段并消费一次后清空。
//
//  设计动机:HomeViewModel 在用户点"存日志"后想直接跳到「日志 → 台账」段,
//  让用户看到刚保存的条目。HomeViewModel 看不到 MainTabView 的 selection 绑定,
//  通过这个共享单例传信号最简单(不污染 view 层接口)。
//
//  消费一次即清:避免重复触发(如 view 重 render 时再次跳)。
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
        /// 仅当 tab == .log 时有意义。`nil` 保持 LogTabView 当前 mode 不变。
        let logMode: LogTabView.Mode?
    }

    /// 请求切到指定 tab。可选指定 LogTabView 的 mode(只在 .log 时生效)。
    func requestTab(_ tab: AppTab, logMode: LogTabView.Mode? = nil) {
        pendingTab = PendingTab(tab: tab, logMode: logMode)
    }

    /// 由 MainTabView/LogTabView 调,标记请求已被消费。
    func clear() {
        pendingTab = nil
    }
}
