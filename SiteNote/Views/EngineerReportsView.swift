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

/// 报告范围切换:我的 / 团队全部。
/// Phase 0 mock:InspectionReport 还没 `createdByUserID` 字段(Phase 2 加),
/// 现在 "我的" 视为全部 owner 为空串/`mockCurrentUserID` 的 report,
/// "团队全部" 不过滤 —— 视觉上 segmented 通了,逻辑等 Phase 2 接通 CloudKit 后用
/// `ICloudSyncConfig.shared.currentUserRecordName` 替换 `mockCurrentUserID`。
enum ReportScope: String, CaseIterable {
    case mine
    case team
}

struct EngineerReportsView: View {
    @Query(
        filter: #Predicate<InspectionReport> { $0.deletedAt == nil },
        sort: \InspectionReport.createdAt,
        order: .reverse
    ) private var allReports: [InspectionReport]

    /// 资源库搜索词。匹配 reportNo / project / inspectionType。
    @State private var searchText: String = ""

    /// 当前 segmented 选中段。
    @State private var scope: ReportScope = .mine

    /// 项目筛选:nil = 全部项目;否则按 InspectionReport.projectNo 匹配。
    @State private var projectFilter: String? = nil

    /// Phase 0 mock;InspectionReport.createdByUserID 在 Phase 2 时加。
    /// Phase 2 接通 CloudKit 后用 `ICloudSyncConfig.shared.currentUserRecordName`。
    private let mockCurrentUserID = "self"

    /// 按 scope 过滤后的全集。
    /// Phase 0 mock;InspectionReport.createdByUserID 在 Phase 2 时加 —— 现在
    /// "我的" 用占位逻辑(全部视为本人,因为 model 上还没字段),
    /// "团队全部" 直接放行,segmented 在视觉上已经能切换。
    private var scopedReports: [InspectionReport] {
        switch scope {
        case .mine:
            // Phase 2 真实实现:
            // allReports.filter {
            //     $0.createdByUserID == ICloudSyncConfig.shared.currentUserRecordName
            //         || $0.createdByUserID.isEmpty
            // }
            return allReports
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
                    // Scope segmented: 我的 / 团队全部
                    // Phase 0 mock;Phase 2 加 InspectionReport.createdByUserID 后接通真实过滤。
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
                    if report.status == .submitted {
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
                Text(report.project.isEmpty
                     ? String(localized: "(未填项目)", locale: AppLanguageManager.currentLocale)
                     : report.project)
                    .font(.system(size: 13))
                    .foregroundStyle(report.project.isEmpty ? Ink.fgDim : Ink.fg)
                    .lineLimit(1)
                if !report.location.isEmpty {
                    Text(report.location)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                        .lineLimit(1)
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
                // 邮件发送状态:已发 builder 姓名(attn) / 未发。
                // TODO: 当前用 report.attn 是否非空近似判断 —— InspectionReport
                //   暂未存"发件历史",真正落地需新增字段(ShareLog 关联或
                //   InspectionReport.sentAt/sentTo 属性),其他 agent 在做。
                HStack(spacing: 3) {
                    Image(systemName: "envelope")
                        .font(.system(size: 10))
                    Text(report.attn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? String(localized: "未发", locale: AppLanguageManager.currentLocale)
                         : String(localized: "已发 \(report.attn)", locale: AppLanguageManager.currentLocale))
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
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Note.self, LogEntry.self, ShareLog.self, InspectionReport.self,
        configurations: config
    )
    return EngineerReportsView().modelContainer(container)
}
