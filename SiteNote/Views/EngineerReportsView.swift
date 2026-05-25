//
//  EngineerReportsView.swift
//  SiteNote
//
//  Engineer Profile 专属"报告"Tab。
//
//  与 PM 的 ReportsView(本周 sparkline / 月度看板 / 多入口)**完全不同**:
//  报告由巡检 session 完成时**自动生成**写入,这个 Tab 是"资源库"角色 ——
//  顶部 search bar + 项目筛选,下面是历史报告列表(草稿 + 已提交),
//  点行跳 InspectionReportDetailView 查看详情与发送状态。
//

import SwiftUI
import SwiftData
import os

/// 报告范围切换:我的 / 团队全部。
/// Phase 2 已接通:`InspectionReport.createdByUserID` 由 InspectionSessionManager
/// 在创建时写入 `ICloudSyncConfig.shared.currentUserRecordName`;"我的" 过滤本人 +
/// 空串(老数据 / 单机数据),"团队全部" 不过滤。
/// segmented 仅在有 Team 时显示(没团队 → 视图永远是"我的")。
enum ReportScope: String, CaseIterable {
    case mine
    case team
}

struct EngineerReportsView: View {
    private static let logger = Logger(subsystem: "com.banruo.sitenote", category: "EngineerReports")
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<InspectionReport> { $0.deletedAt == nil },
        sort: \InspectionReport.createdAt,
        order: .reverse
    ) private var allReports: [InspectionReport]

    /// 反查"别人的报告" → 显示名。`TeamMember.userID → displayName`。
    @Query private var teamMembers: [TeamMember]

    /// 用来判断有无 Team(决定 segmented 是否显示)。
    @Query(filter: #Predicate<Team> { $0.deletedAt == nil }) private var teams: [Team]

    /// 资源库搜索词。匹配 reportNo / project / inspectionType。
    @State private var searchText: String = ""

    /// 当前 segmented 选中段。
    @State private var scope: ReportScope = .mine

    /// 项目筛选:nil = 全部项目;否则按 InspectionReport.projectNo 匹配。
    @State private var projectFilter: String? = nil

    /// 当前用户的 CloudKit recordName(`ICloudSyncConfig.shared.currentUserRecordName`)。
    /// 没启用 iCloud / 还没拉到 → 空串,等价于"全部视为我的"(单机模式行为)。
    @State private var currentUserID: String = ""

    /// 按 scope 过滤后的全集。
    /// - mine: createdByUserID == currentUserID OR createdByUserID.isEmpty(老数据 / 单机)。
    /// - team: 不过滤,显示 CloudKit 同步过来的全部。
    private var scopedReports: [InspectionReport] {
        switch scope {
        case .mine:
            return allReports.filter { r in
                r.createdByUserID == currentUserID || r.createdByUserID.isEmpty
            }
        case .team:
            return allReports
        }
    }

    /// 项目筛选后的 report 列表。chip 行的 "全部" 用 nil;"未分类" 匹配空 projectNo。
    private var filteredReports: [InspectionReport] {
        guard let pf = projectFilter else { return scopedReports }
        if pf == "未分类" {
            return scopedReports.filter { $0.projectNo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return scopedReports.filter { $0.projectNo == pf }
    }

    /// 所有报告里出现过的 projectNo,sorted。空 projectNo 归类成"未分类",一起出现在 chip 行。
    private var allProjectNos: [String] {
        let set = Set(scopedReports.map { $0.projectNo.trimmingCharacters(in: .whitespacesAndNewlines) })
        let nonEmpty = set.filter { !$0.isEmpty }.sorted()
        // 有空 projectNo 的报告 → 加 "未分类" 末尾
        let hasUnsorted = set.contains("")
        return hasUnsorted ? nonEmpty + ["未分类"] : nonEmpty
    }

    /// 搜索过滤后的列表 —— 在 filteredReports 基础上再匹配 search text。
    /// 搜索字段:reportNo / project / inspectionType(不区分大小写)。
    private var searchFilteredReports: [InspectionReport] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return filteredReports }
        return filteredReports.filter { r in
            r.reportNo.lowercased().contains(q)
                || r.project.lowercased().contains(q)
                || r.inspectionType.lowercased().contains(q)
        }
    }

    private var drafts: [InspectionReport] {
        searchFilteredReports.filter { $0.statusRaw == InspectionStatus.draft.rawValue }
    }

    private var submitted: [InspectionReport] {
        searchFilteredReports.filter { $0.statusRaw == InspectionStatus.submitted.rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    titleRow
                    searchBar
                    listContent
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: SettingsDestination.self) { _ in
                SettingsView()
            }
            // 报告详情里点 note row → 跳详情(草稿 / 已提交都通用)。
            .navigationDestination(for: Note.self) { note in
                NoteRouter(note: note)
            }
            .task {
                currentUserID = ICloudSyncConfig.shared.currentUserRecordName ?? ""
                // 没团队 → 强制 scope = .mine,segmented 不显示。
                if teams.isEmpty {
                    scope = .mine
                }
                // 团队 mirror:进报告页拉一次 zone changes,owner 看到 member 的报告
                await TeamDataMirrorService.shared.fetchAndSyncAll(in: modelContext, forceFullSync: true)
                // **Codex#10**:fetchAndSyncAll 内部首次会 await fetchAndCacheUserRecord,
                // 完成后 currentUserRecordName 可能从 nil 变非空 → 这里再读一次保证"我的"
                // scope 过滤正确,否则 currentUserID="" 时 mine == 所有 createdByUserID="" + 自己。
                let refreshed = ICloudSyncConfig.shared.currentUserRecordName ?? ""
                if refreshed != currentUserID {
                    currentUserID = refreshed
                }
            }
            // **关键 bug fix**:scope 切换时 reset projectFilter + searchText。
            // 否则用户在「我的」选了某个项目过滤(如 "ProjectA"),切到「团队全部」后
            // 该过滤继续生效 → Member 的 report 因 projectNo 不匹配被过滤掉 → 看不到。
            // 这就是"诊断显示 DB 有数据但 list 空"的根因。
            .onChange(of: scope) { _, _ in
                projectFilter = nil
                searchText = ""
            }
            // 自愈:projectFilter 选过的项目如果现在 allProjectNos 已不再包含(例如
            // Member 删了那个 projectNo 唯一的报告),立刻 reset 避免悬空过滤。
            .onChange(of: allProjectNos) { _, newSet in
                if let pf = projectFilter, !newSet.contains(pf) {
                    projectFilter = nil
                }
            }
        }
    }

    /// 顶部大标题 + 项目下拉 + 齿轮(跟其他 tab 一致 inline)。
    /// 工程师工地多(10+),用下拉而不是横向 chip 行,避免左右滑。
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "报告", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Ink.fg)
            Spacer()
            if !allProjectNos.isEmpty {
                SiteFilterMenu(allTags: allProjectNos, selection: $projectFilter)
            }
            NavigationLink(value: SettingsDestination()) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Ink.fgDim)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "设置", locale: AppLanguageManager.currentLocale))
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    /// 顶部常驻 search bar(资源库化)。与 RecordView 视觉一致:细描边、非填充。
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Ink.fgDim)
            TextField(
                String(localized: "搜索报告(编号 / 项目 / 类型)", locale: AppLanguageManager.currentLocale),
                text: $searchText
            )
            .font(.system(size: 13))
            .foregroundStyle(Ink.fg)
            .tint(Ink.fg)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.fgDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Ink.line, lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 8).fill(Ink.bg))
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

    private var listContent: some View {
        List {
                    // Scope segmented: 我的 / 团队全部 —— 仅在用户已在 Team 时显示。
                    // 无团队场景 → 不渲染 segmented,内容默认 "我的"。
                    if !teams.isEmpty {
                        Section {
                            Picker("", selection: $scope) {
                                Text(String(localized: "我的", locale: AppLanguageManager.currentLocale))
                                    .tag(ReportScope.mine)
                                Text(String(localized: "团队全部", locale: AppLanguageManager.currentLocale))
                                    .tag(ReportScope.team)
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 16)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Ink.bg)

                            // 诊断条:让用户看到 @Query 实际拉到几条 + 同步状态。
                            // 帮助排查"诊断显示拉到 N 条但 UI 不显示"的差距。
                            if scope == .team {
                                teamScopeDiagnostic
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Ink.bg)
                            }
                        }
                    }

                    // 草稿段
                    if !drafts.isEmpty {
                        Section {
                            ForEach(drafts) { report in
                                reportRowButton(report)
                                    .listRowBackground(Ink.bg)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            softDelete(report)
                                        } label: {
                                            Label(
                                                String(localized: "删除", locale: AppLanguageManager.currentLocale),
                                                systemImage: "trash"
                                            )
                                        }
                                        .tint(Ink.red)
                                    }
                            }
                        } header: {
                            SectionHeader(
                                String(localized: "草稿(\(drafts.count))", locale: AppLanguageManager.currentLocale)
                            )
                        }
                    }

                    // 已提交段
                    if !submitted.isEmpty {
                        Section {
                            ForEach(submitted) { report in
                                reportRowButton(report)
                                    .listRowBackground(Ink.bg)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            softDelete(report)
                                        } label: {
                                            Label(
                                                String(localized: "删除", locale: AppLanguageManager.currentLocale),
                                                systemImage: "trash"
                                            )
                                        }
                                        .tint(Ink.red)
                                    }
                            }
                        } header: {
                            SectionHeader(
                                String(localized: "已提交(\(submitted.count))", locale: AppLanguageManager.currentLocale)
                            )
                        }
                    }

                    if drafts.isEmpty && submitted.isEmpty {
                        Section {
                            emptyHint
                                .listRowBackground(Ink.bg)
                                .listRowSeparator(.hidden)
                        } header: {
                            SectionHeader(
                                String(localized: "我的报告", locale: AppLanguageManager.currentLocale)
                            )
                        }
                    }
                }
        .listStyle(.plain)
        .industrialForm()
        .refreshable {
            // 下拉刷新主动重新拉一次 share zone changes。
            await TeamDataMirrorService.shared.fetchAndSyncAll(in: modelContext, forceFullSync: true)
        }
    }

    /// 团队全部段顶部轻量信息条 — 只显示团队成员条数 + 刷新按钮。
    /// **P1 增强**:有待重发 mirror 时显示橙色警告 + 数量(用户能看到"我的 report 没发出去")。
    /// 长按行显示完整同步诊断 alert(开发用,普通用户不看)。
    private var teamScopeDiagnostic: some View {
        let others = allReports.filter { !$0.createdByUserID.isEmpty && $0.createdByUserID != currentUserID }.count
        let pendingRetry = TeamDataMirrorService.shared.pendingRetryCount
        return HStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.system(size: 11))
                .foregroundStyle(Ink.fgDim)
            Text(String(localized: "团队成员提交 \(others) 条", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ink.fg2)
                .monospacedDigit()
            // 待重发徽章
            if pendingRetry > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                    Text(String(localized: "\(pendingRetry) 待重发", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(Ink.bg)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Ink.amber))
            }
            Spacer()
            Button {
                Task {
                    await TeamDataMirrorService.shared.fetchAndSyncAll(in: modelContext, forceFullSync: true)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.fg2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Ink.card)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            // 长按弹诊断详情(给开发 / 内测排查用,普通用户不会触发)
            Button(action: {}) {
                Label(TeamDataMirrorService.shared.lastSyncStatus, systemImage: "arrow.down.circle")
            }
            Button(action: {}) {
                Label(TeamDataMirrorService.shared.lastMirrorStatus, systemImage: "arrow.up.circle")
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func reportRowButton(_ report: InspectionReport) -> some View {
        NavigationLink {
            InspectionReportDetailView(report: report)
        } label: {
            HStack(spacing: 8) {
                reportRow(report)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.dim)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func reportRow(_ report: InspectionReport) -> some View {
        HStack(spacing: 12) {
            // 左侧状态色条:草稿蓝、已提交灰
            RoundedRectangle(cornerRadius: 1.5)
                .fill(report.status == .draft ? Ink.accentBlue : Ink.dim)
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(report.reportNo.isEmpty
                         ? String(localized: "(无编号)", locale: AppLanguageManager.currentLocale)
                         : report.reportNo)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                        .monospacedDigit()
                    if !report.inspectionType.isEmpty {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                        Text(report.inspectionType)
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    statusBadge(for: report)
                }
                // project 空 → fallback 到 location;再空 → fallback 到 reportNo
                let trimmedProject = report.project.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedLocation = report.location.trimmingCharacters(in: .whitespacesAndNewlines)
                let projectDisplay = trimmedProject.isEmpty
                    ? (trimmedLocation.isEmpty ? report.reportNo : report.location)
                    : report.project
                Text(projectDisplay)
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.fg)
                    .lineLimit(1)
                // 只在 project 非空时再显示 location 作副行,避免和上面重复
                if !trimmedProject.isEmpty, !trimmedLocation.isEmpty {
                    Text(report.location)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                        .lineLimit(1)
                }
                // 团队场景:别人的报告显示橙色 chip "<Member名字>"。自己的 / 老数据(空 owner) 不显示。
                if let creatorName = creatorDisplayName(for: report) {
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text(creatorName)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Ink.bg)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Ink.amber))
                }
            }
            VStack(alignment: .trailing, spacing: 3) {
                Text(dateLabel(for: report.reportDate))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.fgDim)
                    .monospacedDigit()
                Text(
                    String(
                        localized: "\(report.noteIDs.count) 条",
                        locale: AppLanguageManager.currentLocale
                    )
                )
                .font(.system(size: 10))
                .foregroundStyle(Ink.dim)
                // 邮件发送状态:草稿 ≡ 未发(submittedAt 必为 nil);
                // submitted 才看 attn 字段近似显示"已发 <builder>"。
                // TODO: 当前 submitted 路径仍是近似(没专门 sentTo 字段),
                //   真正落地需新增 InspectionReport.sentAt/sentTo 或关联 ShareLog。
                HStack(spacing: 3) {
                    Image(systemName: "envelope")
                        .font(.system(size: 10))
                    Text(mailStatusText(for: report))
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                .foregroundStyle(Ink.fgDim)
            }
        }
        .padding(.vertical, 4)
    }

    private func dateLabel(for date: Date) -> String {
        Formatters.dayMonthShort.string(from: date)
    }

    /// 团队场景下,如果是别人创建的报告 → 返回 displayName(用于橙色 chip 显示)。
    /// 自己的 / 空 owner(老数据 / 单机) → nil(不显示 chip)。
    /// TeamMember 反查不到 → fallback 短 UUID(取前 6 位)。
    private func creatorDisplayName(for report: InspectionReport) -> String? {
        let owner = report.createdByUserID
        guard !owner.isEmpty, owner != currentUserID else { return nil }
        if let member = teamMembers.first(where: { $0.userID == owner }),
           !member.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return member.displayName
        }
        return String(owner.prefix(6))
    }

    /// 邮件状态文本。草稿一律"未发";submitted 用 attn 字段近似(老逻辑)。
    private func mailStatusText(for report: InspectionReport) -> String {
        if report.status == .draft {
            return String(localized: "未发", locale: AppLanguageManager.currentLocale)
        }
        let attn = report.attn.trimmingCharacters(in: .whitespacesAndNewlines)
        if attn.isEmpty {
            return String(localized: "未发", locale: AppLanguageManager.currentLocale)
        }
        return String(localized: "已发 \(attn)", locale: AppLanguageManager.currentLocale)
    }

    /// 状态 badge — draft 蓝点圆角 + "草稿",submitted 灰底 + "已提交"。
    /// 用户原话:"未发邮件的巡检状态也不能叫已提交",这里 draft 走自己显眼的样式。
    @ViewBuilder
    private func statusBadge(for report: InspectionReport) -> some View {
        if report.status == .draft {
            HStack(spacing: 3) {
                Image(systemName: "doc.badge.ellipsis")
                    .font(.system(size: 10))
                Text(String(localized: "草稿", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Ink.accentBlue)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Ink.accentBlue.opacity(0.4), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Ink.bg))
            )
        } else {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 10))
                Text(String(localized: "已提交", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Ink.fgDim)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Ink.card)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - 空态(列表段为空时显示在"我的报告"section 里)

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(searchText.isEmpty
                 ? String(localized: "还没有报告", locale: AppLanguageManager.currentLocale)
                 : String(localized: "没有匹配的报告", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.fg)
            Text(searchText.isEmpty
                 ? String(localized: "完成一次巡检 session 后,报告会自动出现在这里。", locale: AppLanguageManager.currentLocale)
                 : String(localized: "试试换个关键词。", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 12))
                .foregroundStyle(Ink.fgDim)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 删除

    private func softDelete(_ report: InspectionReport) {
        report.deletedAt = Date()
        report.updatedAt = Date()
        // P1 #194:save 失败不再 try? 静默 — 写 OS Logger,Console 可查。
        // 失败时本地内存改了但磁盘没,下次启动数据回弹。一般是磁盘满 / CloudKit 配额。
        //
        // **R3#6**:save 失败时**不**触发 mirror —— 否则把未持久化的 deletedAt 推到 share zone,
        // 团队成员看不到 record 但本地仍存在 → 数据不一致。
        do {
            try modelContext.save()
            // 团队场景:把 deletedAt 推到 share zone,Member 端拉到 deletion 信号 → 跟着软删。
            // 不 mirror 的话 Member 那边永远看着这条 record;Owner 下次拉 share zone 也会被回填。
            let ctx = modelContext
            let r = report
            Task { await TeamDataMirrorService.shared.mirrorReport(r, in: ctx) }
        } catch {
            Self.logger.error("softDelete save failed; not mirroring: \(error.localizedDescription)")
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Note.self, LogEntry.self, ShareLog.self, InspectionReport.self,
        Team.self, TeamMember.self,
        configurations: config
    )
    return EngineerReportsView().modelContainer(container)
}
