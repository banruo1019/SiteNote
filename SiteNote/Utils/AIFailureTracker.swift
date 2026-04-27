//
//  AIFailureTracker.swift
//  SiteNote
//
//  跨 Tab 单例,@Observable。AI 链(polish / classify / extract)失败时记一笔,
//  AIStatusBar 据此把状态条变红显示"AI 失败 · 检查设置",直到 10 分钟超时或手动清。
//
//  动机:之前 HomeViewModel 里 AI 失败只 print log,用户完全感知不到。
//  当 OpenAI Key 失效 / 配额用完 / 网络挂了 / Apple Intelligence 不可用时,
//  用户会以为是自己说得不清楚,反复重录,白白消耗时间。
//

import Foundation
import Observation

@Observable
final class AIFailureTracker {
    static let shared = AIFailureTracker()

    /// 最近一次失败的时间和简短原因。> 10 分钟前的失败视为过期,UI 不再显示。
    var lastFailure: Failure?

    private init() {}

    /// AIService 包装层 / HomeViewModel 的 catch 块调。reason 要短(< 30 字),
    /// 因为会显示在窄状态条上。
    @MainActor
    func record(reason: String) {
        lastFailure = Failure(at: Date(), reason: reason)
    }

    /// 用户进 AI 设置页或主动触发新的 AI 调用成功后调,清掉警告。
    @MainActor
    func clear() {
        lastFailure = nil
    }

    /// UI 用:失败是否仍"新鲜"(默认 10 分钟内)。
    var hasRecentFailure: Bool {
        guard let f = lastFailure else { return false }
        return Date().timeIntervalSince(f.at) < 600
    }

    struct Failure: Hashable {
        let at: Date
        let reason: String
    }
}
