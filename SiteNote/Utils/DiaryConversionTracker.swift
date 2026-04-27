//
//  DiaryConversionTracker.swift
//  SiteNote
//
//  跨 Tab 单例,@Observable。LogEntryIngestor 抽出 ≥1 条 LogEntry 后调
//  `recordPendingConversion(noteID:entriesCount:)`,UI 层(RecordView 顶部 banner)读
//  `current` 显示 "AI 抽到 N 条 · [标为施工日志] [保留提醒]" 浮窗。
//
//  **不再自动清掉**:静默丢提醒是产品红线(project_ai_strategy.md)。
//  banner 显示直到用户点确认或忽略。
//
//  **队列**:同一时间多条 note 都被 AI 抽中时,按 FIFO 排队。banner 显示队首,
//  用户处理完队首才弹出第二条——避免后来者覆盖前一条导致用户漏掉的问题。
//

import Foundation
import Observation

@Observable
final class DiaryConversionTracker {
    static let shared = DiaryConversionTracker()

    /// 待用户处理的转换建议队列。FIFO。UI 只显示 `current` 即队首。
    var queue: [PendingConversion] = []

    /// 当前展示的建议(队首),nil 时不显示 banner。
    var current: PendingConversion? { queue.first }

    private init() {}

    /// LogEntryIngestor 抽出 ≥1 条 draft 后调。
    /// 同一 noteID 已在队列里则忽略(防同条 note 反复 polish 时重复入队)。
    @MainActor
    func recordPendingConversion(noteID: UUID, entriesCount: Int) {
        if queue.contains(where: { $0.noteID == noteID }) { return }
        queue.append(PendingConversion(noteID: noteID, entriesCount: entriesCount, shownAt: Date()))
    }

    /// 用户点了"标为施工日志"或"保留提醒"任一按钮后调,弹出队首。
    /// 具体写库(isDiaryRecord/deadline/cancel)在调用方做,这里只管队列状态。
    @MainActor
    func dismissCurrent() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
    }

    struct PendingConversion: Hashable {
        let noteID: UUID
        let entriesCount: Int
        let shownAt: Date
    }
}
