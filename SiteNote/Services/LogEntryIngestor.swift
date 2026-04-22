//
//  LogEntryIngestor.swift
//  SiteNote
//
//  把 AIService 抽出的 `LogEntryDraft` 落成 SwiftData 的 `LogEntry`。
//  承担两件事:
//    1. 字段对齐(draft.action 不是 LogEntry 字段,需要翻译成 startAt/endAt/isAbsent 组合)。
//    2. **机械 session 匹配**:一条 "挖机走" 要找"最近未闭合的挖机 session"去关闭,
//       不是建新条目。匹配失败则建一条"孤儿 leave"(standalone 事件)让用户看到。
//

import Foundation
import SwiftData

@MainActor
enum LogEntryIngestor {

    /// 把若干 draft 落库。所有 draft 都关联到同一个源 Note。
    ///
    /// 副作用:向 `ctx` 插入新 LogEntry,或修改已存在的 open plant session(填 endAt)。
    /// **如果最终成功处理了 ≥1 条 draft,会把源 note 标为 `isDiaryRecord = true`**——
    /// 它就从"提醒事项"里退出去,归到施工日记类。
    /// 不 save context——由调用方决定 save 时机(通常 SwiftData 自动保存)。
    static func ingest(drafts: [AIService.LogEntryDraft], from note: Note, into ctx: ModelContext) {
        guard !drafts.isEmpty else { return }

        let isoParser = ISO8601DateFormatter()
        isoParser.formatOptions = [.withInternetDateTime]

        var processed = 0
        for draft in drafts {
            guard let kind = LogKind(rawValue: draft.kind) else {
                print("[SiteNote] LogEntryIngestor: 未知 kind \(draft.kind),跳过")
                continue
            }
            // 时间处理:AI 给了 ISO → 用它,`startAtExplicit=true`
            //         AI 给 null → 兜底 note.createdAt,`startAtExplicit=false`(UI 画"—")
            let parsedTime = draft.time.flatMap { isoParser.date(from: $0) }
            let time = parsedTime ?? note.createdAt
            let timeExplicit = parsedTime != nil
            let siteTag = note.siteTag

            switch draft.action {
            case "arrive":
                ingestArrive(
                    kind: kind, draft: draft, time: time, timeExplicit: timeExplicit,
                    siteTag: siteTag, note: note, ctx: ctx
                )
                processed += 1
            case "leave":
                ingestLeave(
                    kind: kind, draft: draft, time: time, timeExplicit: timeExplicit,
                    siteTag: siteTag, note: note, ctx: ctx
                )
                processed += 1
            case "absent":
                ingestAbsent(
                    draft: draft, time: time, timeExplicit: timeExplicit,
                    siteTag: siteTag, note: note, ctx: ctx
                )
                processed += 1
            case "event":
                ingestEvent(
                    kind: kind, draft: draft, time: time, timeExplicit: timeExplicit,
                    siteTag: siteTag, note: note, ctx: ctx
                )
                processed += 1
            default:
                print("[SiteNote] LogEntryIngestor: 未知 action \(draft.action),跳过")
            }
        }

        // 只要有条目成功处理,这条 Note 就归为"施工日记"——从提醒事项退出。
        if processed > 0 {
            note.isDiaryRecord = true
            print("[SiteNote] LogEntryIngestor: note \(note.id.uuidString.prefix(8)) 标记为施工日记(\(processed) 条)")
        }
    }

    // MARK: - Arrive:单点事件(person/delivery/visitor)或开 plant session

    private static func ingestArrive(
        kind: LogKind,
        draft: AIService.LogEntryDraft,
        time: Date,
        timeExplicit: Bool,
        siteTag: String?,
        note: Note,
        ctx: ModelContext
    ) {
        let entry = LogEntry(
            kind: kind,
            subject: draft.subject,
            quantity: kind == .person ? draft.quantity : nil,
            startAt: time,
            startAtExplicit: timeExplicit,
            endAt: nil,                     // plant: 开 session;其他 kind: 单点
            isAbsent: false,
            note: draft.note,
            siteTag: siteTag,
            sourceNoteID: note.id,
            confidence: draft.confidence
        )
        ctx.insert(entry)
    }

    // MARK: - Leave:关闭最近未闭合的 plant session,找不到就建孤儿条目

    private static func ingestLeave(
        kind: LogKind,
        draft: AIService.LogEntryDraft,
        time: Date,
        timeExplicit: Bool,
        siteTag: String?,
        note: Note,
        ctx: ModelContext
    ) {
        // 只 plant 支持 leave。person 的 "走" 没意义(工种是一次性到场标记)。
        guard kind == .plant else {
            print("[SiteNote] LogEntryIngestor: 非 plant 的 leave action(\(draft.subject)),忽略")
            return
        }

        if let open = findOpenPlantSession(subject: draft.subject, siteTag: siteTag, ctx: ctx) {
            open.endAt = time
            if open.note == nil, let extra = draft.note { open.note = extra }
            // 保留源 Note 为"开 session 时那条",但 confidence 按两者平均拉高一点
            open.confidence = min(1.0, max(open.confidence, draft.confidence))
            print("[SiteNote] LogEntryIngestor: 关闭 \(draft.subject) session → duration \(Int((open.duration ?? 0)/60)) min")
        } else {
            // 没找到对应开场:建一条标记条目,让用户注意
            let orphan = LogEntry(
                kind: .plant,
                subject: draft.subject,
                startAt: time,
                startAtExplicit: timeExplicit,
                endAt: time,                // 闭合的单点,duration=0
                isAbsent: false,
                note: "⚠️ 无对应到场记录" + (draft.note.map { " · \($0)" } ?? ""),
                siteTag: siteTag,
                sourceNoteID: note.id,
                confidence: draft.confidence * 0.5
            )
            ctx.insert(orphan)
            print("[SiteNote] LogEntryIngestor: \(draft.subject) leave 找不到开场 session,建孤儿")
        }
    }

    // MARK: - Absent:person 的缺席

    private static func ingestAbsent(
        draft: AIService.LogEntryDraft,
        time: Date,
        timeExplicit: Bool,
        siteTag: String?,
        note: Note,
        ctx: ModelContext
    ) {
        let entry = LogEntry(
            kind: .person,                  // 缺席只对人员有意义
            subject: draft.subject,
            quantity: draft.quantity,
            startAt: time,
            startAtExplicit: timeExplicit,
            endAt: nil,
            isAbsent: true,
            note: draft.note,
            siteTag: siteTag,
            sourceNoteID: note.id,
            confidence: draft.confidence
        )
        ctx.insert(entry)
    }

    // MARK: - Event:停电/暴雨/验收等单点

    private static func ingestEvent(
        kind: LogKind,
        draft: AIService.LogEntryDraft,
        time: Date,
        timeExplicit: Bool,
        siteTag: String?,
        note: Note,
        ctx: ModelContext
    ) {
        let entry = LogEntry(
            kind: kind == .event ? .event : kind,   // 通常 kind 已经是 event
            subject: draft.subject,
            quantity: nil,
            startAt: time,
            startAtExplicit: timeExplicit,
            endAt: nil,
            isAbsent: false,
            note: draft.note,
            siteTag: siteTag,
            sourceNoteID: note.id,
            confidence: draft.confidence
        )
        ctx.insert(entry)
    }

    // MARK: - Session 匹配

    /// 查找匹配的"未闭合 plant session":同 subject + 同 siteTag + endAt==nil + deletedAt==nil,
    /// 按 startAt 倒序取第一条(最近的)。
    ///
    /// 注意:SwiftData #Predicate 对 Optional 等值比较(尤其 nil siteTag)支持不稳,
    /// 所以先 predicate 过滤基础条件,再 in-memory 过滤 siteTag。LogEntry 数量有限,开销可以忽略。
    private static func findOpenPlantSession(
        subject: String,
        siteTag: String?,
        ctx: ModelContext
    ) -> LogEntry? {
        let plantRaw = LogKind.plant.rawValue
        let targetSubject = subject

        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { e in
                e.kindRaw == plantRaw
                    && e.subject == targetSubject
                    && e.endAt == nil
                    && e.deletedAt == nil
            },
            sortBy: [SortDescriptor(\LogEntry.startAt, order: .reverse)]
        )
        let candidates = (try? ctx.fetch(descriptor)) ?? []
        return candidates.first { $0.siteTag == siteTag }
    }
}
