//
//  Team.swift
//  SiteNote
//
//  公司团队 model — 用户已决定(2026-05-16):第一版免费 / 最大 10 人 / member 默认可看全部 / 离队数据归公司。
//
//  ⚠️ Phase 0:此文件存在但**未加入 SiteNoteApp 的 ModelContainer Schema**。
//  Phase 1(iCloud 备份)完成后,会通过 ICloudSyncConfig 切换 schema 启用。
//  在此之前,所有 Team / TeamMember 操作只能在 mock 模式下走 UI 流程。
//

import Foundation
import SwiftData

@Model
final class Team {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var ownerUserID: String = ""        // CKRecord.creatorUserRecordID(Apple ID)
    var createdAt: Date = Date()
    var deletedAt: Date?

    /// CloudKit CKShare 的 recordID,Phase 2 接通后填。
    var cloudShareRecordName: String?

    @Relationship(deleteRule: .cascade, inverse: \TeamMember.team)
    var members: [TeamMember] = []

    init(id: UUID = UUID(), name: String = "", ownerUserID: String = "") {
        self.id = id
        self.name = name
        self.ownerUserID = ownerUserID
        self.createdAt = Date()
    }

    /// 当前用户是否 Owner(对比 ownerUserID 和当前 Apple ID)。
    func isOwner(currentUserID: String) -> Bool {
        return currentUserID == ownerUserID
    }

    /// 团队最大人数(用户决定:10)。超过此数 UI 阻止邀请。
    static let maxMembers: Int = 10
}

@Model
final class TeamMember {
    @Attribute(.unique) var id: UUID = UUID()
    /// Apple ID(CKUserIdentity.userRecordID.recordName)。
    /// 同人多设备共享一个 userID。
    var userID: String = ""
    var displayName: String = ""
    var email: String = ""
    var roleRaw: String = TeamRole.engineer.rawValue
    var joinedAt: Date = Date()

    /// 反向引用 Team(由 Team.members 的 inverse 自动维护)。
    var team: Team?

    var role: TeamRole {
        get { TeamRole(rawValue: roleRaw) ?? .engineer }
        set { roleRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        userID: String = "",
        displayName: String = "",
        email: String = "",
        role: TeamRole = .engineer
    ) {
        self.id = id
        self.userID = userID
        self.displayName = displayName
        self.email = email
        self.roleRaw = role.rawValue
        self.joinedAt = Date()
    }
}

/// 团队角色(三档,对应 CKShare 自带的概念)。
enum TeamRole: String, Codable, CaseIterable {
    case owner
    case lead
    case engineer

    var displayName: String {
        switch self {
        case .owner: return String(localized: "Owner", locale: AppLanguageManager.currentLocale)
        case .lead: return String(localized: "Lead", locale: AppLanguageManager.currentLocale)
        case .engineer: return String(localized: "Engineer", locale: AppLanguageManager.currentLocale)
        }
    }

    var description: String {
        switch self {
        case .owner:
            return String(localized: "可邀请 / 移除成员、分配工地、看全部报告", locale: AppLanguageManager.currentLocale)
        case .lead:
            return String(localized: "可看团队全部、只能改自己的报告", locale: AppLanguageManager.currentLocale)
        case .engineer:
            return String(localized: "看自己的报告 + 分配给自己的工地", locale: AppLanguageManager.currentLocale)
        }
    }
}
