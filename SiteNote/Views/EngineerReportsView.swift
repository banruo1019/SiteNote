//
//  EngineerReportsView.swift
//  SiteNote
//
//  Engineer Profile 专属"报告"Tab。
//
//  与 PM 的 ReportsView(本周 sparkline / 月度看板 / 多入口)**完全不同**:
//  Engineer 工作流核心就是"做一份巡检报告" —— 顶部一个大"+ 导出报告"按钮,
//  下方是"我的报告"历史列表(草稿 + 已提交)。
//
//  实现复用 InspectionReportListView 的数据查询 + InspectionFormView 的填报界面;
//  这里只做 Tab 入口的 layout(NavigationStack + List + 顶部突出按钮)。
//

import SwiftUI
import SwiftData

struct EngineerReportsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<InspectionReport> { $0.deletedAt == nil },
        sort: \InspectionReport.createdAt,
        order: .reverse
    ) private var allReports: [InspectionReport]

    /// `navigationDestination(item:)` 单一路由入口 —— 点 "+导出" 或点历史行都写这里。
    @State private var selectedReport: InspectionReport?

    private var drafts: [InspectionReport] {
        allReports.filter { $0.statusRaw == InspectionStatus.draft.rawValue }
    }

    private var submitted: [InspectionReport] {
        allReports.filter { $0.statusRaw == InspectionStatus.submitted.rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                List {
                    // 顶部:大"+ 导出报告"按钮(突出主操作)
                    Section {
                        Button {
                            createNewReport()
                        } label: {
                            exportButtonLabel
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
            .navigationTitle(String(localized: "报告", locale: AppLanguageManager.currentLocale))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $selectedReport) { report in
                InspectionFormView(report: report)
            }
        }
    }

    // MARK: - 顶部大按钮

    private var exportButtonLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.18))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "导出报告", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(String(localized: "新建一份巡检报告并导出 PDF", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.fg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    // MARK: - 空态(列表段为空时显示在"我的报告"section 里)

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "还没有报告", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.fg)
            Text(String(localized: "点上方「导出报告」开始第一份。", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 12))
                .foregroundStyle(Ink.fgDim)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 创建 / 删除

    private func createNewReport() {
        let report = InspectionReport()
        modelContext.insert(report)
        selectedReport = report
    }

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
