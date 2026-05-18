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
    /// R6:工地标签 — 与 SitePreset.siteTag 对齐,attachIfNeeded 用它回填 Note.siteTag。
    /// **不要**用 location / projectNo 当 siteTag fallback:location 是 PDF 当 address 渲染,
    /// projectNo 是项目号(数字)。siteTag 是工地名(如"悉尼 Olympic Park")。
    /// 老 record 没此字段 → nil,attachIfNeeded fallback 走 location(向后兼容)。
    var siteTag: String?
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

    /// CloudKit 用户 ID(CKRecord.creatorUserRecordID 的 recordName)。
    /// 创建时由 InspectionSessionManager 填 = ICloudSyncConfig.shared.currentUserRecordName。
    /// 空字符串 = 本地未登录 iCloud,视为"我"(单机用户)。
    var createdByUserID: String = ""

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

    /// **团队协作 snapshot** — Member 端 mirrorReport 时把 noteIDs 关联的 Note 摘要
    /// (transcription / siteTag / createdAt / photoCount / floorPlanRef)JSON 编码进来。
    ///
    /// **为什么需要**:share zone 只同步 InspectionReport 这张表,Note 表 SwiftData CloudKit
    /// 走 Member 自己的 private DB,Owner 跨账号无法直接看。Owner 拉到 noteIDs 但 fetch 不到
    /// Note 实体 → 详情页看不到文字证据。这个字段把"文字 + 元数据"固化进 report 本身,
    /// 跨账号即可见。**照片像素不传**(too big);用户体验上 Owner 看到摘要 + "完整照片请向
    /// Foreman 拿 PDF" 提示。后续可改 CKAsset 传图,但 v1 先文本。
    ///
    /// 结构(JSON 数组):
    /// ```json
    /// [
    ///   {"noteID":"<uuid>","transcription":"...","siteTag":"...","createdAt":"<iso8601>","photoCount":2,"floorPlanRef":"..."}
    /// ]
    /// ```
    var noteSnapshotsJSON: String?

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

    /// 解析 noteSnapshotsJSON 为 [NoteSnapshot]。失败/空返回 []。
    /// Owner 端跨账号看不到 Note 实体时,UI fallback 从这里取文字证据。
    func noteSnapshots() -> [NoteSnapshot] {
        guard let json = noteSnapshotsJSON,
              let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([NoteSnapshot].self, from: data)) ?? []
    }

    /// 写 noteSnapshotsJSON。空数组写 nil(节省 share zone record 字段空间)。
    func setNoteSnapshots(_ snapshots: [NoteSnapshot]) {
        guard !snapshots.isEmpty else {
            noteSnapshotsJSON = nil
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        noteSnapshotsJSON = (try? encoder.encode(snapshots))
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
        captionOverridesJSON: String? = nil,
        createdByUserID: String = ""
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
        self.createdByUserID = createdByUserID
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

/// 团队协作:Note 摘要(跨账号传给团队 Owner / 其他成员看)。
/// 不含照片像素 — Owner 看到文字证据 + 元数据,完整照片需 PDF 或 Foreman 设备本地。
///
/// **floorPlanID 优先**:Foreman 改了平面图名字时 Owner 端用 ID 仍能找回平面图,
/// 否则只走 `floorPlanRef` name 匹配会断绑定。
struct NoteSnapshot: Codable, Equatable {
    let noteID: UUID
    let transcription: String
    let siteTag: String?
    let createdAt: Date
    let photoCount: Int
    let floorPlanID: UUID?
    let floorPlanRef: String?

    /// Decoder 显式 fallback:老版本 snapshot(无 floorPlanID 字段)解码后 floorPlanID 为 nil。
    /// Codable 默认 optional 字段缺失 → nil,这里只是文档化。
}
