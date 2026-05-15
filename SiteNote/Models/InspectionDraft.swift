//
//  InspectionReport.swift  (file kept as InspectionDraft.swift for Xcode index continuity)
//  SiteNote
//
//  Engineer Profile 专属:**聚合**一组 Note 成为一份巡检报告。
//
//  设计要点(v1.2 重构后):
//  - Note 是一等公民(用户在"记"界面录),包含 transcription + photoPaths + floorPlanRef/X/Y。
//  - InspectionReport 不重复存照片,只**引用** Note IDs 并存:Header 字段 + 主照来源 + caption override。
//  - PDF 导出时 fetch [Note],从 Note.photoPaths 拿图,从 Note.floorPlanRef 画图钉。
//  - 工程师"做完巡检"= 在「报告」Tab 点"新建报告" → 选当天同工地的 Note → 调整 caption → 出 PDF。
//

import Foundation
import SwiftData

@Model
final class InspectionReport {
    /// 稳定唯一标识。
    var id: UUID = UUID()

    /// 创建时间。
    var createdAt: Date = Date()

    /// 最后修改时间。
    var updatedAt: Date = Date()

    // MARK: - Header 字段

    var project: String = ""
    var projectNo: String = ""
    var client: String = ""
    var location: String = ""
    var attn: String = ""
    /// 关联 Builder ID(BuildersStorage),用于一键发邮件。`nil` 表示 attn 是手输。
    var builderID: String?
    var reportDate: Date = Date()
    var inspectionType: String = ""
    /// 报告编号,如 "SVR25159.05A"。由 ReportNumbering 生成。
    var reportNo: String = ""

    /// 巡检员签字名(默认从 UserProfile / Settings 读)。
    var engineerName: String = ""
    /// Site Rep 状态(例如 "Emailed"、"Signed",自由文本)。
    var siteRepStatus: String = ""

    /// 自定义 disclaimer 文本块,`nil` 用 DisclaimerStorage.defaults。按行存。
    var disclaimerText: String?

    // MARK: - Note 引用(聚合)

    /// 被这份报告纳入的 Note ID 列表,按这个顺序在 PDF 里出现。
    /// SwiftData 数组存 [UUID] 直接支持(底层走 PropertyListEncoder)。
    var noteIDs: [UUID] = []

    /// 主照片来自哪条 Note(默认 noteIDs.first;用户可改)。
    /// `nil` 表示"无主照片"。PDF 渲染时找该 Note.photoPaths.first。
    var mainNoteID: UUID?

    /// 主照片 caption(显示在主照下方)。默认用 mainNoteID 的 Note.transcription,用户可改短。
    var mainCaption: String = ""

    /// 每条 Note 的 caption override。JSON: `{noteIDString: caption}`。
    /// 用户不 override 时 PDF 直接用 `note.transcription`。
    var captionOverridesJSON: String?

    // MARK: - 状态机

    /// `InspectionStatus` 原始值。
    var statusRaw: String = InspectionStatus.draft.rawValue

    /// 提交时间(submitted 后才有)。
    var submittedAt: Date?

    /// 软删时间。nil 活着,非空在回收站。
    var deletedAt: Date?

    /// 上一次导出的 PDF 文件相对路径(便于重新发邮件)。
    var lastPDFPath: String?

    var status: InspectionStatus {
        get { InspectionStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    /// 解析 captionOverridesJSON 为 [UUID: String]。失败/空返回 [:]。
    func captionOverrides() -> [UUID: String] {
        guard let json = captionOverridesJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        var out: [UUID: String] = [:]
        for (k, v) in dict {
            if let id = UUID(uuidString: k) { out[id] = v }
        }
        return out
    }

    /// 写回 captionOverridesJSON。
    func setCaptionOverrides(_ map: [UUID: String]) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: map.map { ($0.key.uuidString, $0.value) })
        captionOverridesJSON = (try? JSONEncoder().encode(stringKeyed))
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    init(
        id: UUID = UUID(),
        project: String = "",
        projectNo: String = "",
        client: String = "",
        location: String = "",
        attn: String = "",
        builderID: String? = nil,
        reportDate: Date = Date(),
        inspectionType: String = "",
        reportNo: String = "",
        engineerName: String = "",
        siteRepStatus: String = "",
        disclaimerText: String? = nil,
        noteIDs: [UUID] = [],
        mainNoteID: UUID? = nil,
        mainCaption: String = "",
        captionOverridesJSON: String? = nil
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.project = project
        self.projectNo = projectNo
        self.client = client
        self.location = location
        self.attn = attn
        self.builderID = builderID
        self.reportDate = reportDate
        self.inspectionType = inspectionType
        self.reportNo = reportNo
        self.engineerName = engineerName
        self.siteRepStatus = siteRepStatus
        self.disclaimerText = disclaimerText
        self.noteIDs = noteIDs
        self.mainNoteID = mainNoteID
        self.mainCaption = mainCaption
        self.captionOverridesJSON = captionOverridesJSON
        self.statusRaw = InspectionStatus.draft.rawValue
        self.submittedAt = nil
        self.deletedAt = nil
        self.lastPDFPath = nil
    }
}

/// 巡检状态。draft 可继续编辑;submitted 锁版本。
enum InspectionStatus: String, Codable {
    case draft
    case submitted
}
