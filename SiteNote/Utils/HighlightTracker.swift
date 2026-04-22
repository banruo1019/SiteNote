//
//  HighlightTracker.swift
//  SiteNote
//
//  跨 View 的"最近保存的 note ID"追踪器。单例 + @Observable,SwiftUI View
//  访问 `shared.highlightedNoteID` 会自动订阅变更。2 秒后自动清空。
//

import Foundation
import Observation

@MainActor
@Observable
final class HighlightTracker {
    static let shared = HighlightTracker()

    /// 最近一次保存的 note ID。非空时对应行应高亮。
    var highlightedNoteID: UUID?

    /// 标记一个 note 为"刚创建",2 秒后自动清空(除非被更新的 ID 覆盖)。
    func markJustAdded(_ id: UUID) {
        highlightedNoteID = id
        Task { [id] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.highlightedNoteID == id {
                self.highlightedNoteID = nil
            }
        }
    }

    private init() {}
}
