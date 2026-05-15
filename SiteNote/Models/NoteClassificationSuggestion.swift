//
//  NoteClassificationSuggestion.swift
//  SiteNote
//
//  Note 分类建议的 JSON 数据结构。
//
//  定位:**非 SwiftData 值类型**,以 JSON 串形式存在 `Note.classificationJSON`。
//  好处:
//    - schema 演化不用走 SwiftData 迁移(加字段只改 Codable struct)。
//    - 用户 "全部确认" 后,这段建议全部落到 Note 真实字段,JSON 被清空——结构短命,不适合做 @Model。
//
//  每个字段都是 Optional `FieldSuggestion<T>`,nil 表示没有建议。
//

import Foundation

/// 建议来源。顶层 enum 避免 `FieldSuggestion<T>.Source` 因 T 不同变成不同类型。
enum SuggestionSource: String, Codable {
    case gps  // 规则:GPS 距离最近的已知工地
    case ai   // AI omni-classify 输出
}

/// 某个分类字段的建议值 + 元信息。
struct FieldSuggestion<T: Codable>: Codable {
    var value: T
    /// 0.0–1.0,越高越应该默认预填。
    var confidence: Double
    /// 中文短理由(≤20 字),给用户看"为什么 AI 这么猜"。
    var reasoning: String
    /// 这条建议的来源。UI 上 gps 用蓝色,AI 用强调色区分。
    var source: SuggestionSource
}

/// 对一条 Note 的综合分类建议。所有字段可空;只填 AI/规则判断出的项。
struct NoteClassificationSuggestion: Codable {
    /// 工地。GPS 或 AI 选。
    var site: FieldSuggestion<String>?
    /// 分类。AI 从已存在 subTag 列表里选 0–3 个。
    var subTags: FieldSuggestion<[String]>?
    /// Deadline 的 raw value(inbox/today/threeDays/thisWeek/archive)。
    /// 只在有**明确时间信号**时填,避免"赶紧/有空"这种模糊词误判。
    var deadline: FieldSuggestion<String>?
    /// 是否隐患。只在明确有安全问题时 true;false/null 不覆盖用户原值。
    var hazard: FieldSuggestion<Bool>?
    /// 合同条款引用。
    var clause: FieldSuggestion<String>?

    var isEmpty: Bool {
        site == nil && subTags == nil && deadline == nil
            && hazard == nil && clause == nil
    }

    /// 高置信度字段的数量(给 UI 判断"是否足以 prefill")。
    var highConfidenceCount: Int {
        var n = 0
        if let s = site, s.confidence >= 0.85 { n += 1 }
        if let s = subTags, s.confidence >= 0.85 { n += 1 }
        if let s = deadline, s.confidence >= 0.85 { n += 1 }
        if let s = hazard, s.confidence >= 0.85 { n += 1 }
        if let s = clause, s.confidence >= 0.85 { n += 1 }
        return n
    }
}
