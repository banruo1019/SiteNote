//
//  SiteNoteSchemaV2.swift
//  SiteNote
//
//  Schema V2 — v1.2 目标(也是当前主分支正在用的)。在 V1 基础上"加表":
//   + InspectionReport(QDE 风格巡检报告聚合 model)
//   + SiteVisitSchedule(工程师日程表)
//   + Team(团队,Phase 2 接 CloudKit Sharing)
//   + TeamMember(团队成员,使用 teamID UUID 软引用,无 @Relationship)
//
//  **设计约束**:与 V1 相比**只加表,不改字段、不删字段**。这让 V1 → V2
//  能走 SwiftData 默认 lightweight migration,无需自定义 stage。
//  v1.0/v1.1 用户升级 v1.2 时:旧 3 张表数据保留,新 4 张表空。
//
//  Team/TeamMember **没有** @Relationship 双向引用 —— 见 Team.swift 注释。
//

import Foundation
import SwiftData

enum SiteNoteSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    /// 所有 model(给主 Schema 用)。
    static var models: [any PersistentModel.Type] {
        coreModels + teamModels
    }

    /// 核心业务 model — 可以走 SwiftData CloudKit private DB auto-sync。
    /// Note / LogEntry 等同 Apple ID 多设备自动同步。
    static var coreModels: [any PersistentModel.Type] {
        [
            Note.self,
            LogEntry.self,
            ShareLog.self,
            InspectionReport.self,
            SiteVisitSchedule.self,
            SitePreset.self,  // v1.6: struct + UserDefaults JSON → @Model class(团队 share 需要)
        ]
    }

    /// 团队 model — **不**走 SwiftData CloudKit auto-sync(SwiftData 没公开 CKShare API)。
    /// 改由 TeamCloudKitService 用 raw CKDatabase + custom zone + CKShare 跨用户共享。
    /// 本地 SwiftData 只作缓存。
    static var teamModels: [any PersistentModel.Type] {
        [
            Team.self,
            TeamMember.self,
        ]
    }
}
