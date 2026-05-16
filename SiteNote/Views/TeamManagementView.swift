//
//  TeamManagementView.swift
//  SiteNote
//
//  团队管理主页面。
//
//  数据流:
//   - `@Query Team` 拿本地 SwiftData(team_local store)的 Team 记录。owner
//     创建后,自己设备的 @Query 立刻看到;member 接受邀请后,
//     ShareInvitationCoordinator 把 mirror 写进本地 SwiftData,也是 @Query 拿。
//   - currentUserID 从 ICloudSyncConfig 拉(第一次进页面时异步 fetch)。
//   - UICloudSharingController 弹出系统邀请 UI(Owner 创建团队后立刻弹)。
//

import SwiftUI
import SwiftData
import CloudKit

struct TeamManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Team.createdAt) private var allTeams: [Team]
    @Query(sort: \TeamMember.joinedAt) private var allMembers: [TeamMember]

    @State private var currentUserID: String = ""
    @State private var currentUserLoaded: Bool = false

    @State private var showsCreateTeam = false
    @State private var showsInvite = false
    @State private var showsLeaveConfirm = false
    @State private var showsDissolveConfirm = false
    @State private var operationError: String?

    /// 创建团队后系统弹邀请 sheet 用。
    @State private var pendingSharingControllerInput: SharingControllerInput?

    /// 当前用户所属团队(本地最多 1 个 — Owner 创建的,或 Member 接受的)。
    private var currentTeam: Team? {
        allTeams.filter { $0.deletedAt == nil }.first
    }

    private var teamMembers: [TeamMember] {
        guard let team = currentTeam else { return [] }
        return allMembers.filter { $0.teamID == team.id }
            .sorted { $0.joinedAt < $1.joinedAt }
    }

    private var locale: Locale { AppLanguageManager.currentLocale }

    var body: some View {
        Form {
            if let team = currentTeam {
                teamHeader(team)
                membersSection(team)
                actionsSection(team)
            } else {
                createSection
            }
        }
        .industrialForm()
        .navigationTitle(String(localized: "团队", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .task { await ensureCurrentUser() }
        .sheet(isPresented: $showsCreateTeam) {
            CreateTeamSheet { name in
                showsCreateTeam = false
                Task { await createTeam(name: name) }
            }
        }
        .sheet(isPresented: $showsInvite) {
            if let team = currentTeam {
                InviteMemberSheet(currentCount: teamMembers.count) { name, email in
                    showsInvite = false
                    Task { await inviteMember(team: team, name: name, email: email) }
                }
            }
        }
        .sheet(item: $pendingSharingControllerInput) { input in
            CloudSharingControllerView(
                share: input.share,
                container: input.container,
                onAdd: { _ in pendingSharingControllerInput = nil },
                onRemove: { pendingSharingControllerInput = nil },
                onStop: { pendingSharingControllerInput = nil }
            )
            .ignoresSafeArea()
        }
        .alert(
            String(localized: "离开团队?", locale: locale),
            isPresented: $showsLeaveConfirm
        ) {
            Button(String(localized: "取消", locale: locale), role: .cancel) {}
            Button(String(localized: "离开", locale: locale), role: .destructive) {
                Task { await leaveTeam() }
            }
        } message: {
            Text(String(
                localized: "你的数据会留在团队(归公司),你将无法再访问。",
                locale: locale
            ))
        }
        .alert(
            String(localized: "解散团队?", locale: locale),
            isPresented: $showsDissolveConfirm
        ) {
            Button(String(localized: "取消", locale: locale), role: .cancel) {}
            Button(String(localized: "解散", locale: locale), role: .destructive) {
                Task { await dissolveTeam() }
            }
        } message: {
            Text(String(
                localized: "解散后所有成员将失去访问。云端数据(team zone)一并删除。无法恢复。",
                locale: locale
            ))
        }
        .alert(
            String(localized: "操作失败", locale: locale),
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button(String(localized: "知道了", locale: locale)) { operationError = nil }
        } message: {
            Text(operationError ?? "")
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
                    Text(String(localized: "\(teamMembers.count) / \(Team.maxMembers) 成员", locale: locale))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func membersSection(_ team: Team) -> some View {
        Section(String(localized: "成员", locale: locale)) {
            ForEach(teamMembers) { member in
                memberRow(member, isOwnerView: team.isOwner(currentUserID: currentUserID))
            }
            if team.isOwner(currentUserID: currentUserID),
               teamMembers.count < Team.maxMembers {
                Button {
                    showsInvite = true
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundStyle(.tint)
                        Text(String(localized: "邀请成员", locale: locale))
                            .foregroundStyle(.primary)
                    }
                }
            } else if teamMembers.count >= Team.maxMembers {
                Text(String(localized: "已达 \(Team.maxMembers) 人上限", locale: locale))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func memberRow(_ member: TeamMember, isOwnerView: Bool) -> some View {
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
                if !member.email.isEmpty {
                    Text(member.email)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            if isOwnerView && member.role != .owner {
                Button {
                    Task { await removeMember(member) }
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
                    showsDissolveConfirm = true
                } label: {
                    Text(String(localized: "解散团队", locale: locale))
                }
            } else {
                Button(role: .destructive) {
                    showsLeaveConfirm = true
                } label: {
                    Text(String(localized: "离开团队", locale: locale))
                }
            }
        } footer: {
            Text(String(localized: "第一版免费;最大 10 人;member 默认可看团队全部;离队数据归公司。", locale: locale))
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
                        Text(String(localized: "创建团队", locale: locale))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(String(localized: "和你的工程师 / 老板一起协作", locale: locale))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(String(localized: "你还没有团队", locale: locale))
        } footer: {
            Text(String(localized: "第一版免费。创建后可邀请最多 9 个成员(共 10 人,含你自己)。通过 iCloud 邀请,需要双方都登录 iCloud。", locale: locale))
                .font(.system(size: 11))
        }
    }

    // MARK: - Actions

    private func ensureCurrentUser() async {
        guard !currentUserLoaded else { return }
        do {
            let id = try await TeamCloudKitService.shared.fetchCurrentUserRecordName()
            await MainActor.run {
                self.currentUserID = id
                self.currentUserLoaded = true
            }
        } catch {
            await MainActor.run {
                self.operationError = String(
                    localized: "无法获取 iCloud 用户身份(请检查 iCloud 登录):\(error.localizedDescription)",
                    locale: locale
                )
            }
        }
    }

    private func createTeam(name: String) async {
        await ensureCurrentUser()
        guard !currentUserID.isEmpty else {
            operationError = String(localized: "iCloud 未就绪", locale: locale)
            return
        }

        // 1. 本地建 Team + Owner 成员
        let team = Team(name: name, ownerUserID: currentUserID)
        modelContext.insert(team)

        let ownerMember = TeamMember(
            teamID: team.id,
            userID: currentUserID,
            displayName: String(localized: "我(Owner)", locale: locale),
            email: "",
            role: .owner
        )
        modelContext.insert(ownerMember)

        do {
            try modelContext.save()
        } catch {
            operationError = error.localizedDescription
            return
        }

        // 2. 推上 CloudKit,拿 CKShare
        do {
            let (share, container) = try await TeamCloudKitService.shared.createTeamOnCloud(team: team)
            try? modelContext.save()  // cloudShareRecordName 已经写回 team
            // 3. 立刻弹 UICloudSharingController 让 owner 发邀请
            pendingSharingControllerInput = SharingControllerInput(share: share, container: container)
        } catch {
            // 云端失败 → 回滚本地(避免本地有 team 但云端没,member 永远接不到)
            modelContext.delete(ownerMember)
            modelContext.delete(team)
            try? modelContext.save()
            operationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func inviteMember(team: Team, name: String, email: String) async {
        let member = TeamMember(
            teamID: team.id,
            userID: "",  // 待对方接受 share 后由 metadata 回填(目前留空,只作本地占位)
            displayName: name,
            email: email,
            role: .engineer
        )
        modelContext.insert(member)
        try? modelContext.save()

        do {
            try await TeamCloudKitService.shared.addMemberOnCloud(member: member)
        } catch {
            modelContext.delete(member)
            try? modelContext.save()
            operationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        // 需要把 CKShare 弹出来让 owner 把 share URL 发给该 email(因为 CKShare 是 zone-level,
        // 邀请是通过 share URL 发布的,不能自动给 email 发,user 自己点系统 share sheet 选 channel)。
        if let shareName = team.cloudShareRecordName {
            await openShareSheet(for: team, shareRecordName: shareName)
        }
    }

    private func openShareSheet(for team: Team, shareRecordName: String) async {
        // 这里是简化版:fetch share record 然后弹 UICloudSharingController。
        // CKShare 在 private DB,recordID 是 (name=shareRecordName, zone=team.id)
        let zoneID = CKRecordZone.ID(zoneName: team.id.uuidString, ownerName: CKCurrentUserDefaultName)
        let shareID = CKRecord.ID(recordName: shareRecordName, zoneID: zoneID)
        let container = CKContainer(identifier: "iCloud.com.banruo.SiteNote")
        do {
            let share = try await container.privateCloudDatabase.record(for: shareID) as? CKShare
            if let share {
                await MainActor.run {
                    pendingSharingControllerInput = SharingControllerInput(share: share, container: container)
                }
            }
        } catch {
            await MainActor.run {
                self.operationError = String(
                    localized: "拉取分享失败:\(error.localizedDescription)",
                    locale: locale
                )
            }
        }
    }

    private func removeMember(_ member: TeamMember) async {
        modelContext.delete(member)
        try? modelContext.save()
        // TODO: 同步删 CKRecord(目前只删本地,CKShare 的 participant remove
        // 需要通过 CKShare API 单独做,留 v1.2.x 补)
    }

    private func leaveTeam() async {
        guard let team = currentTeam else { return }
        // Member 端:删自己 + 删本地 team mirror。
        // 云端 CKShare 还在(zone 是 owner 的),只是该 member 不再 sync。
        // 严谨做法:让 member 调 CKAcceptSharesOperation 的 remove,但简化版直接清本地。
        let myMembers = teamMembers.filter { $0.userID == currentUserID }
        for m in myMembers { modelContext.delete(m) }
        modelContext.delete(team)
        try? modelContext.save()
    }

    private func dissolveTeam() async {
        guard let team = currentTeam,
              team.isOwner(currentUserID: currentUserID) else { return }
        // Owner 端:删 cloud zone(连带 CKShare + records)+ 清本地。
        do {
            try await TeamCloudKitService.shared.deleteTeamZoneOnCloud(team: team)
        } catch {
            operationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        for m in teamMembers { modelContext.delete(m) }
        modelContext.delete(team)
        try? modelContext.save()
    }
}

// MARK: - 弹 UICloudSharingController 的 input wrapper

private struct SharingControllerInput: Identifiable {
    let share: CKShare
    let container: CKContainer
    var id: String { share.recordID.recordName }
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
                Section {} footer: {
                    Text(String(
                        localized: "创建后会立刻弹出系统邀请页,可通过 Mail / Messages 发链接邀请成员。需要你和成员都登录 iCloud。",
                        locale: AppLanguageManager.currentLocale
                    ))
                    .font(.system(size: 11))
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
                    Text(String(localized: "添加后会再次弹出系统邀请页,你可以把链接通过 Messages/Mail 发给该成员(系统会自动 lookup 对应 iCloud 账户)。当前 \(currentCount) / \(Team.maxMembers) 成员。", locale: AppLanguageManager.currentLocale))
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
