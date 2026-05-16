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

    /// Owner 端:在 CloudKit private DB 创建一个 Team zone + Team CKRecord + zone-wide CKShare。
    /// 返回的 CKShare 直接喂给 UICloudSharingController 弹邀请 UI。
    func createTeamOnCloud(team: Team) async throws -> (CKShare, CKContainer) {
        // 1. 检查 iCloud 状态
        let accountStatus = try await container.accountStatus()
        guard accountStatus == .available else {
            throw CloudKitError.iCloudNotAvailable
        }

        // 2. 创建 custom zone(zoneName = team.id.uuidString)
        let zoneID = CKRecordZone.ID(zoneName: team.id.uuidString, ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)

        do {
            _ = try await privateDB.modifyRecordZones(saving: [zone], deleting: [])
        } catch {
            logger.error("Zone creation failed: \(error.localizedDescription)")
            throw CloudKitError.zoneCreationFailed(error.localizedDescription)
        }

        // 3. 创建 Team CKRecord(放在新 zone 的固定 recordID "root")
        let teamRecordID = CKRecord.ID(recordName: "root", zoneID: zoneID)
        let teamRecord = CKRecord(recordType: RecordType.team, recordID: teamRecordID)
        teamRecord["teamID"] = team.id.uuidString as CKRecordValue
        teamRecord["name"] = team.name as CKRecordValue
        teamRecord["ownerUserID"] = team.ownerUserID as CKRecordValue
        teamRecord["createdAt"] = team.createdAt as CKRecordValue

        // 4. 创建 zone-wide CKShare(rootRecord = Team CKRecord)
        let share = CKShare(rootRecord: teamRecord)
        share[CKShare.SystemFieldKey.title] = team.name as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "com.banruo.SiteNote.team" as CKRecordValue
        share.publicPermission = .none  // 必须显式邀请

        // 5. 一次性写两个 records(team + share)
        do {
            _ = try await privateDB.modifyRecords(saving: [teamRecord, share], deleting: [])
        } catch {
            logger.error("Save team+share failed: \(error.localizedDescription)")
            throw CloudKitError.shareCreationFailed(error.localizedDescription)
        }

        // 6. 把 share recordName 存回本地 Team(用于以后拉 CKShare 状态)
        team.cloudShareRecordName = share.recordID.recordName

        logger.info("Team created on cloud: zone=\(zoneID.zoneName) shareID=\(share.recordID.recordName)")
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
            _ = try await privateDB.modifyRecords(saving: [record], deleting: [])
        } catch {
            logger.error("Add member failed: \(error.localizedDescription)")
            throw CloudKitError.recordOperationFailed(error.localizedDescription)
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

        // 2. 拉 shared DB 这个 zone 的所有 records
        let zoneID = metadata.share.recordID.zoneID
        let recordsToFetch: [CKRecord]
        do {
            let result = try await sharedDB.records(matching: CKQuery(
                recordType: RecordType.team,
                predicate: NSPredicate(value: true)
            ), inZoneWith: zoneID)
            let teamRecords = result.matchResults.compactMap { try? $0.1.get() }

            let memberResult = try await sharedDB.records(matching: CKQuery(
                recordType: RecordType.teamMember,
                predicate: NSPredicate(value: true)
            ), inZoneWith: zoneID)
            let memberRecords = memberResult.matchResults.compactMap { try? $0.1.get() }

            recordsToFetch = teamRecords + memberRecords
        } catch {
            logger.error("Fetch shared records failed: \(error.localizedDescription)")
            throw CloudKitError.acceptShareFailed(error.localizedDescription)
        }

        // 3. 在本地 SwiftData 创建 mirror
        for record in recordsToFetch {
            switch record.recordType {
            case RecordType.team:
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

        try? modelContext.save()
        logger.info("Accepted share for zone=\(zoneID.zoneName), synced \(recordsToFetch.count) records")
    }

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
