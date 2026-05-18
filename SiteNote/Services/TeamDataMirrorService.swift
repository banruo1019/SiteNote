//
//  TeamDataMirrorService.swift
//  SiteNote
//
//  团队数据双向同步服务 — 把 SwiftData @Model 实例 mirror 到 team CKShare zone,
//  让 owner / member 跨 iCloud 账号看到彼此的 SitePreset / SiteVisitSchedule / InspectionReport。
//
//  ## 架构(为啥要这层)
//
//  SwiftData iOS 17/18 **没暴露** cross-user CKShare API,所有共享必须自己用 raw CKDatabase + CKShare。
//  TeamCloudKitService 已实现 Team / TeamMember 的共享(只 2 张表),
//  本 service 把同套机制扩展到核心业务数据。
//
//  ## 写哪个 DB
//
//  Owner 在自己 private DB 的 team zone 写 records;Member 在 shared DB(指向 owner 那个 zone)写。
//  CKShare 默认 R+W 权限,Member 也能往 owner 的 zone 写。
//
//  ## 同步策略
//
//  - **写**:SwiftData @Model 写入触发 immediate mirror(下面 mirrorXxx APIs)。
//  - **读**:Owner / Member 进 RecordView / Reports Tab 时 `.task` 调 fetchAndSyncAll
//    拉这个 zone 自上次 server token 以来的 changes,反向 upsert 进本地 SwiftData。
//  - server change token 持久化 UserDefaults,避免重复拉 + 流量。
//
//  ## 现阶段不同步的
//
//  - Builder / Contact(还是 struct + UserDefaults)— Member 端会显示"未知联系人"
//  - Note(录音/拍照的 note 本身,InspectionReport 通过 noteIDs 索引;但 Member 端
//    listing 时 deference 不到 Note 实例,只看 report 的 noteIDs 引用计数)— v1 团队 MVP 折衷
//

import Foundation
import CloudKit
import SwiftData
import os

@MainActor
@Observable
final class TeamDataMirrorService {
    static let shared = TeamDataMirrorService()
    private init() {
        // 启动时恢复 retry queue 长度,UI 能立刻显示徽章
        self.pendingRetryCount = Self.loadRetryQueue().count
    }

    private let logger = Logger(subsystem: "com.banruo.sitenote", category: "TeamDataMirror")

    // MARK: - 诊断状态(给 TeamManagementView 显示用)

    /// 最后一次 fetchAndSyncAll 的结果文字 — "Synced 3 records (1 preset / 1 schedule / 1 report)" 或 "FAILED: ..."。
    private(set) var lastSyncStatus: String = "未同步"
    /// 最后一次 mirror push 的结果文字。
    private(set) var lastMirrorStatus: String = "未推送"
    /// 最后一次 sync / mirror 时间。
    private(set) var lastActivityAt: Date?
    /// fetchAndSyncAll 累计调用次数(包括 skip 的)。让用户能验证"view 切换是否真的触发 sync"。
    private(set) var syncCallCount: Int = 0
    /// 累计 mirror push 触发次数。
    private(set) var mirrorCallCount: Int = 0
    /// **Retry queue** — 未同步成功的 record entityID。在前台 / fetchAndSyncAll 时重试。
    /// @Observable property,UI 用它显示徽章("X 条未同步")。
    /// 持久化:UserDefaults key `team.mirrorRetryQueue.v1`,断网/退出后下次启动恢复。
    private(set) var pendingRetryCount: Int = 0
    private static let retryQueueKey = "team.mirrorRetryQueue.v1"

    private let containerID = "iCloud.com.banruo.SiteNote"
    private var container: CKContainer { CKContainer(identifier: containerID) }
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    // MARK: - Record types(独立于 SwiftData 的 CD_<class> 自动命名)
    enum RT {
        static let sitePreset = "SiteNoteSitePreset"
        static let schedule = "SiteNoteSchedule"
        static let report = "SiteNoteReport"
    }

    // MARK: - 当前团队 / Owner 判断

    /// 当前的 team(假设单 team 模型,取第一个未软删的)。
    func currentTeam(in modelContext: ModelContext) -> Team? {
        let desc = FetchDescriptor<Team>(
            predicate: #Predicate<Team> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let teams = (try? modelContext.fetch(desc)) ?? []
        guard !teams.isEmpty else { return nil }

        let currentUser = ICloudSyncConfig.shared.currentUserRecordName ?? ""
        let defaults = UserDefaults.standard

        // 旧版 / 内测设备可能残留多条 Team。优先选择真正接入 CloudKit share 的那条,
        // 避免拿第一条本地旧缓存去拉一个不存在或不可见的 zone。
        if !currentUser.isEmpty,
           let ownerShared = teams.first(where: {
               $0.ownerUserID == currentUser && $0.cloudShareRecordName != nil
           }) {
            return ownerShared
        }
        if let memberShared = teams.first(where: {
            defaults.string(forKey: "team.sharedZoneOwnerName.\($0.id.uuidString)") != nil
        }) {
            return memberShared
        }
        if let anyShared = teams.first(where: { $0.cloudShareRecordName != nil }) {
            return anyShared
        }
        if !currentUser.isEmpty,
           let ownerLocal = teams.first(where: { $0.ownerUserID == currentUser }) {
            return ownerLocal
        }
        return teams.first
    }

    /// 当前用户是该团队的 owner?
    func isOwner(of team: Team) -> Bool {
        guard let currentUser = ICloudSyncConfig.shared.currentUserRecordName else {
            return false
        }
        return team.ownerUserID == currentUser
    }

    /// 该团队的 CloudKit zone ID。
    ///
    /// - Owner 端:直接构造 `CKCurrentUserDefaultName`。
    /// - Member 端:**不能用 `team.ownerUserID` 反推**。Owner 写入的 ownerUserID 是
    ///   Owner Container 视角的 user record name,Member Container 视角看到同一个 user
    ///   的 record name 可能不同(或 Owner createTeam 时 currentUserRecordName 还没拉到
    ///   → 空字符串)。这是 Member 端 fetchAndSyncAll "拉到 0 条" 的根因。
    ///   - 优先用 acceptShareInvitation 时缓存到 UserDefaults 的 ownerName
    ///   - cache miss 则 `sharedDB.allRecordZones()` 枚举找 zoneName 匹配的 zone,
    ///     拿到的 zoneID 是 CloudKit 给的真实 share zone identity(成功后回写缓存)
    private func resolveZoneID(for team: Team) async -> CKRecordZone.ID? {
        if isOwner(of: team) {
            return CKRecordZone.ID(
                zoneName: team.id.uuidString,
                ownerName: CKCurrentUserDefaultName
            )
        }
        let key = "team.sharedZoneOwnerName.\(team.id.uuidString)"
        if let cached = UserDefaults.standard.string(forKey: key), !cached.isEmpty {
            return CKRecordZone.ID(zoneName: team.id.uuidString, ownerName: cached)
        }
        // cache miss → 枚举 sharedDB 找匹配 zone
        do {
            let zones = try await sharedDB.allRecordZones()
            if let match = zones.first(where: { $0.zoneID.zoneName == team.id.uuidString }) {
                UserDefaults.standard.set(match.zoneID.ownerName, forKey: key)
                logger.info("Resolved member zone via enumeration: owner=\(match.zoneID.ownerName)")
                return match.zoneID
            }
            logger.warning("Zone not visible in shared DB (\(zones.count) zones)")
            return nil
        } catch {
            logger.error("allRecordZones() FAILED: \(error.localizedDescription)")
            return nil
        }
    }

    /// 写时该用哪个 DB(Owner 走 private,Member 走 shared)。
    private func database(for team: Team) -> CKDatabase {
        isOwner(of: team) ? privateDB : sharedDB
    }

    // MARK: - Owner / Member 都能调:把本地 @Model 写到 zone

    /// SitePreset → CKRecord 写到 team zone。team 为 nil(单机模式)直接 no-op。
    func mirrorSitePreset(_ preset: SitePreset, in modelContext: ModelContext) async {
        guard let team = currentTeam(in: modelContext) else {
            logger.warning("mirrorSitePreset SKIPPED — no current team(单机模式)")
            return
        }
        logger.info("mirrorSitePreset CALLED siteTag=\(preset.siteTag) team=\(team.name) isOwner=\(self.isOwner(of: team))")
        guard let zone = await resolveZoneID(for: team) else {
            logger.warning("mirrorSitePreset SKIPPED — zone not resolved")
            lastMirrorStatus = "✗ preset zone 未解析(Member 端未接受邀请或 share 失效)"
            return
        }
        let recordID = CKRecord.ID(recordName: "preset-\(preset.id.uuidString)", zoneID: zone)
        let record = CKRecord(recordType: RT.sitePreset, recordID: recordID)
        record["id"] = preset.id.uuidString as CKRecordValue
        record["siteTag"] = preset.siteTag as CKRecordValue
        record["projectName"] = preset.projectName as CKRecordValue
        record["projectNo"] = preset.projectNo as CKRecordValue
        record["clientName"] = preset.clientName as CKRecordValue
        record["address"] = preset.address as CKRecordValue
        record["defaultAttn"] = preset.defaultAttn as CKRecordValue
        record["defaultInspectionType"] = preset.defaultInspectionType as CKRecordValue
        record["notes"] = preset.notes as CKRecordValue
        if let assignedTo = preset.assignedToUserID {
            record["assignedToUserID"] = assignedTo as CKRecordValue
        }
        if let assignedAt = preset.assignedAt {
            record["assignedAt"] = assignedAt as CKRecordValue
        }
        record["linkedContactIDs"] = preset.linkedContactIDs.map { $0.uuidString } as CKRecordValue
        record["defaultRecipientIDs"] = preset.defaultRecipientIDs.map { $0.uuidString } as CKRecordValue
        record["updatedAt"] = preset.updatedAt as CKRecordValue
        if let deletedAt = preset.deletedAt {
            record["deletedAt"] = deletedAt as CKRecordValue
        }
        await save(record: record, db: database(for: team), context: "preset")
    }

    /// SiteVisitSchedule → CKRecord。
    func mirrorSchedule(_ schedule: SiteVisitSchedule, in modelContext: ModelContext) async {
        guard let team = currentTeam(in: modelContext) else {
            logger.warning("mirrorSchedule SKIPPED — no current team(单机模式)")
            return
        }
        logger.info("mirrorSchedule CALLED title=\(schedule.title) assignedTo=\(schedule.assignedToUserID ?? "nil") team=\(team.name)")
        guard let zone = await resolveZoneID(for: team) else {
            logger.warning("mirrorSchedule SKIPPED — zone not resolved")
            lastMirrorStatus = "✗ schedule zone 未解析(Member 端未接受邀请或 share 失效)"
            return
        }
        let recordID = CKRecord.ID(recordName: "schedule-\(schedule.id.uuidString)", zoneID: zone)
        let record = CKRecord(recordType: RT.schedule, recordID: recordID)
        record["id"] = schedule.id.uuidString as CKRecordValue
        record["scheduledDate"] = schedule.scheduledDate as CKRecordValue
        if let time = schedule.scheduledTime {
            record["scheduledTime"] = time as CKRecordValue
        }
        if let siteTag = schedule.siteTag {
            record["siteTag"] = siteTag as CKRecordValue
        }
        record["title"] = schedule.title as CKRecordValue
        record["notes"] = schedule.notes as CKRecordValue
        record["statusRaw"] = schedule.statusRaw as CKRecordValue
        if let completedAt = schedule.completedAt {
            record["completedAt"] = completedAt as CKRecordValue
        }
        if let assignedTo = schedule.assignedToUserID {
            record["assignedToUserID"] = assignedTo as CKRecordValue
        }
        if let linkedReport = schedule.linkedReportID {
            record["linkedReportID"] = linkedReport.uuidString as CKRecordValue
        }
        record["createdAt"] = schedule.createdAt as CKRecordValue
        if let deletedAt = schedule.deletedAt {
            record["deletedAt"] = deletedAt as CKRecordValue
        }
        await save(record: record, db: database(for: team), context: "schedule")
    }

    /// InspectionReport → CKRecord。也写 `createdAt`(让 Owner 端按真实创建时间排序)。
    func mirrorReport(_ report: InspectionReport, in modelContext: ModelContext) async {
        guard let team = currentTeam(in: modelContext) else {
            logger.warning("mirrorReport SKIPPED — no current team(单机模式)")
            return
        }
        // **Codex#5 自愈**:Note 创建时 currentUserRecordName 可能还没拉到 →
        // report.createdByUserID 写了 ""。本地保存后下一次 mirror 时如果 cache 已就绪,
        // 补回 createdByUserID 然后 mirror,避免 Owner 端拉到 createdByUserID 为空的 report
        // → 团队视图过滤错(用 .mine scope 会把空 createdByUserID 当"我的")。
        if report.createdByUserID.isEmpty {
            if ICloudSyncConfig.shared.currentUserRecordName == nil {
                try? await ICloudSyncConfig.shared.fetchAndCacheUserRecord()
            }
            if let me = ICloudSyncConfig.shared.currentUserRecordName, !me.isEmpty {
                report.createdByUserID = me
                // **R3#5**:cloud 写对了但本地没 save → app kill 后 .mine scope 仍误判。
                try? modelContext.save()
                logger.info("mirrorReport: backfilled empty createdByUserID with current user + persisted")
            }
        }
        logger.info("mirrorReport CALLED reportNo=\(report.reportNo) createdBy=\(report.createdByUserID) team=\(team.name)")
        guard let zone = await resolveZoneID(for: team) else {
            logger.warning("mirrorReport SKIPPED — zone not resolved")
            lastMirrorStatus = "✗ report zone 未解析(Member 端未接受邀请或 share 失效)"
            return
        }
        let recordID = CKRecord.ID(recordName: "report-\(report.id.uuidString)", zoneID: zone)
        let record = CKRecord(recordType: RT.report, recordID: recordID)
        record["id"] = report.id.uuidString as CKRecordValue
        record["reportNo"] = report.reportNo as CKRecordValue
        record["project"] = report.project as CKRecordValue
        record["projectNo"] = report.projectNo as CKRecordValue
        record["client"] = report.client as CKRecordValue
        record["location"] = report.location as CKRecordValue
        record["inspectionType"] = report.inspectionType as CKRecordValue
        record["attn"] = report.attn as CKRecordValue
        if let siteTag = report.siteTag, !siteTag.isEmpty {
            record["siteTag"] = siteTag as CKRecordValue
        }
        record["engineerName"] = report.engineerName as CKRecordValue
        record["statusRaw"] = report.statusRaw as CKRecordValue
        record["reportDate"] = report.reportDate as CKRecordValue
        if let submittedAt = report.submittedAt {
            record["submittedAt"] = submittedAt as CKRecordValue
        }
        record["createdByUserID"] = report.createdByUserID as CKRecordValue
        record["noteIDs"] = report.noteIDs.map { $0.uuidString } as CKRecordValue
        record["createdAt"] = report.createdAt as CKRecordValue
        record["updatedAt"] = report.updatedAt as CKRecordValue
        // 团队协作 snapshot — 给 Owner 跨账号看 Foreman 提交的文字证据(transcription / 元数据)。
        // 照片像素不传(too big);后续可改 CKAsset。
        //
        // **Codex#2 关键防御**:Note 表跨账号不同步,Owner 端 mirror Member 的 report 时本地
        // **没有** noteIDs 对应的 Note 实体。如果无条件 rebuild,compactMap 返回 [] →
        // setNoteSnapshots([]) → noteSnapshotsJSON 被清空 → share zone 上原本由 Foreman 写的
        // 文字证据被 Owner 一次 view-触发 mirror 就抹掉了。
        //
        // 策略:只在**本设备至少有部分 noteIDs 对应的 Note 实体**时才 rebuild。否则保留原值。
        if hasLocalNotes(for: report, in: modelContext) {
            rebuildNoteSnapshots(for: report, in: modelContext)
        }
        if let snapshotJSON = report.noteSnapshotsJSON {
            record["noteSnapshots"] = snapshotJSON as CKRecordValue
        }
        if let deletedAt = report.deletedAt {
            record["deletedAt"] = deletedAt as CKRecordValue
        }
        await save(record: record, db: database(for: team), context: "report")
    }

    /// 本设备是否有 report.noteIDs 中**任一**对应的 Note 实体。
    /// Codex#2:Owner 端跨账号 mirror Member 的 report 时本地没 Note 实体,这条返回 false,
    /// caller 跳过 rebuild,保留原 noteSnapshotsJSON(避免抹掉 Foreman 提交的文字证据)。
    private func hasLocalNotes(for report: InspectionReport, in modelContext: ModelContext) -> Bool {
        let ids = report.noteIDs
        guard !ids.isEmpty else { return false }
        let idSet = Set(ids)
        let all = (try? modelContext.fetch(FetchDescriptor<Note>())) ?? []
        return all.contains { idSet.contains($0.id) }
    }

    /// 给一个 InspectionReport 重建 noteSnapshots(本地 Note 实体 → JSON 摘要),回写 report.noteSnapshotsJSON。
    /// Member 端 mirrorReport 前调,让 Owner 拉到 record 时能直接看到文字证据。
    /// Owner 端也会调(但 Owner 本地大多数 Note 实体是 mirror 进来的,可能没真照片 — 没事,
    /// 只要 transcription 是从 Note 拿的就行)。
    private func rebuildNoteSnapshots(for report: InspectionReport, in modelContext: ModelContext) {
        let noteIDs = report.noteIDs
        guard !noteIDs.isEmpty else {
            report.setNoteSnapshots([])
            return
        }
        let idSet = Set(noteIDs)
        let allNotes = (try? modelContext.fetch(FetchDescriptor<Note>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: allNotes.filter { idSet.contains($0.id) }.map { ($0.id, $0) })
        let snapshots: [NoteSnapshot] = noteIDs.compactMap { id in
            guard let n = byID[id] else { return nil }
            return NoteSnapshot(
                noteID: n.id,
                transcription: n.transcription,
                siteTag: n.siteTag,
                createdAt: n.createdAt,
                photoCount: n.photoPaths.count,
                floorPlanID: n.floorPlanID,
                floorPlanRef: n.floorPlanRef
            )
        }
        report.setNoteSnapshots(snapshots)
    }

    /// 内部:保存 record 到 db,记日志失败不抛(mirror 是 best-effort,不阻塞 UI)。
    /// **savePolicy: .allKeys**:不查 etag 强写,避免 etag 冲突死循环。
    private func save(record: CKRecord, db: CKDatabase, context: String) async {
        mirrorCallCount += 1
        lastActivityAt = Date()
        let zoneOwner = record.recordID.zoneID.ownerName
        let dbName = (db === privateDB) ? "private" : "shared"
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            logger.info("Mirror \(context) OK: \(record.recordID.recordName) db=\(dbName) zone-owner=\(zoneOwner)")
            // **关键诊断 — 用户报"推送成功但 R:0"**:
            // modifyRecords 返回 success 不保证 record 真到目标 zone。Apple CloudKit 在
            // sharedDB 写 share zone 时,如果 share 权限/状态有问题,server 可能"接受写入但不
            // propagate 到 share zone" — 静默假成功。
            // 立刻读回验证:`db.record(for: recordID)`。读到 → 真成功。读不到 → push 进了
            // 黑洞,lastMirrorStatus 显示 "推送伪成功",让用户立刻看到。
            var verifyMark = "✓"
            do {
                _ = try await db.record(for: record.recordID)
            } catch {
                verifyMark = "⚠ 伪成功"
                logger.error("Mirror \(context) verify FAILED — push 没真到 zone: \(error.localizedDescription)")
            }
            lastMirrorStatus = "\(verifyMark) #\(mirrorCallCount) \(context) [\(dbName)] zone-owner=\(zoneOwner.prefix(12))"
            // 成功:从 retry queue 移除(若之前在队列)
            dequeueRetry(recordName: record.recordID.recordName)
        } catch {
            logger.error("Mirror \(context) FAILED: \(error.localizedDescription) db=\(dbName) zone-owner=\(zoneOwner)")
            lastMirrorStatus = "✗ #\(mirrorCallCount) \(context) [\(dbName)] 失败 zone-owner=\(zoneOwner.prefix(12)): \(error.localizedDescription.prefix(40))"
            // 失败:入 retry queue,fetchAndSyncAll 入口 / app 前台时重发
            enqueueRetry(recordName: record.recordID.recordName)
        }
    }

    // MARK: - Retry queue(P1 修:mirror 失败持久化重试)

    /// Retry 队列存:recordName 字符串(`preset-<uuid>` / `schedule-<uuid>` / `report-<uuid>`)。
    /// **不存 record 内容** — 重发时从 SwiftData 拉最新实体重新构造 CKRecord,保证字段不 stale。
    private static func loadRetryQueue() -> [String] {
        UserDefaults.standard.stringArray(forKey: retryQueueKey) ?? []
    }

    private static func saveRetryQueue(_ items: [String]) {
        if items.isEmpty {
            UserDefaults.standard.removeObject(forKey: retryQueueKey)
        } else {
            UserDefaults.standard.set(items, forKey: retryQueueKey)
        }
    }

    /// Mirror 失败时调:把 recordName 加入 retry queue(去重)。
    private func enqueueRetry(recordName: String) {
        var queue = Self.loadRetryQueue()
        if !queue.contains(recordName) {
            queue.append(recordName)
            Self.saveRetryQueue(queue)
        }
        pendingRetryCount = queue.count
        logger.info("Retry queue size now \(queue.count) (added \(recordName))")
    }

    /// Mirror 成功时调:从队列删该 recordName。
    private func dequeueRetry(recordName: String) {
        var queue = Self.loadRetryQueue()
        let countBefore = queue.count
        queue.removeAll { $0 == recordName }
        if queue.count != countBefore {
            Self.saveRetryQueue(queue)
            pendingRetryCount = queue.count
            logger.info("Retry queue size now \(queue.count) (removed \(recordName))")
        }
    }

    /// 处理 retry queue:遍历每条 recordName,从 SwiftData 取最新实体重新 mirror。
    /// `fetchAndSyncAll` 开头调一次;`SiteNoteApp` scenePhase = .active 也可调。
    /// 成功的 record 在 mirrorXxx 内部 save() 成功路径会 dequeue。
    func processRetryQueue(in modelContext: ModelContext) async {
        let queue = Self.loadRetryQueue()
        guard !queue.isEmpty else { return }
        logger.info("Processing retry queue: \(queue.count) items")
        for name in queue {
            // recordName 格式:<type>-<uuid>
            let parts = name.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { continue }
            switch String(parts[0]) {
            case "preset":
                if let p = try? modelContext.fetch(FetchDescriptor<SitePreset>(
                    predicate: #Predicate<SitePreset> { $0.id == id }
                )).first {
                    await mirrorSitePreset(p, in: modelContext)
                }
            case "schedule":
                if let s = try? modelContext.fetch(FetchDescriptor<SiteVisitSchedule>(
                    predicate: #Predicate<SiteVisitSchedule> { $0.id == id }
                )).first {
                    await mirrorSchedule(s, in: modelContext)
                }
            case "report":
                if let r = try? modelContext.fetch(FetchDescriptor<InspectionReport>(
                    predicate: #Predicate<InspectionReport> { $0.id == id }
                )).first {
                    await mirrorReport(r, in: modelContext)
                }
            default:
                // 未知类型(如 TeamMember 不在 retry 范畴)→ 从队列移除避免卡死
                dequeueRetry(recordName: name)
            }
        }
    }

    // MARK: - 反向 sync:从 zone 拉 records,upsert 进本地 SwiftData

    /// 旧版本可能出现"已接受 share,但本地没有 Team 记录"的坏状态。
    /// 这种情况下 `fetchAndSyncAll` 会因为 no current team 直接跳过,导致永远拉不到报告。
    /// 这里从 sharedDB 可见 zone 里恢复一个本地 Team cache,再把 zone 全量 records upsert 进来。
    private func recoverSharedTeamFromVisibleZones(in modelContext: ModelContext) async -> Team? {
        do {
            let zones = try await sharedDB.allRecordZones()
            for zone in zones {
                guard let teamID = UUID(uuidString: zone.zoneID.zoneName) else { continue }

                UserDefaults.standard.set(
                    zone.zoneID.ownerName,
                    forKey: "team.sharedZoneOwnerName.\(zone.zoneID.zoneName)"
                )

                var recoveredName: String?
                if let changes = try? await sharedDB.recordZoneChanges(inZoneWith: zone.zoneID, since: nil) {
                    for (_, mod) in changes.modificationResultsByID {
                        guard let record = try? mod.get().record else { continue }
                        if record.recordType == "SiteNoteTeam" {
                            recoveredName = record["name"] as? String
                        }
                        upsert(record: record, in: modelContext)
                    }
                }

                if let existing = try? modelContext.fetch(FetchDescriptor<Team>(
                    predicate: #Predicate<Team> { $0.id == teamID }
                )).first {
                    if existing.cloudShareRecordName == nil {
                        existing.cloudShareRecordName = CKRecordNameZoneWideShare
                    }
                    try? modelContext.save()
                    logger.info("Recovered local team cache from shared zone: \(teamID.uuidString)")
                    return existing
                }

                let fallbackName = recoveredName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let team = Team(
                    id: teamID,
                    name: (fallbackName?.isEmpty == false ? fallbackName! : "Shared Team"),
                    ownerUserID: zone.zoneID.ownerName
                )
                team.cloudShareRecordName = CKRecordNameZoneWideShare
                modelContext.insert(team)
                try? modelContext.save()
                logger.info("Created fallback local team from shared zone: \(teamID.uuidString)")
                return team
            }
        } catch {
            logger.error("recoverSharedTeamFromVisibleZones FAILED: \(error.localizedDescription)")
        }
        return nil
    }

    /// Owner / Member 进入 view 时 `.task` 调,拉当前 team zone 自上次 server token 以来的 changes。
    /// 反向 upsert SitePreset / Schedule / Report 进本地 SwiftData。
    /// 失败不抛(best effort + log)。
    /// `forceFullSync` 用于用户手动刷新 / 首次接受邀请后的自愈,会忽略本地 server token。
    /// `_isRetryAfterTokenExpiry` 内部参数:防 changeTokenExpired 递归二次失败时无限循环。
    func fetchAndSyncAll(
        in modelContext: ModelContext,
        forceFullSync: Bool = false,
        _isRetryAfterTokenExpiry: Bool = false
    ) async {
        syncCallCount += 1
        // Swift ?? 右侧不能 await,拆开:
        let team: Team
        if let local = currentTeam(in: modelContext) {
            team = local
        } else if let recovered = await recoverSharedTeamFromVisibleZones(in: modelContext) {
            team = recovered
        } else {
            logger.info("fetchAndSyncAll SKIPPED — no current team")
            lastSyncStatus = "⏭ 跳过(没团队)#\(syncCallCount)"
            lastActivityAt = Date()
            return
        }
        // **P1 修(用户报"团队 report 不同步")**:先处理 retry queue 重发失败的 mirror。
        // 这覆盖了"用户完成巡检时网络瞬断 → mirror 失败 → record 在本地但 share zone 没有"
        // 这条 silent 数据丢失路径。仅 _isRetryAfterTokenExpiry=false 时跑,避免 token 过期递归重做。
        if !_isRetryAfterTokenExpiry {
            await processRetryQueue(in: modelContext)
        }
        // **关键**:isOwner + ensureSelfMemberRecord 都依赖 currentUserRecordName。
        // 首次启动时 SiteNoteApp 用 Task.detached 异步拉 user record,view .task 可能更早触发 →
        // 这里同步 await 一次保证 isOwner 判断 + register 不静默失败。
        if ICloudSyncConfig.shared.currentUserRecordName == nil {
            try? await ICloudSyncConfig.shared.fetchAndCacheUserRecord()
        }
        // **P0 用户报告"团队 report 拉到 0 条"诊断**:isOwner sanity check。
        // 如果本机是 Owner 创建团队的设备,但当前 currentUserRecordName 跟 team.ownerUserID
        // 不一致(可能是 cache 失效 / 老 record),会走 Member 分支拉 sharedDB → 拉不到自己的 zone
        // → 永远 0 条。这里强制 re-fetch 一次 user record,然后比对。
        let myID = ICloudSyncConfig.shared.currentUserRecordName ?? ""
        let teamOwnerID = team.ownerUserID
        // 边界:team.ownerUserID 在 Owner 创建团队时写,但若创建时 currentUserRecordName 是空,
        // 会写成 "" — Owner 后续永远 isOwner=false。这里检测并尝试自愈。
        if teamOwnerID.isEmpty && !myID.isEmpty {
            // Owner 创建时 race condition,补 ownerUserID
            team.ownerUserID = myID
            try? modelContext.save()
            logger.warning("isOwner sanity: team.ownerUserID was empty, backfilled with current user")
        }
        guard let zone = await resolveZoneID(for: team) else {
            logger.warning("fetchAndSyncAll SKIPPED — zone not resolved (Member 端未接受邀请 / share 失效)")
            lastSyncStatus = "✗ #\(syncCallCount) zone 未解析 | me=\(myID.prefix(8)) ownerID=\(teamOwnerID.prefix(8))"
            return
        }
        let db = database(for: team)
        // Token 必须 Owner / Member 独立 — 同 zone 在 privateDB 和 sharedDB 视角下
        // 是不同的 CloudKit DB,各自维护独立的 server change token。混用会触发
        // CKError.changeTokenExpired 或更糟:静默 "0 条变更",这是 Owner 拉不到 Member
        // push 的 record 的潜在原因之一。
        let isOwnerNow = isOwner(of: team)
        let dbTag = isOwnerNow ? "private" : "shared"
        let tokenKey = "team.serverChangeToken.\(zone.zoneName).\(dbTag).v2"
        let lastToken = forceFullSync ? nil : loadToken(key: tokenKey)

        logger.info("fetchAndSyncAll START team=\(team.name) isOwner=\(isOwnerNow) db=\(dbTag) zone=\(zone.zoneName) ownerName=\(zone.ownerName) forceFull=\(forceFullSync) hasToken=\(lastToken != nil) myID=\(myID.prefix(12)) teamOwnerID=\(teamOwnerID.prefix(12))")
        lastActivityAt = Date()
        do {
            let result = try await db.recordZoneChanges(inZoneWith: zone, since: lastToken)
            // 1. upsert 所有变更
            var presetCount = 0, scheduleCount = 0, reportCount = 0, memberCount = 0, teamCount = 0
            for (_, mod) in result.modificationResultsByID {
                if let record = try? mod.get().record {
                    upsert(record: record, in: modelContext)
                    switch record.recordType {
                    case RT.sitePreset: presetCount += 1
                    case RT.schedule: scheduleCount += 1
                    case RT.report: reportCount += 1
                    case "SiteNoteTeam": teamCount += 1
                    case "SiteNoteTeamMember": memberCount += 1
                    default: break
                    }
                }
            }
            // 2. 软删:CKShare 删的 record 走 deletions
            for deletion in result.deletions {
                softDelete(recordID: deletion.recordID, in: modelContext)
            }
            // **关键**:save 必须 explicit catch。SwiftData 启用了 CloudKit 自动同步
            // (.private(containerID)),mirror 进来的 record 在 save 时会触发 SwiftData
            // CloudKit 链路把它推到 SwiftData 自己的 zone。如果该链路 reject(配额/网络/
            // 默认 record type 冲突),save 会抛错且**本地不 persist** → 看上去"拉到 N 条"
            // 但 @Query 永远看不到。之前 try? 吞了这个错误,根本看不到失败原因。
            var saveErr: String?
            do {
                try modelContext.save()
            } catch {
                saveErr = error.localizedDescription
                logger.error("modelContext.save() FAILED after upsert: \(error.localizedDescription)")
            }
            // 验证:SwiftData 里实际可见的 InspectionReport 总数 + 团队成员创建的数量
            let allReportsAfter = (try? modelContext.fetch(FetchDescriptor<InspectionReport>())) ?? []
            let myID = ICloudSyncConfig.shared.currentUserRecordName ?? ""
            let othersCount = allReportsAfter.filter {
                $0.deletedAt == nil && !$0.createdByUserID.isEmpty && $0.createdByUserID != myID
            }.count
            // **Codex#1 关键修**:Token 仅在 save 成功时推进。
            // 之前不管 save 失败都 saveToken → 下次 fetch token 已过本批 record → 永久丢。
            // save 失败时保留旧 token,下次 fetchAndSyncAll 会重新拉到这些 record 再 upsert。
            let total = result.modificationResultsByID.count
            // P0:暴露 isOwner / db 给 UI,用户看到 "Owner拉private" vs "Member拉shared" 立刻能判断走没走对分支
            let roleTag = isOwnerNow ? "Owner" : "Member"
            if saveErr == nil {
                saveToken(result.changeToken, key: tokenKey)
                logger.info("Synced \(total) records + \(result.deletions.count) deletes from zone=\(zone.zoneName) | DB has \(allReportsAfter.count) reports total, \(othersCount) from others")
                lastSyncStatus = "✓ #\(syncCallCount) [\(roleTag)/\(dbTag)] 拉到 \(total) 条 (P:\(presetCount) S:\(scheduleCount) R:\(reportCount) T:\(teamCount) M:\(memberCount)) | DB 报告共 \(allReportsAfter.count) 条,他人 \(othersCount) 条"
            } else {
                logger.warning("Token NOT advanced because save failed; will retry next sync")
                lastSyncStatus = "⚠ #\(syncCallCount) [\(roleTag)/\(dbTag)] 拉到 \(total) 条但本地 save 失败: \(saveErr!.prefix(60)) (token 保留,下次重试)"
            }

            // 4. 自愈:确保自己在 zone 的 TeamMember 列表里 — Owner 和 Member 都需要
            // (老团队 owner 没推自己 / Member 首次 register 失败)。每次 fetch 后检查 + 补推。
            await ensureSelfMemberRecord(team: team, in: modelContext)

            // 5. Owner 端孤儿清理:zone 里可能有多条同 userID 不同 memberID 的孤儿
            // (Jamie 端 oscillation 修复前用 UUID() 多次推留下),导致 picker 里同人显示 N 次。
            // 只 Owner 能删 zone 里别人写的 record(zone admin 权限);Member 没权。
            if isOwner(of: team) {
                await cleanupDuplicateMembers(team: team, zone: zone, in: modelContext)
            }
        } catch {
            // **关键**:Owner 解散团队(deleteTeamZoneOnCloud)后,Member 端拉 zone changes
            // 会拿到 CKError.zoneNotFound / userDeletedZone → 视为团队已解散,清本地 Team + TeamMember
            // 让 Member 视图退出团队状态。
            if isZoneGone(error) {
                logger.warning("Zone gone (owner dissolved team) — clearing local team mirror")
                clearLocalTeamMirror(team: team, in: modelContext)
                lastSyncStatus = "⚠ #\(syncCallCount) 团队 zone 已删除,本地团队清空"
            } else if isChangeTokenExpired(error) {
                // **Codex#3 + R3#3 修**:changeTokenExpired 时 CloudKit 要求清 token 重拉全量,
                // 否则后续每次同步都失败 → 永久卡死。
                // **关键**:`_isRetryAfterTokenExpiry` 防递归二次失败时无限循环 → stack overflow。
                if _isRetryAfterTokenExpiry {
                    logger.error("changeTokenExpired AGAIN on full sync — bail to avoid infinite loop")
                    lastSyncStatus = "✗ #\(syncCallCount) token 反复过期(服务端异常),停止重试"
                } else {
                    logger.warning("changeTokenExpired — clearing token + retrying full sync")
                    UserDefaults.standard.removeObject(forKey: tokenKey)
                    lastSyncStatus = "🔄 #\(syncCallCount) token 过期,自动重试全量同步"
                    // 仅递归一次,带 flag 防进一步递归
                    await fetchAndSyncAll(
                        in: modelContext,
                        forceFullSync: true,
                        _isRetryAfterTokenExpiry: true
                    )
                }
            } else {
                logger.error("Sync FAILED for zone=\(zone.zoneName): \(error.localizedDescription)")
                lastSyncStatus = "✗ #\(syncCallCount) 失败: \(error.localizedDescription)"
            }
        }
    }

    /// CKError.changeTokenExpired:服务器端把这个 zone 的 history 截断了(常见于长时间不同步或
    /// CloudKit 端 storage policy),客户端必须丢弃 token 重新全量拉。
    private func isChangeTokenExpired(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        return ckError.code == .changeTokenExpired
    }

    /// 判断 CKError 是否是"团队已被解散"信号。
    private func isZoneGone(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .zoneNotFound, .userDeletedZone:
            return true
        default:
            return false
        }
    }

    /// Member 端检测到 owner 已解散团队 → 清本地 Team + TeamMember + 所有 team UserDefaults 缓存。
    /// SitePreset / Schedule / Report 这些 mirror 进来的数据**保留**(算 member 离队后的本地存档),
    /// 不破坏 member 自己曾经做的工作。
    func clearLocalTeamMirror(team: Team, in modelContext: ModelContext) {
        let teamID = team.id
        // 删本地 Team(软删,deletedAt)
        team.deletedAt = Date()
        // 删本地 TeamMember(硬删,UI 立即看不到)
        let members = try? modelContext.fetch(FetchDescriptor<TeamMember>(
            predicate: #Predicate<TeamMember> { $0.teamID == teamID }
        ))
        for m in (members ?? []) {
            modelContext.delete(m)
        }
        try? modelContext.save()
        purgeTeamLocalCaches(teamID: teamID)
        logger.info("clearLocalTeamMirror DONE for teamID=\(teamID)")
    }

    /// Owner 端孤儿清理:本地 SwiftData fetch 该 team 所有 TeamMember,按 userID group,
    /// 同 userID 多条只保留一条(自己 → stableMemberID;其他 → joinedAt 最晚),
    /// 多余的从本地 + zone 一起删。空 userID 的 placeholder 一律删。
    ///
    /// 为什么需要:Jamie 端 oscillation bug 修复前用 `UUID()` 新生成 memberID 推 zone,zone 里
    /// 累积了多条 Jamie 的孤儿,Owner 端 fetchAndSyncAll 全拉进本地 → picker 里同人显示 N 次。
    /// Jamie 端无权删 Owner zone 里别人(指自己历史 push 的)record,只能 Owner 来清。
    private func cleanupDuplicateMembers(
        team: Team,
        zone: CKRecordZone.ID,
        in modelContext: ModelContext
    ) async {
        let teamID = team.id
        let members = (try? modelContext.fetch(FetchDescriptor<TeamMember>(
            predicate: #Predicate<TeamMember> { $0.teamID == teamID }
        ))) ?? []

        let myUserID = ICloudSyncConfig.shared.currentUserRecordName ?? ""
        let myStableMemberID: UUID? = {
            let key = "team.selfMemberID.\(teamID.uuidString)"
            if let s = UserDefaults.standard.string(forKey: key) { return UUID(uuidString: s) }
            return nil
        }()

        var toDelete: [TeamMember] = []
        var zoneIDsToDelete: [CKRecord.ID] = []

        // 按 userID 分组
        let grouped = Dictionary(grouping: members, by: { $0.userID })
        for (userID, group) in grouped {
            if userID.isEmpty {
                // 空 userID placeholder 全删
                toDelete.append(contentsOf: group)
                continue
            }
            let keep: TeamMember
            if userID == myUserID, let stable = myStableMemberID, let stableMatch = group.first(where: { $0.id == stable }) {
                keep = stableMatch
            } else {
                keep = group.sorted(by: { $0.joinedAt > $1.joinedAt }).first ?? group[0]
            }
            for m in group where m.id != keep.id {
                toDelete.append(m)
            }
        }

        guard !toDelete.isEmpty else { return }

        for m in toDelete {
            zoneIDsToDelete.append(CKRecord.ID(recordName: m.id.uuidString, zoneID: zone))
            modelContext.delete(m)
        }
        try? modelContext.save()
        logger.info("cleanupDuplicateMembers: removed \(toDelete.count) duplicates (local + zone)")

        // Owner 在 privateDB,zone admin 权限能删
        do {
            _ = try await privateDB.modifyRecords(saving: [], deleting: zoneIDsToDelete, savePolicy: .allKeys)
        } catch {
            logger.warning("cleanupDuplicateMembers zone delete partial fail: \(error.localizedDescription)")
        }
    }

    /// 自愈:确保 share zone 里有当前用户的 TeamMember CKRecord。
    /// **关键稳定性**:自己的 memberID 用 UserDefaults 持久化(`team.selfMemberID.<teamID>`),
    /// 永远复用同一个 id — 即使本地 TeamMember 被某种原因删了,重建仍用同 id,zone 里只有一条
    /// (避免 owner 端 defense 2 删旧 id → bob 端重新 push 新 id → owner 又删 → 死循环 oscillation,
    /// 表现就是 owner 端 bob 时有时无)。
    private func ensureSelfMemberRecord(team: Team, in modelContext: ModelContext) async {
        guard let myUserID = ICloudSyncConfig.shared.currentUserRecordName, !myUserID.isEmpty else { return }
        let teamID = team.id

        // 取/建持久化 memberID
        let memberIDKey = "team.selfMemberID.\(teamID.uuidString)"
        let stableMemberID: UUID = {
            if let s = UserDefaults.standard.string(forKey: memberIDKey),
               let id = UUID(uuidString: s) {
                return id
            }
            let new = UUID()
            UserDefaults.standard.set(new.uuidString, forKey: memberIDKey)
            return new
        }()

        let existing = try? modelContext.fetch(FetchDescriptor<TeamMember>(
            predicate: #Predicate<TeamMember> { $0.userID == myUserID && $0.teamID == teamID }
        )).first
        let myName = UserProfileManager.shared.userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = myName.isEmpty ? String(myUserID.prefix(8)) : myName
        let amOwner = isOwner(of: team)

        // Flag = teamID + displayName。displayName 变就重 push(刷新 zone 上的名字)。
        let pushedFlagKey = "team.selfPushed.\(teamID.uuidString).\(displayName)"
        let alreadyPushed = UserDefaults.standard.bool(forKey: pushedFlagKey)

        let member: TeamMember
        if let existing {
            existing.displayName = displayName
            // 老数据修正:如果 existing.id 跟持久化 memberID 不一致(老 random UUID),不强迁本地
            // (会断 SwiftData @Model 引用),只确保下次 push 用 stableMemberID
            member = existing
            if alreadyPushed { return /* 本地有 + zone 也已推 + 名字一致 → no-op */ }
        } else {
            member = TeamMember(
                id: stableMemberID,  // 用持久化 id,不再 UUID()
                teamID: teamID,
                userID: myUserID,
                displayName: displayName,
                email: "",
                role: amOwner ? .owner : .engineer
            )
            modelContext.insert(member)
        }
        try? modelContext.save()

        guard let zoneID = await resolveZoneID(for: team) else {
            logger.warning("ensureSelfMemberRecord SKIPPED — zone not resolved")
            return
        }
        let db = amOwner ? privateDB : sharedDB
        // **总是用 stableMemberID 推到 zone**(不用 member.id;老 existing.id 可能 ≠ stableMemberID)
        let recordID = CKRecord.ID(recordName: stableMemberID.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "SiteNoteTeamMember", recordID: recordID)
        record["memberID"] = stableMemberID.uuidString as CKRecordValue
        record["teamID"] = teamID.uuidString as CKRecordValue
        record["userID"] = myUserID as CKRecordValue
        record["displayName"] = displayName as CKRecordValue
        record["email"] = "" as CKRecordValue
        record["roleRaw"] = member.roleRaw as CKRecordValue
        record["joinedAt"] = member.joinedAt as CKRecordValue

        // 如果 existing.id ≠ stableMemberID,zone 里可能有老 id 的孤儿 record 在污染 owner 视图。
        // 这里把它同时删了。
        var staleIDsToDelete: [CKRecord.ID] = []
        if let existing, existing.id != stableMemberID {
            let staleRecordID = CKRecord.ID(recordName: existing.id.uuidString, zoneID: zoneID)
            staleIDsToDelete.append(staleRecordID)
            logger.info("ensureSelfMemberRecord deleting stale zone record: \(existing.id)")
        }

        do {
            _ = try await db.modifyRecords(saving: [record], deleting: staleIDsToDelete, savePolicy: .allKeys)
            UserDefaults.standard.set(true, forKey: pushedFlagKey)
            logger.info("ensureSelfMemberRecord pushed (\(amOwner ? "owner" : "member")): \(displayName)")
        } catch {
            logger.error("ensureSelfMemberRecord FAILED: \(error.localizedDescription)")
        }
    }

    /// 单条 CKRecord → upsert 进本地 SwiftData。按 record type dispatch。
    private func upsert(record: CKRecord, in modelContext: ModelContext) {
        switch record.recordType {
        case RT.sitePreset:
            upsertSitePreset(record: record, in: modelContext)
        case RT.schedule:
            upsertSchedule(record: record, in: modelContext)
        case RT.report:
            upsertReport(record: record, in: modelContext)
        case "SiteNoteTeam":
            upsertTeam(record: record, in: modelContext)
        case "SiteNoteTeamMember":
            upsertTeamMember(record: record, in: modelContext)
        default:
            break
        }
    }

    /// Owner 改了 team 名 / 加新 member 时,Member 端拉新变更。
    private func upsertTeam(record: CKRecord, in modelContext: ModelContext) {
        guard let teamIDString = record["teamID"] as? String,
              let teamID = UUID(uuidString: teamIDString),
              let name = record["name"] as? String,
              let ownerUserID = record["ownerUserID"] as? String else { return }
        let existing = try? modelContext.fetch(FetchDescriptor<Team>(
            predicate: #Predicate<Team> { $0.id == teamID }
        )).first
        if let existing {
            existing.name = name
            existing.ownerUserID = ownerUserID
        } else {
            let team = Team(id: teamID, name: name, ownerUserID: ownerUserID)
            modelContext.insert(team)
        }
    }

    /// Owner 加新 member 后,Member 端拉到新 TeamMember record → 本地 SwiftData
    /// 多一条,@Query teamMembers 自动更新,分配 UI 能看到新人。
    ///
    /// **防御**:userID="" 的占位 record(老 inviteMember 流程留下的孤儿)直接 skip,
    /// 避免本地出现"占位 + 真注册"两条同人 TeamMember。
    /// 同 userID 已有真 TeamMember(Member 自己 register 的)时,合并:
    /// - 优先保留 Member 自己 register 的那条(更权威 — userID 非空 + displayName 自填)
    /// - 占位的删
    private func upsertTeamMember(record: CKRecord, in modelContext: ModelContext) {
        guard let memberIDString = record["memberID"] as? String,
              let memberID = UUID(uuidString: memberIDString),
              let teamIDString = record["teamID"] as? String,
              let teamID = UUID(uuidString: teamIDString),
              let userID = record["userID"] as? String,
              let displayName = record["displayName"] as? String,
              let email = record["email"] as? String,
              let roleRaw = record["roleRaw"] as? String else { return }

        // 防御 1:占位 record (userID="") 直接 skip
        guard !userID.isEmpty else {
            logger.info("upsertTeamMember: skip placeholder record (empty userID) id=\(memberID)")
            return
        }

        // 防御 2:如果本地已有同 userID 的真 TeamMember(不同 memberID),清掉它
        // (避免同人多条 — 例如老 placeholder 用了 owner 输入的 displayName + 不同 id,后来
        //  Member 自己 register 了新 id;这一步清掉所有非当前 record 的同 userID 残留)
        let staleSameUser = try? modelContext.fetch(FetchDescriptor<TeamMember>(
            predicate: #Predicate<TeamMember> { $0.userID == userID && $0.teamID == teamID && $0.id != memberID }
        ))
        for stale in (staleSameUser ?? []) {
            modelContext.delete(stale)
        }

        let existing = try? modelContext.fetch(FetchDescriptor<TeamMember>(
            predicate: #Predicate<TeamMember> { $0.id == memberID }
        )).first
        if let existing {
            existing.displayName = displayName
            existing.email = email
            existing.roleRaw = roleRaw
            existing.userID = userID
        } else {
            let member = TeamMember(
                id: memberID,
                teamID: teamID,
                userID: userID,
                displayName: displayName,
                email: email,
                role: TeamRole(rawValue: roleRaw) ?? .engineer
            )
            modelContext.insert(member)
        }
    }

    private func upsertSitePreset(record: CKRecord, in modelContext: ModelContext) {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString) else { return }
        let existing = try? modelContext.fetch(FetchDescriptor<SitePreset>(
            predicate: #Predicate<SitePreset> { $0.id == id }
        )).first

        let target = existing ?? SitePreset(id: id)
        target.siteTag = record["siteTag"] as? String ?? ""
        target.projectName = record["projectName"] as? String ?? ""
        target.projectNo = record["projectNo"] as? String ?? ""
        target.clientName = record["clientName"] as? String ?? ""
        target.address = record["address"] as? String ?? ""
        target.defaultAttn = record["defaultAttn"] as? String ?? ""
        target.defaultInspectionType = record["defaultInspectionType"] as? String ?? ""
        target.notes = record["notes"] as? String ?? ""
        target.assignedToUserID = record["assignedToUserID"] as? String
        target.assignedAt = record["assignedAt"] as? Date
        if let idStrings = record["linkedContactIDs"] as? [String] {
            target.linkedContactIDs = idStrings.compactMap { UUID(uuidString: $0) }
        }
        if let idStrings = record["defaultRecipientIDs"] as? [String] {
            target.defaultRecipientIDs = idStrings.compactMap { UUID(uuidString: $0) }
        }
        target.updatedAt = record["updatedAt"] as? Date ?? Date()
        target.deletedAt = record["deletedAt"] as? Date

        if existing == nil {
            modelContext.insert(target)
        }
    }

    private func upsertSchedule(record: CKRecord, in modelContext: ModelContext) {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString) else { return }
        let existing = try? modelContext.fetch(FetchDescriptor<SiteVisitSchedule>(
            predicate: #Predicate<SiteVisitSchedule> { $0.id == id }
        )).first

        let target = existing ?? SiteVisitSchedule(id: id, scheduledDate: Date())
        target.scheduledDate = record["scheduledDate"] as? Date ?? Date()
        target.scheduledTime = record["scheduledTime"] as? Date
        target.siteTag = record["siteTag"] as? String
        target.title = record["title"] as? String ?? ""
        target.notes = record["notes"] as? String ?? ""
        target.statusRaw = record["statusRaw"] as? String ?? ScheduleStatus.pending.rawValue
        target.completedAt = record["completedAt"] as? Date
        target.assignedToUserID = record["assignedToUserID"] as? String
        if let linkedString = record["linkedReportID"] as? String {
            target.linkedReportID = UUID(uuidString: linkedString)
        }
        target.createdAt = record["createdAt"] as? Date ?? Date()
        target.deletedAt = record["deletedAt"] as? Date

        if existing == nil {
            modelContext.insert(target)
        }
    }

    private func upsertReport(record: CKRecord, in modelContext: ModelContext) {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString) else { return }
        let existing = try? modelContext.fetch(FetchDescriptor<InspectionReport>(
            predicate: #Predicate<InspectionReport> { $0.id == id }
        )).first

        // **Codex#4 关键修**:last-write-wins by updatedAt。
        // 之前无条件覆盖 → share zone 上 stale record(eg. token expired 重拉)会盖掉
        // 本地刚做的更新。这里若 cloud updatedAt <= 本地,跳过(保留本地版本)。
        // existing == nil 时永远 insert(没有本地版本可比)。
        if let existing,
           let cloudUpdatedAt = record["updatedAt"] as? Date,
           cloudUpdatedAt <= existing.updatedAt {
            logger.info("upsertReport: skip stale record id=\(id) cloud=\(cloudUpdatedAt) local=\(existing.updatedAt)")
            return
        }

        let target = existing ?? InspectionReport(id: id)
        target.reportNo = record["reportNo"] as? String ?? ""
        target.project = record["project"] as? String ?? ""
        target.projectNo = record["projectNo"] as? String ?? ""
        target.client = record["client"] as? String ?? ""
        target.location = record["location"] as? String ?? ""
        target.inspectionType = record["inspectionType"] as? String ?? ""
        target.attn = record["attn"] as? String ?? ""
        target.siteTag = record["siteTag"] as? String  // R6 新字段;老 record 没此字段 → nil
        target.engineerName = record["engineerName"] as? String ?? ""
        target.statusRaw = record["statusRaw"] as? String ?? InspectionStatus.draft.rawValue
        target.reportDate = record["reportDate"] as? Date ?? Date()
        target.submittedAt = record["submittedAt"] as? Date
        target.createdByUserID = record["createdByUserID"] as? String ?? ""
        if let idStrings = record["noteIDs"] as? [String] {
            target.noteIDs = idStrings.compactMap { UUID(uuidString: $0) }
        }
        // 团队协作:读 noteSnapshots 让 Owner 端跨账号 fetch 不到 Note 实体时,
        // 仍能从 noteSnapshotsJSON 拿 transcription / photoCount / siteTag。
        if let snapshotJSON = record["noteSnapshots"] as? String {
            target.noteSnapshotsJSON = snapshotJSON
        }
        // 保留 Member 端的真实创建时间(不被本地 init 的 Date() 覆盖),
        // 让 Owner 端 @Query `sort: \.createdAt` 排序正确。
        if let cloudCreatedAt = record["createdAt"] as? Date {
            target.createdAt = cloudCreatedAt
        }
        // **P0 R3#2**:fallback **不能用 Date()**(now)。
        // 老 cloud record 没 updatedAt 字段 → 用 now → 后续 cloud update 永远 <= now → LWW 永远 reject
        // → 这条 record 永久卡在老状态。改用 record.modificationDate(CloudKit 服务端时间戳),
        // 若也没有则 Date.distantPast。
        target.updatedAt = record["updatedAt"] as? Date
            ?? record.modificationDate
            ?? .distantPast
        target.deletedAt = record["deletedAt"] as? Date

        if existing == nil {
            modelContext.insert(target)
        }
    }

    /// CKRecord 被云端删 → 本地软删对应实体。
    /// preset / schedule / report 的 recordName 形如 `preset-<uuid>` 等 → 走 prefix 分支。
    /// TeamMember CKRecord 的 recordName 是纯 UUID(`<memberID.uuidString>`)→ fallback 在
    /// SwiftData 各表 fetch by id,匹配上的硬删(TeamMember 没 deletedAt 字段)。
    /// 这一步让 Owner 端 `cleanupDuplicateMembers` 删 zone 里孤儿后,Jamie 端下次 sync 能同步删本地。
    private func softDelete(recordID: CKRecord.ID, in modelContext: ModelContext) {
        let parts = recordID.recordName.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        let now = Date()
        if parts.count == 2, let id = UUID(uuidString: String(parts[1])) {
            switch String(parts[0]) {
            case "preset":
                if let p = try? modelContext.fetch(FetchDescriptor<SitePreset>(
                    predicate: #Predicate<SitePreset> { $0.id == id }
                )).first {
                    p.deletedAt = now
                }
                return
            case "schedule":
                if let s = try? modelContext.fetch(FetchDescriptor<SiteVisitSchedule>(
                    predicate: #Predicate<SiteVisitSchedule> { $0.id == id }
                )).first {
                    s.deletedAt = now
                }
                return
            case "report":
                if let r = try? modelContext.fetch(FetchDescriptor<InspectionReport>(
                    predicate: #Predicate<InspectionReport> { $0.id == id }
                )).first {
                    r.deletedAt = now
                }
                return
            default:
                break
            }
        }
        // Fallback:纯 UUID(TeamMember CKRecord 的 recordName)→ 试 fetch + 硬删
        if let memberID = UUID(uuidString: recordID.recordName),
           let m = try? modelContext.fetch(FetchDescriptor<TeamMember>(
               predicate: #Predicate<TeamMember> { $0.id == memberID }
           )).first {
            modelContext.delete(m)
            logger.info("softDelete: removed TeamMember \(memberID) (cloud deleted)")
        }
    }

    // MARK: - Server change token 持久化

    private func loadToken(key: String) -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveToken(_ token: CKServerChangeToken, key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// 清掉某 zone 的所有 server change token 形式(v1 legacy + v2 private + v2 shared + 任何未来变种)。
    /// **关键**:之前只删 `.v1`,新代码已切 `.<private|shared>.v2`,resetToken 不更新意味着
    /// 团队解散 / 离队后 token 还在,下次入团 / 重建 token 会撞旧值。这里用 prefix 扫确保全清。
    func resetToken(forZoneName zoneName: String) {
        let prefix = "team.serverChangeToken.\(zoneName)"
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
            logger.info("resetToken removed key: \(key)")
        }
    }

    /// 清掉该 team 在 UserDefaults 的所有本地缓存。
    /// 团队解散 / 离队 / nukeAllData 都调用 — 防止重新加入团队时老缓存污染:
    /// - `team.serverChangeToken.<zoneName>.*`(所有 token 变种)
    /// - `team.sharedZoneOwnerName.<zoneName>`(Member 端 share zone owner 缓存)
    /// - `team.selfMemberID.<teamID>`(自己的 stable member id)
    /// - `team.selfPushed.<teamID>.<displayName>`(所有 displayName 变种)
    func purgeTeamLocalCaches(teamID: UUID) {
        let zoneName = teamID.uuidString
        resetToken(forZoneName: zoneName)
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "team.sharedZoneOwnerName.\(zoneName)")
        defaults.removeObject(forKey: "team.selfMemberID.\(zoneName)")
        let pushedPrefix = "team.selfPushed.\(zoneName)."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(pushedPrefix) {
            defaults.removeObject(forKey: key)
        }
        logger.info("purgeTeamLocalCaches done for teamID=\(teamID)")
    }
}
