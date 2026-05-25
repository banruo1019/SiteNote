//
//  TeamCloudKitService.swift
//  SiteNote
//
//  Team / TeamMember 的跨用户共享通过 raw CloudKit + CKShare 实现。
//  本地 SwiftData 只作缓存,所有"接通团队"的实际网络操作走这里。
//
//  ## 架构
//
//  每个 Team 对应一个 **custom CKRecordZone**(zoneName = Team.id.uuidString):
//    - Team CKRecord(recordType "CD_Team") at recordID(name="root", zone=teamZone)
//    - TeamMember CKRecord(recordType "CD_TeamMember") at recordID(name=member.id, zone=teamZone)
//    - **zone-level CKShare**(rootRecord = Team CKRecord)
//
//  Owner 创建团队:
//    1. createCustomZone(zoneID)
//    2. 创建 Team CKRecord + CKShare(rootRecord=Team)
//    3. modifyRecords 一次性写两个 records
//    4. 把 CKShare.url 给 UICloudSharingController 弹邀请
//
//  Member 接受邀请:
//    1. iCloud 邀请 link → 系统弹 sheet → 用户点接受
//    2. App 收到 userDidAcceptCloudKitShareWith(metadata)(AppDelegate)
//    3. CKAcceptSharesOperation 接受 share
//    4. 拉 shared DB 的 zone 里所有 records
//    5. 在本地 SwiftData 创建 Team + TeamMember mirror
//
//  ## 局限
//
//  - 需要 Apple Developer 后台 CloudKit container 已配置(✅ 已配)
//  - 双方都要登 iCloud
//  - 网络断开时操作排队但 best effort,失败抛 CloudKitError
//

import Foundation
import CloudKit
import SwiftData
import os

@MainActor
final class TeamCloudKitService {
    static let shared = TeamCloudKitService()
    private init() {}

    private let logger = Logger(subsystem: "com.banruo.sitenote", category: "TeamCloudKit")

    /// 同 ICloudSyncConfig.containerID。
    private static let containerID = "iCloud.com.banruo.SiteNote"

    private var container: CKContainer {
        CKContainer(identifier: Self.containerID)
    }
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    // MARK: - CloudKit record types
    // SwiftData 内部把 @Model 对应到 CD_<ClassName>,我们自己管的 record 用独立 type 避免和 SwiftData 冲突。
    enum RecordType {
        static let team = "SiteNoteTeam"
        static let teamMember = "SiteNoteTeamMember"
    }

    enum CloudKitError: LocalizedError {
        case iCloudNotAvailable
        case zoneCreationFailed(String)
        case shareCreationFailed(String)
        case recordOperationFailed(String)
        case acceptShareFailed(String)

        var errorDescription: String? {
            switch self {
            case .iCloudNotAvailable:
                return String(localized: "iCloud 未登录或不可用。请在 设置 → Apple ID 登录后重试。", locale: AppLanguageManager.currentLocale)
            case .zoneCreationFailed(let s):
                return String(localized: "创建团队 zone 失败:\(s)", locale: AppLanguageManager.currentLocale)
            case .shareCreationFailed(let s):
                return String(localized: "创建分享失败:\(s)", locale: AppLanguageManager.currentLocale)
            case .recordOperationFailed(let s):
                return String(localized: "云端操作失败:\(s)", locale: AppLanguageManager.currentLocale)
            case .acceptShareFailed(let s):
                return String(localized: "接受邀请失败:\(s)", locale: AppLanguageManager.currentLocale)
            }
        }
    }

    // MARK: - Owner:创建团队

    /// Owner 端:在 CloudKit private DB 创建一个 Team zone + **zone-wide** CKShare + Team CKRecord。
    /// 返回的 CKShare 直接喂给 UICloudSharingController 弹邀请 UI。
    ///
    /// **关键**:用 `CKShare(recordZoneID:)` 创建 **zone-wide share**(iOS 15+),不是
    /// `CKShare(rootRecord:)` single-record share。这样整个 zone 里的所有 records
    /// (TeamMember / SitePreset / Schedule / Report)Member 端都能拉到 + 写入。
    /// 之前用 single-record share → Member 只能拉到 Team 那一条,其它全看不到 →
    /// 这是 owner 看不到 member、member 看不到分配的根因。
    func createTeamOnCloud(team: Team) async throws -> (CKShare, CKContainer) {
        // 1. 检查 iCloud 状态
        let accountStatus = try await container.accountStatus()
        guard accountStatus == .available else {
            throw CloudKitError.iCloudNotAvailable
        }

        // 2. 创建 custom zone(zoneName = team.id.uuidString)。zone-wide share 必须
        // 跑在 custom zone(default zone 不支持)。
        let zoneID = CKRecordZone.ID(zoneName: team.id.uuidString, ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)

        do {
            _ = try await privateDB.modifyRecordZones(saving: [zone], deleting: [])
        } catch {
            logger.error("Zone creation failed: \(error.localizedDescription)")
            throw CloudKitError.zoneCreationFailed(error.localizedDescription)
        }

        // 3. 创建 **zone-wide** CKShare。recordName 固定 = CKRecordNameZoneWideShare。
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = team.name as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "com.banruo.SiteNote.team" as CKRecordValue
        share.publicPermission = .none  // 必须显式邀请

        // 4. 先单独保存 share(zone-wide share 必须先 save 才能往 zone 里写其它 records)。
        do {
            _ = try await privateDB.modifyRecords(saving: [share], deleting: [], savePolicy: .allKeys)
        } catch {
            logger.error("Save zone-wide share failed: \(error.localizedDescription)")
            throw CloudKitError.shareCreationFailed(error.localizedDescription)
        }

        // 5. 接着写 Team CKRecord 进 zone(放在固定 recordID "root")
        let teamRecordID = CKRecord.ID(recordName: "root", zoneID: zoneID)
        let teamRecord = CKRecord(recordType: RecordType.team, recordID: teamRecordID)
        teamRecord["teamID"] = team.id.uuidString as CKRecordValue
        teamRecord["name"] = team.name as CKRecordValue
        teamRecord["ownerUserID"] = team.ownerUserID as CKRecordValue
        teamRecord["createdAt"] = team.createdAt as CKRecordValue
        do {
            _ = try await privateDB.modifyRecords(saving: [teamRecord], deleting: [], savePolicy: .allKeys)
        } catch {
            logger.error("Save team record failed: \(error.localizedDescription)")
            _ = try? await privateDB.modifyRecordZones(saving: [], deleting: [zoneID])
            throw CloudKitError.recordOperationFailed(error.localizedDescription)
        }

        // 6. 把 share recordName 存回本地 Team(用于以后拉 CKShare 状态)
        team.cloudShareRecordName = share.recordID.recordName

        logger.info("Team created on cloud: zone=\(zoneID.zoneName) zone-wide-share=\(share.recordID.recordName)")
        return (share, container)
    }

    // MARK: - Owner:同步 Member 到 cloud

    /// Owner 添加 TeamMember 时调用(本地 SwiftData 创建后再 push 到云)。
    func addMemberOnCloud(member: TeamMember) async throws {
        let zoneID = CKRecordZone.ID(zoneName: member.teamID.uuidString, ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: member.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: RecordType.teamMember, recordID: recordID)
        record["memberID"] = member.id.uuidString as CKRecordValue
        record["teamID"] = member.teamID.uuidString as CKRecordValue
        record["userID"] = member.userID as CKRecordValue
        record["displayName"] = member.displayName as CKRecordValue
        record["email"] = member.email as CKRecordValue
        record["roleRaw"] = member.roleRaw as CKRecordValue
        record["joinedAt"] = member.joinedAt as CKRecordValue

        do {
            _ = try await privateDB.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        } catch {
            logger.error("Add member failed: \(error.localizedDescription)")
            throw CloudKitError.recordOperationFailed(error.localizedDescription)
        }
    }

    // MARK: - Owner:移除单个成员

    /// 删除 zone 里指定 TeamMember CKRecord(memberID 对应 recordName)。Member 端下次
    /// fetchAndSyncAll 拉 deletions 时会触发 softDelete fallback 删本地。
    ///
    /// **限制**:删 record 只是清"成员名单",**并不撤销 share 访问权**。
    /// Member 实际还能通过 sharedDB 看到 share zone 的其它 record。
    /// 撤销 share access 必须额外调 `tryRevokeShareParticipant(...)`(见下)。
    func removeMemberOnCloud(member: TeamMember) async throws {
        let zoneID = CKRecordZone.ID(zoneName: member.teamID.uuidString, ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: member.id.uuidString, zoneID: zoneID)
        do {
            _ = try await privateDB.modifyRecords(saving: [], deleting: [recordID], savePolicy: .allKeys)
            logger.info("removeMemberOnCloud OK: \(member.displayName) (\(member.id))")
        } catch {
            logger.error("removeMemberOnCloud failed: \(error.localizedDescription)")
            throw CloudKitError.recordOperationFailed(error.localizedDescription)
        }
    }

    /// 尝试从 CKShare 的 participants 列表里撤销该 userID 对应的 share access。
    ///
    /// **真实限制 — 必须告诉用户**:
    /// CKShare.participants 是只读 snapshot。要"撤销" share 必须:
    /// 1. fetch CKShare from privateDB
    /// 2. 找到 share.participants 里 userID 匹配的 CKShare.Participant
    /// 3. share.removeParticipant(p)
    /// 4. privateDB.modifyRecords([share])
    ///
    /// 即便上面流程跑通,iOS / iCloud 端**移除生效有延迟**(几分钟到几小时),
    /// 且 Member 设备本地的 sharedDB cache 在他主动 fetch 前看上去还是有 access。
    /// 失败不抛 — 调用方只用 record 删除作为软撤销。
    ///
    /// 返回 true 表示 modifyRecords 成功(不保证 iCloud 端立即生效)。
    @discardableResult
    func tryRevokeShareParticipant(team: Team, memberUserID: String) async -> Bool {
        guard let shareName = team.cloudShareRecordName else {
            logger.warning("tryRevokeShareParticipant SKIPPED — team.cloudShareRecordName nil")
            return false
        }
        let zoneID = CKRecordZone.ID(zoneName: team.id.uuidString, ownerName: CKCurrentUserDefaultName)
        let shareID = CKRecord.ID(recordName: shareName, zoneID: zoneID)
        do {
            guard let share = try await privateDB.record(for: shareID) as? CKShare else {
                logger.warning("tryRevokeShareParticipant: share record not CKShare type")
                return false
            }
            let target = share.participants.first { participant in
                participant.userIdentity.userRecordID?.recordName == memberUserID
            }
            guard let target else {
                logger.info("tryRevokeShareParticipant: no matching participant for userID=\(memberUserID)")
                return false
            }
            share.removeParticipant(target)
            _ = try await privateDB.modifyRecords(saving: [share], deleting: [], savePolicy: .allKeys)
            logger.info("tryRevokeShareParticipant OK: removed \(memberUserID)")
            return true
        } catch {
            logger.error("tryRevokeShareParticipant failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Owner:解散团队

    /// 删除整个 zone(连带 CKShare、所有 records)。本地 SwiftData 由调用方负责清。
    func deleteTeamZoneOnCloud(team: Team) async throws {
        let zoneID = CKRecordZone.ID(zoneName: team.id.uuidString, ownerName: CKCurrentUserDefaultName)
        do {
            _ = try await privateDB.modifyRecordZones(saving: [], deleting: [zoneID])
        } catch {
            logger.error("Delete zone failed: \(error.localizedDescription)")
            throw CloudKitError.recordOperationFailed(error.localizedDescription)
        }
    }

    // MARK: - Member:接受邀请

    /// SceneDelegate / AppDelegate 收到 share invitation 时调用。
    /// 接受 share → 拉 zone 里所有 records → 在本地 SwiftData 创建 mirror。
    /// 调用方需要传 SwiftData 的 ModelContext 才能写本地缓存。
    func acceptShareInvitation(
        metadata: CKShare.Metadata,
        modelContext: ModelContext
    ) async throws {
        // 1. 接受 share
        do {
            _ = try await container.accept(metadata)
        } catch {
            logger.error("Accept share failed: \(error.localizedDescription)")
            throw CloudKitError.acceptShareFailed(error.localizedDescription)
        }

        // 2. 拉 shared DB 这个 zone 的所有 records。
        // **不用 CKQuery + NSPredicate(value: true)** — 这会触发对 recordName 的索引查询,
        // 而新 record type 的 recordName 字段默认 **not queryable**(CloudKit Dashboard 才能加
        // queryable index,纯代码改不了)。报错:"Field 'recordName' is not marked queryable"。
        // 用 `recordZoneChanges(inZoneWith:since:)` 拉 zone 全量 changes,不依赖任何 queryable
        // index,这是 CKShare 场景 Apple 推荐 API。
        let zoneID = metadata.share.recordID.zoneID
        // **关键**:把 metadata 给出的 zone ownerName 立即缓存。这是 Member Container 视角下
        // 真正的 share zone owner identity。后续 fetchAndSyncAll / mirrorXxx 用它构造 zoneID,
        // 不再用 team.ownerUserID 反推(那个值是 Owner Container 视角写的,跨账号场景下可能不
        // 等于 Member 看到的)。这是之前 Member 端 fetchAndSyncAll "拉到 0 条" 的根因。
        UserDefaults.standard.set(
            zoneID.ownerName,
            forKey: "team.sharedZoneOwnerName.\(zoneID.zoneName)"
        )
        let recordsToFetch: [CKRecord]
        do {
            let changes = try await sharedDB.recordZoneChanges(inZoneWith: zoneID, since: nil)
            recordsToFetch = changes.modificationResultsByID.values.compactMap {
                try? $0.get().record
            }
        } catch {
            logger.error("Fetch shared records failed: \(error.localizedDescription)")
            throw CloudKitError.acceptShareFailed(error.localizedDescription)
        }

        // 3. 在本地 SwiftData 创建 mirror
        var sawTeamRecord = false
        for record in recordsToFetch {
            switch record.recordType {
            case RecordType.team:
                sawTeamRecord = true
                if let teamIDString = record["teamID"] as? String,
                   let teamID = UUID(uuidString: teamIDString),
                   let name = record["name"] as? String,
                   let ownerUserID = record["ownerUserID"] as? String {
                    // 检查本地是否已有
                    let existing = try? modelContext.fetch(FetchDescriptor<Team>(
                        predicate: #Predicate<Team> { $0.id == teamID }
                    )).first
                    if existing == nil {
                        let team = Team(id: teamID, name: name, ownerUserID: ownerUserID)
                        team.cloudShareRecordName = metadata.share.recordID.recordName
                        modelContext.insert(team)
                    } else if existing?.cloudShareRecordName == nil {
                        existing?.cloudShareRecordName = metadata.share.recordID.recordName
                    }
                }
            case RecordType.teamMember:
                if let memberIDString = record["memberID"] as? String,
                   let memberID = UUID(uuidString: memberIDString),
                   let teamIDString = record["teamID"] as? String,
                   let teamID = UUID(uuidString: teamIDString),
                   let userID = record["userID"] as? String,
                   let displayName = record["displayName"] as? String,
                   let email = record["email"] as? String,
                   let roleRaw = record["roleRaw"] as? String {
                    let existing = try? modelContext.fetch(FetchDescriptor<TeamMember>(
                        predicate: #Predicate<TeamMember> { $0.id == memberID }
                    )).first
                    if existing == nil {
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
            default:
                break
            }
        }

        // 老版本可能创建了 zone-wide share,但 root Team CKRecord 没写成功。
        // Member 接受后仍然能看到 shared zone,但本地没有 Team 时 fetchAndSyncAll 会直接跳过。
        // 这里用 zoneName(team UUID) + share title 做一个 fallback Team cache,让后续报告全量拉取继续跑。
        if !sawTeamRecord,
           let teamID = UUID(uuidString: zoneID.zoneName) {
            let existing = try? modelContext.fetch(FetchDescriptor<Team>(
                predicate: #Predicate<Team> { $0.id == teamID }
            )).first
            if existing == nil {
                let rawTitle = metadata.share[CKShare.SystemFieldKey.title] as? String
                let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                let team = Team(
                    id: teamID,
                    name: (title?.isEmpty == false ? title! : "Shared Team"),
                    ownerUserID: zoneID.ownerName
                )
                team.cloudShareRecordName = metadata.share.recordID.recordName
                modelContext.insert(team)
                logger.warning("Accepted share without root Team record; created fallback local Team for zone=\(zoneID.zoneName)")
            } else if existing?.cloudShareRecordName == nil {
                existing?.cloudShareRecordName = metadata.share.recordID.recordName
            }
        }

        try? modelContext.save()
        logger.info("Accepted share for zone=\(zoneID.zoneName), synced \(recordsToFetch.count) records")
        // 接受 share 后立即拉一次 zone changes,把 SitePreset/Schedule/Report 也同步进来(首次全量)。
        // fetchAndSyncAll 末尾的 ensureSelfMemberRecord 会自动把 Member 自己 push 到 share zone,
        // 不需要再单独调老的 registerSelfAsMember(已删,以免 double push 引起 etag 冲突)。
        await TeamDataMirrorService.shared.fetchAndSyncAll(in: modelContext, forceFullSync: true)
    }

    // (v1.6: registerSelfAsMember 已被 TeamDataMirrorService.ensureSelfMemberRecord 取代,
    //  扔了避免 double push 引起 etag 冲突)

    // MARK: - 用户身份缓存

    /// 当前用户的 CKUserIdentity recordName(用于 isOwner 判断)。
    /// 第一次访问时网络拉取并缓存到 ICloudSyncConfig。
    func fetchCurrentUserRecordName() async throws -> String {
        if let cached = ICloudSyncConfig.shared.currentUserRecordName {
            return cached
        }
        let recordID = try await container.userRecordID()
        ICloudSyncConfig.shared.currentUserRecordName = recordID.recordName
        return recordID.recordName
    }
}
