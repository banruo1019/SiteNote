//
//  SwiftDataStack.swift
//  SiteNote
//
//  全局 ModelContainer / ModelContext 访问点。
//
//  设计:大多数 UserDefaults-style storage facade(SitePresetStorage / SiteTagsStorage 等)
//  在 v1.6+ 升级到 SwiftData 后,需要全局 access ModelContext。Caller 大多在
//  SwiftUI view body 里(MainActor)同步访问,改成 caller-传 modelContext 会
//  炸 25+ callers。这里用一个 @MainActor singleton 暴露 mainContext。
//
//  生命周期:SiteNoteApp 拿到 ModelContainer.ready 后立即 `register(_:)`;
//  在那之前调任何 storage facade 会拿到 nil,facade 返回空 / 日志 warning。
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataStack {
    static let shared = SwiftDataStack()
    private init() {}

    private(set) var container: ModelContainer?

    /// SiteNoteApp 在 .ready 状态时调一次。
    func register(_ container: ModelContainer) {
        self.container = container
    }

    /// 给 facade 用的主上下文。register 之前 nil。
    var mainContext: ModelContext? {
        container?.mainContext
    }
}
