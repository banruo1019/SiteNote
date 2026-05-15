//
//  TeamPermissions.swift
//  SiteNote
//
//  团队角色权限检查。
//
//  规则(2026-05-16 用户决定):
//  - Owner:看全部 / 分配 / 邀请 / 改任何报告
//  - Lead:看团队全部,只能改自己的
//  - Engineer:看自己创建的 + 分配给自己的工地的报告
//  - 但用户也说 "member 默认可以看团队全部" — 所以 engineer 默认也能看,只是不能改别人的。
//

import Foundation

enum TeamPermissions {
    /// 当前用户是否能看到这份报告。
    /// (用户决定:member 默认可看全部,所以这里都返回 true。后续如果要限制,改这里。)
    static func canView(reportCreatedBy creatorID: String, currentUserID: String, role: TeamRole) -> Bool {
        return true  // 用户决定:全部可见
    }

    /// 当前用户是否能修改这份报告。
    /// Owner 全能改;Lead 只改自己的;Engineer 只改自己的。
    static func canEdit(reportCreatedBy creatorID: String, currentUserID: String, role: TeamRole) -> Bool {
        if role == .owner { return true }
        return creatorID == currentUserID
    }

    /// 当前用户能否分配工地/日程给别人(只有 Owner)。
    static func canAssign(role: TeamRole) -> Bool {
        return role == .owner
    }

    /// 当前用户能否邀请新成员(只有 Owner)。
    static func canInviteMember(role: TeamRole) -> Bool {
        return role == .owner
    }

    /// 当前用户能否移除其他成员(只有 Owner,且不能移除自己)。
    static func canRemoveMember(targetUserID: String, currentUserID: String, role: TeamRole) -> Bool {
        return role == .owner && targetUserID != currentUserID
    }
}
