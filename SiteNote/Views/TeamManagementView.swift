//
//  TeamManagementView.swift
//  SiteNote
//
//  团队管理主页面(Owner / Member 两视角)。
//
//  ⚠️ Phase 0(2026-05-16):UI shell + mock data。
//  Phase 2(Team / TeamMember 接入主 Schema)后才能持久化。
//  Phase 2 实际 CloudKit Sharing 通过 CloudSharingControllerWrapper 接通。
//

import SwiftUI

struct TeamManagementView: View {
    /// Mock 模式的 team(Phase 0)。Phase 2 改成 @Query Team。
    @State private var mockTeam: Team? = nil
    @State private var mockMembers: [TeamMember] = []
    @State private var currentUserID: String = "mock-user-self"

    @State private var showsCreateTeam = false
    @State private var showsInvite = false
    @State private var showsLeaveConfirm = false

    var body: some View {
        Form {
            if let team = mockTeam {
                teamHeader(team)
                membersSection(team)
                actionsSection(team)
            } else {
                createSection
            }
        }
        .industrialForm()
        .navigationTitle(String(localized: "团队", locale: AppLanguageManager.currentLocale))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsCreateTeam) {
            CreateTeamSheet(onCreate: { name in
                mockTeam = Team(name: name, ownerUserID: currentUserID)
                mockMembers = [
                    TeamMember(userID: currentUserID, displayName: "我", email: "me@example.com", role: .owner)
                ]
                showsCreateTeam = false
            })
        }
        .sheet(isPresented: $showsInvite) {
            InviteMemberSheet(currentCount: mockMembers.count, onInvite: { name, email in
                let m = TeamMember(userID: UUID().uuidString, displayName: name, email: email, role: .engineer)
                mockMembers.append(m)
                showsInvite = false
            })
        }
        .alert(String(localized: "离开团队?", locale: AppLanguageManager.currentLocale), isPresented: $showsLeaveConfirm) {
            Button(String(localized: "取消", locale: AppLanguageManager.currentLocale), role: .cancel) {}
            Button(String(localized: "离开", locale: AppLanguageManager.currentLocale), role: .destructive) {
                mockTeam = nil
                mockMembers = []
            }
        } message: {
            Text(String(localized: "你的数据会留在团队(归公司),你将无法再访问。", locale: AppLanguageManager.currentLocale))
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func teamHeader(_ team: Team) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Ink.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name)
                        .font(.system(size: 18, weight: .semibold))
                    Text(String(localized: "\(mockMembers.count) / \(Team.maxMembers) 成员", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func membersSection(_ team: Team) -> some View {
        Section(String(localized: "成员", locale: AppLanguageManager.currentLocale)) {
            ForEach(mockMembers) { member in
                memberRow(member, isOwner: team.isOwner(currentUserID: currentUserID))
            }
            if team.isOwner(currentUserID: currentUserID),
               mockMembers.count < Team.maxMembers {
                Button {
                    showsInvite = true
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundStyle(.tint)
                        Text(String(localized: "邀请成员", locale: AppLanguageManager.currentLocale))
                            .foregroundStyle(.primary)
                    }
                }
            } else if mockMembers.count >= Team.maxMembers {
                Text(String(localized: "已达 \(Team.maxMembers) 人上限", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func memberRow(_ member: TeamMember, isOwner: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: member.role == .owner ? "crown.fill" : "person.fill")
                .foregroundStyle(member.role == .owner ? Ink.accent : .secondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    Text(member.role.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Ink.card)
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)
                }
                Text(member.email)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if isOwner && member.role != .owner {
                Button {
                    if let idx = mockMembers.firstIndex(where: { $0.id == member.id }) {
                        mockMembers.remove(at: idx)
                    }
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Ink.red)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func actionsSection(_ team: Team) -> some View {
        Section {
            if team.isOwner(currentUserID: currentUserID) {
                Button(role: .destructive) {
                    mockTeam = nil
                    mockMembers = []
                } label: {
                    Text(String(localized: "解散团队", locale: AppLanguageManager.currentLocale))
                }
            } else {
                Button(role: .destructive) {
                    showsLeaveConfirm = true
                } label: {
                    Text(String(localized: "离开团队", locale: AppLanguageManager.currentLocale))
                }
            }
        } footer: {
            Text(String(localized: "第一版免费;最大 10 人;member 默认可看团队全部;离队数据归公司。", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 11))
        }
    }

    @ViewBuilder
    private var createSection: some View {
        Section {
            Button {
                showsCreateTeam = true
            } label: {
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "创建团队", locale: AppLanguageManager.currentLocale))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(String(localized: "和你的工程师 / 老板一起协作", locale: AppLanguageManager.currentLocale))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(String(localized: "你还没有团队", locale: AppLanguageManager.currentLocale))
        } footer: {
            Text(String(localized: "第一版免费。创建后可邀请最多 9 个成员(共 10 人,含你自己)。", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 11))
        }
    }
}

// MARK: - 创建团队 sheet

private struct CreateTeamSheet: View {
    let onCreate: (String) -> Void
    @State private var name: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "团队名称", locale: AppLanguageManager.currentLocale)) {
                    TextField(String(localized: "如 ABC Engineering", locale: AppLanguageManager.currentLocale), text: $name)
                }
            }
            .navigationTitle(String(localized: "新建团队", locale: AppLanguageManager.currentLocale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", locale: AppLanguageManager.currentLocale)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "创建", locale: AppLanguageManager.currentLocale)) {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onCreate(trimmed)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 邀请成员 sheet

private struct InviteMemberSheet: View {
    let currentCount: Int
    let onInvite: (String, String) -> Void
    @State private var name: String = ""
    @State private var email: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "成员信息", locale: AppLanguageManager.currentLocale)) {
                    TextField(String(localized: "姓名", locale: AppLanguageManager.currentLocale), text: $name)
                    TextField(String(localized: "iCloud 邮箱", locale: AppLanguageManager.currentLocale), text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                Section {} footer: {
                    Text(String(localized: "通过 iCloud 邀请。对方需用同一 Apple ID 登录 SiteNote 接受邀请。当前 \(currentCount) / \(Team.maxMembers) 成员。", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 11))
                }
            }
            .navigationTitle(String(localized: "邀请成员", locale: AppLanguageManager.currentLocale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", locale: AppLanguageManager.currentLocale)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "发送邀请", locale: AppLanguageManager.currentLocale)) {
                        onInvite(name.trimmingCharacters(in: .whitespacesAndNewlines),
                                 email.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(name.isEmpty || !email.contains("@"))
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack {
        TeamManagementView()
    }
}
