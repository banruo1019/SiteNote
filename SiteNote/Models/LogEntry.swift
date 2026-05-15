//
//  LogEntry.swift
//  SiteNote
//
//  工地日志结构化条目(Daily Site Diary / Labour & Plant Log)。
//
//  定位:**Note 的 AI 派生数据**。
//  - Note(保持不动)存原始语音 + transcription + 照片等。
//  - AI 在保存 Note 之后异步抽取"水工×4 / 挖机到 / 监理巡检"等结构化信息 → 落成 LogEntry。
//  - 永远通过 `sourceNoteID` 反向引用源 Note,方便用户在 Note 详情里改正抽取错误。
//
//  为什么不用 @Relationship:
//  - SwiftData 的 cascading 删除会把 LogEntry 连带干掉,而我们想让 LogEntry 在源 Note 软删后
//    仍保留(日志法律证据属性)。用裸 UUID 反向引用,删除策略自己控。
//

import Foundation
import SwiftData

/// 日志条目类型。中文语义:"到场的**是什么**"。
enum LogKind: String, Codable, CaseIterable {
    /// 工种/班组/人员到场(如 水工、电工、钢筋班)。用 `quantity` 表达人数。
    case person
    /// 机械/设备进出场(如 挖机、混凝土泵)。用 `startAt` / `endAt` 表达 session。
    case plant
    /// 材料/物资送达(如 钢筋送达、商混到场)。单点事件。
    case delivery
    /// 访客/监理/业主巡视。单点事件。
    case visitor
    /// 其他事件(停电、暴雨、验收、事故)。单点事件。
    case event

    var displayName: String {
        switch self {
        case .person: return String(localized: "人员", locale: AppLanguageManager.currentLocale)
        case .plant: return String(localized: "机械", locale: AppLanguageManager.currentLocale)
        case .delivery: return String(localized: "送达", locale: AppLanguageManager.currentLocale)
        case .visitor: return String(localized: "访客", locale: AppLanguageManager.currentLocale)
        case .event: return String(localized: "事件", locale: AppLanguageManager.currentLocale)
        }
    }
}

/// 一条结构化日志条目。由 AI 从 Note.transcription 抽取,用户可确认/修改。
@Model
final class LogEntry {
    /// 稳定唯一标识。
    var id: UUID

    /// `LogKind` 的原始字符串值。和 Note.deadlineRaw 一样,SwiftData 存 String 比存自定义枚举稳。
    /// 通过 `kind` 计算属性读写。
    var kindRaw: String

    /// 主语:工种名 / 设备名 / 送达物 / 访客身份 / 事件名。AI 抽取的短词。
    var subject: String

    /// 数量,只 `.person` 用(水工×4)。其他 kind 恒 nil。
    var quantity: Int?

    /// 事件开始时间。单点事件(.delivery / .visitor / .event / 缺席的 .person)即为事件时间。
    /// **即使用户没说时间,这里也填 `note.createdAt` 作兜底**——保证排序和日期过滤不崩。
    /// UI 是否显示由 `startAtExplicit` 决定:false 时 UI 画"—"而不是这个兜底时间。
    var startAt: Date

    /// 用户/AI 是否**明确给出**了开始时间。
    /// - true: 语音明说("7 点半到"、"现在"),UI 和 PDF 都显示 `startAt` 的具体时间。
    /// - false: 没说,`startAt` 是 note.createdAt 兜底,UI 和 PDF 显示"—"。
    var startAtExplicit: Bool = false

    /// 结束时间。只 `.plant` 的已闭合 session 有值;其他恒 nil。
    /// `kind == .plant && endAt == nil` 表示"开着的机械 session",日终需要提醒用户关闭。
    var endAt: Date?

    /// 是否缺席(只 .person 用)。true 时 `quantity` 可能为 nil,`note` 存原因。
    var isAbsent: Bool = false

    /// 附加说明。AI 抽取的上下文("缺席,原因:下雨"、"钢筋规格 HRB400")。
    var note: String?

    /// 所属工地(从源 Note 继承或 AI 识别)。
    var siteTag: String?

    /// 反向引用源 Note 的 id。必填——所有 LogEntry 都是某条 Note 的派生物,永远可追溯。
    /// 不用 @Relationship:保留 Note 软删后 LogEntry 仍留存的能力(证据链)。
    var sourceNoteID: UUID

    /// AI 抽取时的置信度 0–1。< 0.7 在 UI 上要标灰/加 ⚠,强制用户看一眼再确认。
    var confidence: Double = 1.0

    /// 用户是否点过"确认"。用于 UI 区分 AI 草稿 vs 已确认。
    var userConfirmed: Bool = false

    /// 创建(落库)时间。
    var createdAt: Date

    /// 软删时间戳。和 Note 一致:nil 表示"活着",非空表示在垃圾桶里。
    /// 主查询过滤 deletedAt == nil。
    var deletedAt: Date?

    // MARK: - Derived

    var kind: LogKind {
        get { LogKind(rawValue: kindRaw) ?? .event }
        set { kindRaw = newValue.rawValue }
    }

    /// 是否为"开着的机械 session"(需要后续关闭)。
    var isOpenPlantSession: Bool {
        kind == .plant && endAt == nil && deletedAt == nil
    }

    /// 机械 session 的时长(已闭合的)。person/event/delivery/visitor 返回 nil。
    var duration: TimeInterval? {
        guard kind == .plant, let end = endAt else { return nil }
        return end.timeIntervalSince(startAt)
    }

    // MARK: - Init

    init(
        kind: LogKind,
        subject: String,
        quantity: Int? = nil,
        startAt: Date = Date(),
        startAtExplicit: Bool = false,
        endAt: Date? = nil,
        isAbsent: Bool = false,
        note: String? = nil,
        siteTag: String? = nil,
        sourceNoteID: UUID,
        confidence: Double = 1.0,
        userConfirmed: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.subject = subject
        self.quantity = quantity
        self.startAt = startAt
        self.startAtExplicit = startAtExplicit
        self.endAt = endAt
        self.isAbsent = isAbsent
        self.note = note
        self.siteTag = siteTag
        self.sourceNoteID = sourceNoteID
        self.confidence = confidence
        self.userConfirmed = userConfirmed
        self.createdAt = createdAt
    }
}
