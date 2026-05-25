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
                syncDiagnosticSection
            } else {
                createSection
            }
        }
        .industrialForm()
        .navigationTitle(String(localized: "团队", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await TeamDataMirrorService.shared.fetchAndSyncAll(in: modelContext, forceFullSync: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(String(localized: "刷新", locale: locale))
            }
        }
        .task {
            await ensureCurrentUser()
            // 进入团队页主动拉一次 zone changes,Owner 能看到 Member 注册;Member 能补 register。
            await TeamDataMirrorService.shared.fetchAndSyncAll(in: modelContext, forceFullSync: true)
        }
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
                localized: "你的本地团队信息会被清理,你将看不到团队数据。注意:Owner 仍然在云端 share 名单里看到你 —— 彻底移除需要 Owner 在团队页点 \"-\" 撤销邀请。",
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
            SectionFooter(String(localized: "第一版免费;最大 10 人;member 默认可看团队全部;离队数据归公司。", locale: locale))
        }
    }

    /// 同步状态诊断段 — 默认折叠的 DisclosureGroup,不污染主页面。
    /// 用户出问题时展开截图给开发反馈。
    @ViewBuilder
    private var syncDiagnosticSection: some View {
        Section {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                        Text(String(localized: "最近拉取:", locale: locale))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Ink.fgDim)
                    }
                    Text(TeamDataMirrorService.shared.lastSyncStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.fg)
                        .textSelection(.enabled)

                    Divider().padding(.vertical, 4)

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                        Text(String(localized: "最近推送:", locale: locale))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Ink.fgDim)
                    }
                    Text(TeamDataMirrorService.shared.lastMirrorStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.fg)
                        .textSelection(.enabled)

                    if let ts = TeamDataMirrorService.shared.lastActivityAt {
                        Text(String(localized: "时间:\(ts.formatted(date: .omitted, time: .standard))", locale: locale))
                            .font(.system(size: 10))
                            .foregroundStyle(Ink.fgDim)
                            .padding(.top, 2)
                    }

                    // P1 retry queue:让用户清楚知道有多少条 mirror 待重发
                    let pending = TeamDataMirrorService.shared.pendingRetryCount
                    if pending > 0 {
                        Divider().padding(.vertical, 4)
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11))
                                .foregroundStyle(Ink.amber)
                            Text(String(localized: "待重发:\(pending) 条", locale: locale))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Ink.fg)
                        }
                        Text(String(localized: "网络恢复后下次进入团队页 / 报告页会自动重发。也可点右上角刷新按钮立刻重试。",
                                    locale: locale))
                            .font(.system(size: 10))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
                .padding(.vertical, 6)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                    Text(String(localized: "同步诊断", locale: locale))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Ink.fg2)
                    // 待重发数量徽章 — 折叠态也能看到 X 条未同步
                    let pending = TeamDataMirrorService.shared.pendingRetryCount
                    if pending > 0 {
                        Text("\(pending)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Ink.bg)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Ink.amber))
                    }
                }
            }
        } footer: {
            SectionFooter(String(localized: "同步异常时展开,截图给开发反馈。", locale: locale))
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
            SectionHeader(String(localized: "你还没有团队", locale: locale))
        } footer: {
            SectionFooter(String(localized: "第一版免费。创建后可邀请最多 9 个成员(共 10 人,含你自己)。通过 iCloud 邀请,需要双方都登录 iCloud。", locale: locale))
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

        // 1. 本地建 Team + Owner 成员。
        // displayName 用「设置 → 我是 → 我的名字」,空就 fallback 用 userID 前 8 位。
        // 不再用 hardcode "我(Owner)" — Member 端拉到这条 TeamMember 时看到"我(Owner)"会困惑。
        let team = Team(name: name, ownerUserID: currentUserID)
        modelContext.insert(team)

        let trimmedName = UserProfileManager.shared.userDisplayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerDisplay = trimmedName.isEmpty ? String(currentUserID.prefix(8)) : trimmedName
        let ownerMember = TeamMember(
            teamID: team.id,
            userID: currentUserID,
            displayName: ownerDisplay,
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

            // **关键**:Owner 自己的 TeamMember 也要推到 zone — 否则 Member 接受邀请拉 zone records
            // 只有 Team CKRecord 没 Owner TeamMember,Member 端永远看不到 Owner 的名字 / 信息。
            do {
                try await TeamCloudKitService.shared.addMemberOnCloud(member: ownerMember)
            } catch {
                // 推 owner member 失败不阻塞(Owner 本地有 record,fetchAndSyncAll 下次会重推)
                print("[CreateTeam] push owner member failed:", error.localizedDescription)
            }

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

    /// 邀请新成员。**不再** 本地写占位 TeamMember(userID="")+ 不再 push placeholder 到 cloud —
    /// 之前会导致:Owner 输入名字"Jamie",Member 实际接受时用自己「我的名字」"JamieSmith" 再
    /// register 一条 → 同 team 出现两条 Jamie(一占位 + 一真的)。修法:UICloudSharingController
    /// 邀请 + Member 端 acceptShareInvitation 自动 ensureSelfMemberRecord 写权威 record。
    /// name + email 输入框只是用户心智上的"邀请清单",不真写 model。
    private func inviteMember(team: Team, name: String, email: String) async {
        if let shareName = team.cloudShareRecordName {
            await openShareSheet(for: team, shareRecordName: shareName)
        }
        // name + email 当前只用于 UI hint(也不再发送任何 email/notify — 真邀请走 UICloudSharingController)
        _ = name; _ = email
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

    /// Owner 端移除成员。**数据流**:
    /// 1. 删云端 zone 里该成员的 TeamMember CKRecord
    /// 2. 尝试从 CKShare.participants 撤销该成员的 share access(best-effort,iCloud 端延迟生效)
    /// 3. 删本地 SwiftData TeamMember
    ///
    /// **真实限制**:即使 CKShare 撤销成功,Member 设备的 sharedDB cache 在他主动 fetch
    /// 前看起来还能访问。彻底"踢人"的语义需要 Owner 解散重建团队,这是 CKShare 的限制。
    /// 失败时云端先回滚不可能(modifyRecords 已部分提交),所以失败也走本地删 — 至少保持
    /// "我看不到这人了" 的 UX。下次 fetchAndSyncAll 如果发现 record 还在云端,会重新拉回本地
    /// (这是正常的"未真正撤销"反馈)。
    private func removeMember(_ member: TeamMember) async {
        guard let team = currentTeam, team.isOwner(currentUserID: currentUserID) else { return }
        let userIDForRevoke = member.userID
        do {
            try await TeamCloudKitService.shared.removeMemberOnCloud(member: member)
        } catch {
            operationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // 继续本地删 — 见 doc 上面的解释
        }
        // 尝试撤销 share access(best-effort,失败不阻断)
        await TeamCloudKitService.shared.tryRevokeShareParticipant(team: team, memberUserID: userIDForRevoke)
        modelContext.delete(member)
        try? modelContext.save()
    }

    /// Member 端离开团队。**数据流**:
    /// - 本地:清 Team + TeamMember + UserDefaults team.* 缓存(token / sharedZoneOwnerName /
    ///   selfMemberID / selfPushed)— 走 clearLocalTeamMirror。
    /// - 云端:**不删** Owner 的 share zone(没权限,且 zone 是 Owner 资产)。
    ///   理想做法是调 `CKContainer.shared.unshareCloudKitContainer(...)` 让 Member 主动放弃 share,
    ///   但 iOS 没暴露该 API。我们只能让 Member 本地不再 fetch,share access 在 Member 接受新邀请前
    ///   仍然技术上存在。UI 已通过文案说明。
    ///
    /// 后果:
    /// - Member 看不到团队任何数据(本地 Team 软删 + token 清,下次 fetch 找不到也不再尝试)
    /// - Owner 仍能在自己的 share.participants 看到这个 Member(必须手动 removeMember 才能下掉)
    private func leaveTeam() async {
        guard let team = currentTeam else { return }
        TeamDataMirrorService.shared.clearLocalTeamMirror(team: team, in: modelContext)
    }

    /// Owner 端解散团队。**数据流**:
    /// 1. 删云端 zone(连带 CKShare + 所有 record)— Member 下次 fetch 拿到 zoneNotFound,
    ///    走 clearLocalTeamMirror 自己清本地
    /// 2. 本地:删 Team + TeamMember + 清 UserDefaults team.* 缓存
    private func dissolveTeam() async {
        guard let team = currentTeam,
              team.isOwner(currentUserID: currentUserID) else { return }
        let teamID = team.id
        do {
            try await TeamCloudKitService.shared.deleteTeamZoneOnCloud(team: team)
        } catch {
            operationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        for m in teamMembers { modelContext.delete(m) }
        modelContext.delete(team)
        try? modelContext.save()
        TeamDataMirrorService.shared.purgeTeamLocalCaches(teamID: teamID)
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
                    SectionFooter(String(
                        localized: "创建后会立刻弹出系统邀请页,可通过 Mail / Messages 发链接邀请成员。需要你和成员都登录 iCloud。",
                        locale: AppLanguageManager.currentLocale
                    ))
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
                    SectionFooter(String(localized: "添加后会再次弹出系统邀请页,你可以把链接通过 Messages/Mail 发给该成员(系统会自动 lookup 对应 iCloud 账户)。当前 \(currentCount) / \(Team.maxMembers) 成员。", locale: AppLanguageManager.currentLocale))
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
