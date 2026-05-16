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
    /// **不会** 自动改 `note.isDiaryRecord` 也 **不会** 取消推送——LLM 误判 → 静默丢提醒
    /// 是产品红线(参见 project_ai_strategy.md "绝不静默自动应用")。
    /// 仅向 `DiaryConversionTracker` 登记一条 *pending* 建议,由 banner 让用户确认。
    /// 不 save context——由调用方决定 save 时机(通常 SwiftData 自动保存)。
    ///
    /// **Profile defense-in-depth**:即使 AI 没遵守 prompt,这里也按 profile 丢掉越界 kind:
    ///   - engineer:丢 person/plant(只允许问题类)
    ///   - pm:不过滤
    static func ingest(drafts: [AIService.LogEntryDraft], from note: Note, into ctx: ModelContext) {
        guard !drafts.isEmpty else { return }

        let isoParser = ISO8601DateFormatter()
        isoParser.formatOptions = [.withInternetDateTime]

        let profile = UserProfileManager.shared.current

        var processed = 0
        for draft in drafts {
            guard let kind = LogKind(rawValue: draft.kind) else {
                print("[SiteNote] LogEntryIngestor: 未知 kind \(draft.kind),跳过")
                continue
            }
            // Profile 兜底过滤:AI 偶尔会越界,这里再保险一次。
            if !isKindAllowed(kind, for: profile) {
                print("[SiteNote] LogEntryIngestor: profile=\(profile.rawValue) 不允许 kind=\(draft.kind),跳过 \(draft.subject)")
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

        // E2.14:siteTag 一致性 propagate。
        // 同一 sourceNoteID 的所有未删除 LogEntry 都同步到当前 note.siteTag,
        // 防止 ingest 早期取了过时的 siteTag(用户在 AI 处理途中改了 note 的工地标签)
        // 或老条目还残留旧 siteTag。代价小:LogEntry 量级有限。
        let noteID = note.id
        let currentSiteTag = note.siteTag
        let propagateDescriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { e in
                e.sourceNoteID == noteID && e.deletedAt == nil
            }
        )
        if let related = try? ctx.fetch(propagateDescriptor) {
            for entry in related where entry.siteTag != currentSiteTag {
                entry.siteTag = currentSiteTag
            }
        }

        // 仅登记一条 *pending* 建议——不动 isDiaryRecord、不 cancel 推送。
        // 用户在 banner 点"标为施工日志"才把 note 翻成日记 + 取消推送。
        // 设计依据:LLM 误判时静默丢提醒会让用户信任崩塌(project_ai_strategy.md 红线)。
        if processed > 0 {
            let id = note.id
            let count = processed
            Task { @MainActor in
                DiaryConversionTracker.shared.recordPendingConversion(noteID: id, entriesCount: count)
            }
            print("[SiteNote] LogEntryIngestor: note \(note.id.uuidString.prefix(8)) 抽出 \(count) 条建议(待用户确认)")
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

        if let open = findOpenPlantSession(subject: draft.subject, siteTag: siteTag, sourceNoteID: note.id, ctx: ctx) {
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
                note: String(localized: "⚠️ 无对应到场记录", locale: AppLanguageManager.currentLocale) + (draft.note.map { " · \($0)" } ?? ""),
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

    // MARK: - Profile 越界 kind 过滤

    /// 按 profile 决定哪些 LogKind 允许写入。AI prompt 已经按 profile 调优,
    /// 这里再做一次 defense-in-depth——AI 偶发越界也不会让用户看到不该看到的条目。
    private static func isKindAllowed(_ kind: LogKind, for profile: ProfileKind) -> Bool {
        switch profile {
        case .pm:
            return true
        case .engineer:
            // 工程师看:问题(event)+ 业主/监理/质监站到场(visitor)。
            // person/plant/delivery 不属于巡检视角。
            return kind == .event || kind == .visitor
        }
    }

    // MARK: - Session 匹配

    /// 查找匹配的"未闭合 plant session":同 subject + 同 siteTag + endAt==nil + deletedAt==nil,
    /// 按 startAt 倒序取第一条(最近的)。
    ///
    /// 跨工地约束(E2.13):
    /// - 只在 startAt > now - 24h 的窗口内匹配。超过 24h 还没关的 session 视为孤儿,新条目应该开新 session,
    ///   而不是跨日合并(用户明天上午报"挖机走"不应该关掉昨天遗留的 open session)。
    /// - siteTag 双方都为 nil 时,**收紧到只匹配同 sourceNoteID** 的 entry——避免不同 note 没填 siteTag
    ///   各自开 dingo 时被错误合并。两条 nil siteTag 的 entry 不能假设是同一个 session。
    ///
    /// 注意:SwiftData #Predicate 对 Optional 等值比较(尤其 nil siteTag)支持不稳,
    /// 所以先 predicate 过滤基础条件,再 in-memory 过滤。LogEntry 数量有限,开销可以忽略。
    private static func findOpenPlantSession(
        subject: String,
        siteTag: String?,
        sourceNoteID: UUID,
        ctx: ModelContext
    ) -> LogEntry? {
        let plantRaw = LogKind.plant.rawValue
        let targetSubject = subject
        let cutoff = Date().addingTimeInterval(-24 * 3600)

        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { e in
                e.kindRaw == plantRaw
                    && e.subject == targetSubject
                    && e.endAt == nil
                    && e.deletedAt == nil
                    && e.startAt > cutoff
            },
            sortBy: [SortDescriptor(\LogEntry.startAt, order: .reverse)]
        )
        let candidates = (try? ctx.fetch(descriptor)) ?? []
        return candidates.first { entry in
            // siteTag 都有值:必须相等
            // siteTag 一边有一边没有:不匹配
            // siteTag 两边都为 nil:只匹配同 sourceNoteID(避免跨 note 错误合并)
            switch (entry.siteTag, siteTag) {
            case let (a?, b?):
                return a == b
            case (nil, nil):
                return entry.sourceNoteID == sourceNoteID
            default:
                return false
            }
        }
    }
}
