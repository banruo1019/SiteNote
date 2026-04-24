//
//  NoteClassificationPipeline.swift
//  SiteNote
//
//  Phase A(GPS 规则)+ Phase B(AI omni-classify)的集成管道。
//
//  职责:
//    1. `classify(note:)` — 跑两个 phase,把建议合成一个 `NoteClassificationSuggestion`,
//       编码成 JSON 写到 `note.classificationJSON`,**不动真实字段**。
//    2. `apply(suggestion:to:)` — 用户点"确认"后,把建议落到 Note 真实字段,
//       清 JSON,记录 GPS 学习(observe centroid)。
//
//  合并策略:
//    - site:AI 明说优先(confidence > 0.85) > GPS 规则。两者都没 → nil。
//    - 其他字段:只走 AI,没有规则。
//    - AI 失败但 Phase A 有结果 → 建议只有 site,仍然有用。
//

import Foundation
import SwiftData

@MainActor
enum NoteClassificationPipeline {

    /// 跑完 Phase A + B,把建议写到 `note.classificationJSON`(已有建议会被覆盖)。
    /// best-effort:AI 失败不抛错,只写 Phase A 的结果(或啥都不写)。
    static func classify(note: Note) async {
        var suggestion = NoteClassificationSuggestion()

        // ---------- Phase A: GPS → 最近工地 ----------
        if note.siteTag == nil,
           let lat = note.latitude,
           let lng = note.longitude,
           let nearest = SiteSuggestionService.nearestSite(latitude: lat, longitude: lng) {
            suggestion.site = FieldSuggestion(
                value: nearest.name,
                confidence: nearest.confidence,
                reasoning: "GPS 距 \(Int(nearest.distanceMeters))m",
                source: .gps
            )
        }

        // ---------- Phase B: AI omni-classify ----------
        let aiEnabled = UserDefaults.standard.object(forKey: "settings.aiOmniClassifyEnabled") as? Bool ?? true
        if aiEnabled {
            let sites = SiteTagsStorage.load()
            let subs = SubTagsStorage.load().map(\.name)
            let tpls = InspectionTemplatesStorage.load().map(\.name)
            let clauses = ClauseRefsStorage.load()

            if let ai = await AIService.shared.classifyNote(
                transcription: note.transcription,
                availableSites: sites,
                availableSubTags: subs,
                availableTemplates: tpls,
                availableClauses: clauses
            ) {
                mergeAI(ai, into: &suggestion, hasGPSHit: suggestion.site?.source == .gps)
            }
        }

        // ---------- 日志 note 裁剪 ----------
        // 施工日记只关心"哪个工地 + 属于哪类任务",不关心 deadline/隐患/模板/条款。
        // 把无关字段扔掉,避免建议卡上出现误导的 chips。
        if note.isDiaryRecord {
            suggestion.deadline = nil
            suggestion.hazard = nil
            suggestion.template = nil
            suggestion.clause = nil
        }

        // ---------- 写入 Note ----------
        if suggestion.isEmpty {
            note.classificationJSON = nil
            return
        }
        if let data = try? JSONEncoder().encode(suggestion),
           let json = String(data: data, encoding: .utf8) {
            note.classificationJSON = json
            note.classificationConfirmed = false
            print("[SiteNote] classify: \(describe(suggestion)) for \(note.id.uuidString.prefix(8))")
        }
    }

    /// 用户点"全部确认"时调。把 suggestion 的各字段**非覆盖式**地合并到 Note 真实字段上,
    /// 记录 GPS 学习,清 JSON。
    /// - Note: siteTag 和 isHazard 会覆盖(用户点确认就是表示同意);templateName/clauseRef 同理;
    ///         subTags 是去重合并,不清空已有。deadline 覆盖(因为本来就是单值字段)。
    static func apply(suggestion: NoteClassificationSuggestion, to note: Note) {
        if let s = suggestion.site {
            note.siteTag = s.value
            // 冷启动:AI 提议的新工地(不在 SiteTagsStorage 里)→ 用户点确认即视为加入。
            // 第二条 note 起,这个工地就出现在所有 site picker 里。
            let knownSites = SiteTagsStorage.load()
            if !knownSites.contains(s.value) {
                SiteTagsStorage.add(s.value)
                print("[SiteNote] Pipeline: AI 提议的新工地 \(s.value) 已自动加入 SiteTagsStorage")
            }
            // GPS 学习:用户确认后,把这条 note 的坐标喂给中心点。
            if let lat = note.latitude, let lng = note.longitude {
                SiteCentroidsStorage.observe(siteName: s.value, latitude: lat, longitude: lng)
            }
            // 同步所有关联 LogEntry 的 siteTag——否则 LogTabView 台账模式 / PDF 的工地过滤会把
            // 旧 siteTag=nil 的条目当"未分类"而漏掉,导致到场人数等统计不准。
            propagateSiteTag(s.value, toLogEntriesOf: note)
        }
        if let d = suggestion.deadline, let dl = Deadline(rawValue: d.value) {
            note.deadline = dl
            note.dueDate = dl.dueDate(from: note.createdAt)
            // 重排推送
            NotificationService.shared.cancel(for: note)
            NotificationService.shared.schedule(for: note)
        }
        if let tags = suggestion.subTags {
            var existing = Set(note.otherTags)
            for t in tags.value { existing.insert(t) }
            note.otherTags = Array(existing).sorted()
        }
        if let h = suggestion.hazard, h.value {
            note.isHazard = true
        }
        if let t = suggestion.template {
            note.templateName = t.value
        }
        if let c = suggestion.clause {
            note.contractClauseRef = c.value
        }
        note.classificationJSON = nil
        note.classificationConfirmed = true
    }

    /// 用户点"忽略"——不改任何真实字段,清 JSON,标已确认(之后不再提醒)。
    static func dismiss(note: Note) {
        note.classificationJSON = nil
        note.classificationConfirmed = true
    }

    /// Note 的 siteTag 变了,把关联 LogEntry 的 siteTag 一并同步。
    /// 通过 note 的 modelContext 查,避免全局 fetch。
    private static func propagateSiteTag(_ newTag: String, toLogEntriesOf note: Note) {
        guard let ctx = note.modelContext else { return }
        let noteID = note.id
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { $0.sourceNoteID == noteID }
        )
        let entries = (try? ctx.fetch(descriptor)) ?? []
        for e in entries where e.siteTag != newTag {
            e.siteTag = newTag
        }
        if !entries.isEmpty {
            print("[SiteNote] Pipeline: 同步 \(entries.count) 条 LogEntry 的 siteTag → \(newTag)")
        }
    }

    // MARK: - Merge 策略

    /// 把 AI 输出合并进已有 suggestion(Phase A 可能已经填了 site)。
    /// site 字段的规则:AI 高置信(≥0.85)覆盖 GPS;否则保留 GPS 结果。
    /// 其他字段没有规则对手,直接接收 AI 非 null 值。
    private static func mergeAI(
        _ ai: AIService.ClassificationAIOutput,
        into suggestion: inout NoteClassificationSuggestion,
        hasGPSHit: Bool
    ) {
        if let aiSite = ai.site, !aiSite.isEmpty {
            let aiConf = ai.confidences?["site"] ?? 0.7
            if !hasGPSHit || aiConf >= 0.85 {
                suggestion.site = FieldSuggestion(
                    value: aiSite,
                    confidence: aiConf,
                    reasoning: ai.reasoning?["site"] ?? "AI 建议",
                    source: .ai
                )
            }
        }

        if let tags = ai.subTags, !tags.isEmpty {
            suggestion.subTags = FieldSuggestion(
                value: tags,
                confidence: ai.confidences?["subTags"] ?? 0.7,
                reasoning: ai.reasoning?["subTags"] ?? "AI 建议",
                source: .ai
            )
        }

        if let d = ai.deadline, !d.isEmpty,
           Deadline(rawValue: d) != nil {
            suggestion.deadline = FieldSuggestion(
                value: d,
                confidence: ai.confidences?["deadline"] ?? 0.7,
                reasoning: ai.reasoning?["deadline"] ?? "AI 建议",
                source: .ai
            )
        }

        if let h = ai.isHazard, h == true {
            suggestion.hazard = FieldSuggestion(
                value: true,
                confidence: ai.confidences?["hazard"] ?? 0.7,
                reasoning: ai.reasoning?["hazard"] ?? "AI 判定隐患",
                source: .ai
            )
        }

        if let t = ai.templateName, !t.isEmpty {
            suggestion.template = FieldSuggestion(
                value: t,
                confidence: ai.confidences?["templateName"] ?? 0.7,
                reasoning: ai.reasoning?["templateName"] ?? "AI 建议",
                source: .ai
            )
        }

        if let c = ai.clauseRef, !c.isEmpty {
            suggestion.clause = FieldSuggestion(
                value: c,
                confidence: ai.confidences?["clauseRef"] ?? 0.7,
                reasoning: ai.reasoning?["clauseRef"] ?? "AI 建议",
                source: .ai
            )
        }
    }

    /// 调试输出。
    private static func describe(_ s: NoteClassificationSuggestion) -> String {
        var parts: [String] = []
        if let x = s.site { parts.append("site=\(x.value)(\(Int(x.confidence * 100))%)") }
        if let x = s.deadline { parts.append("deadline=\(x.value)") }
        if let x = s.subTags { parts.append("tags=\(x.value.joined(separator: ","))") }
        if let x = s.hazard, x.value { parts.append("hazard") }
        if let x = s.template { parts.append("tpl=\(x.value)") }
        if let x = s.clause { parts.append("clause=\(x.value)") }
        return parts.joined(separator: " · ")
    }
}
