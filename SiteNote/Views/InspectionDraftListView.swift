//
//  InspectionDraftListView.swift  (struct renamed to InspectionReportListView)
//  SiteNote
//
//  Engineer 巡检报告列表(草稿 / 已提交 两段)。
//  顶部 "+" 创建新 InspectionReport 并直接 push 到 InspectionFormView。
//
//  R3 重构后:
//    - 数据模型从 InspectionDraft 切换到 InspectionReport(@Model 文件名保留为
//      InspectionDraft.swift,但类型已重命名)。
//    - struct InspectionDraftListView → InspectionReportListView。
//    - 文件名不改(避免 PBXFileSystemSynchronizedRootGroup 重新索引)。
//

import SwiftUI
import SwiftData

/// RecordView Engineer 主屏顶部 NavigationLink 的路由标签。
struct InspectionEntryDestination: Hashable {}

struct InspectionReportListView: View {
    @Environment(\.modelContext) private var modelContext

    /// 只查活的报告(deletedAt == nil),按创建时间倒序。
    @Query(
        filter: #Predicate<InspectionReport> { $0.deletedAt == nil },
        sort: \InspectionReport.createdAt,
        order: .reverse
    ) private var allReports: [InspectionReport]

    /// 当前要 push 的报告。`点行` 和 `+ 新建` 都写这里。
    @State private var selectedReport: InspectionReport?

    private var drafts: [InspectionReport] {
        allReports.filter { $0.statusRaw == InspectionStatus.draft.rawValue }
    }

    private var submitted: [InspectionReport] {
        allReports.filter { $0.statusRaw == InspectionStatus.submitted.rawValue }
    }

    var body: some View {
        Group {
            if allReports.isEmpty {
                emptyState
            } else {
                List {
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

                    if !submitted.isEmpty {
                        Section {
                            ForEach(submitted) { report in
                                reportRowButton(report)
                                    .listRowBackground(Ink.bg)
                            }
                        } header: {
                            SectionHeader(
                                String(localized: "已提交(\(submitted.count))", locale: AppLanguageManager.currentLocale)
                            )
                        }
                    }
                }
                .listStyle(.plain)
                .industrialForm()
            }
        }
        .navigationTitle(String(localized: "巡检报告", locale: AppLanguageManager.currentLocale))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    createNewReport()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                }
                .accessibilityLabel(String(localized: "新建巡检", locale: AppLanguageManager.currentLocale))
            }
        }
        // iOS 17+:单一路由入口。`selectedReport` 被赋值时自动 push。
        .navigationDestination(item: $selectedReport) { report in
            InspectionFormView(report: report)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func reportRowButton(_ report: InspectionReport) -> some View {
        Button {
            selectedReport = report
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
            statusIcon(for: report)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
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
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.fgDim)
                            .lineLimit(1)
                    }
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
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(dateLabel(for: report.reportDate))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Ink.fgDim)
                    .monospacedDigit()
                Text(
                    String(
                        localized: "\(report.noteIDs.count) 条记录",
                        locale: AppLanguageManager.currentLocale
                    )
                )
                .font(.system(size: 10))
                .foregroundStyle(Ink.dim)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusIcon(for report: InspectionReport) -> some View {
        let symbol: String
        let color: Color
        switch report.status {
        case .draft:
            symbol = "doc.text"
            color = Ink.accentBlue
        case .submitted:
            symbol = "checkmark.seal.fill"
            color = Ink.fgDim
        }
        return Image(systemName: symbol)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
    }

    private func dateLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Ink.fgDim)
            Text(String(localized: "还没有巡检报告", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ink.fg)
            Text(String(localized: "点右上角 + 新建一份。先填好 Header,再挑当天的现场速记。", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 12))
                .foregroundStyle(Ink.fgDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                createNewReport()
            } label: {
                Label(
                    String(localized: "新建巡检", locale: AppLanguageManager.currentLocale),
                    systemImage: "plus"
                )
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Ink.fg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.bg)
    }

    // MARK: - 创建 / 删除

    /// 新建一份报告 → 插入 context → 立刻 push 到 FormView。
    /// reportNo 占位策略:projectNo 为空时不预填(FormView 内 onChange 会接管)。
    private func createNewReport() {
        let report = InspectionReport()
        modelContext.insert(report)
        selectedReport = report
    }

    private func softDelete(_ report: InspectionReport) {
        report.deletedAt = Date()
    }
}
