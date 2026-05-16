//
//  Team.swift
//  SiteNote
//
//  公司团队 model。用户决策(2026-05-16):第一版免费 / 最大 10 人 /
//  member 默认可看全部 / 离队数据归公司。
//
//  ⚠️ **设计教训**(v1.2 phase 2 那次崩):
//  Team / TeamMember 之间**不使用 @Relationship 双向引用** —— 上次崩的根因是
//  `@Relationship(deleteRule:.cascade, inverse:\TeamMember.team)` 跨 @Model
//  cycle 在 v1.0 → v1.2 lightweight migration 时,CoreData/CloudKit 层
//  解析失败。
//
//  改用 `teamID: UUID` 软引用 + 查询时手动 join。代价是 cascade delete 要
//  自己写一行(`TeamSharingService.dissolveTeam` 里),收益是 schema migration
//  100% 安全 + CloudKit 友好。
//
//  CloudKit 要求:所有非可选属性必须有 default value(在声明处提供)。
//

import Foundation
import SwiftData

@Model
final class Team {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    /// CKRecord.creatorUserRecordID(Apple ID,team 创建者)。
    var ownerUserID: String = ""
    var createdAt: Date = Date()
    var deletedAt: Date?

    /// CloudKit CKShare 的 recordID。Owner 创建团队时填,Member 接受邀请后也填(用于查回 CKShare)。
    var cloudShareRecordName: String?

    init(id: UUID = UUID(), name: String = "", ownerUserID: String = "") {
        self.id = id
        self.name = name
        self.ownerUserID = ownerUserID
        self.createdAt = Date()
    }

    /// 当前用户是否 Owner。
    func isOwner(currentUserID: String) -> Bool {
        return currentUserID == ownerUserID
    }

    /// 团队最大人数。
    static let maxMembers: Int = 10

    /// 查询此团队的所有 member(替代之前的 @Relationship)。
    /// - Parameter context: SwiftData 上下文。
    func members(in context: ModelContext) -> [TeamMember] {
        let teamID = self.id
        let descriptor = FetchDescriptor<TeamMember>(
            predicate: #Predicate<TeamMember> { $0.teamID == teamID }
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}

@Model
final class TeamMember {
    @Attribute(.unique) var id: UUID = UUID()

    /// 属于哪个团队(软引用替代 @Relationship)。
    var teamID: UUID = UUID()

    /// Apple ID(CKUserIdentity.userRecordID.recordName)。同人多设备共享一个 userID。
    var userID: String = ""
    var displayName: String = ""
    var email: String = ""
    var roleRaw: String = TeamRole.engineer.rawValue
    var joinedAt: Date = Date()

    var role: TeamRole {
        get { TeamRole(rawValue: roleRaw) ?? .engineer }
        set { roleRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        teamID: UUID = UUID(),
        userID: String = "",
        displayName: String = "",
        email: String = "",
        role: TeamRole = .engineer
    ) {
        self.id = id
        self.teamID = teamID
        self.userID = userID
        self.displayName = displayName
        self.email = email
        self.roleRaw = role.rawValue
        self.joinedAt = Date()
    }
}

/// 团队角色(三档,对应 CKShare 的 owner / private user / public user 概念)。
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
