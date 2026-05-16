//
//  SavedReportsView.swift
//  SiteNote
//
//  "我的报告"列表:展示 ReportArchiveService 归档的所有 PDF。
//  入口在 Engineer / PM 设置 → 数据和关于 → 我的报告。
//
//  数据源:`ReportArchiveService.listArchived()`(纯文件系统,不走 SwiftData)。
//  操作:Tap 行 = ShareSheet;swipe = 删除(确认 alert);右上 = "在 Files 中打开"
//  (用 UIDocumentPickerViewController 跳转,需 iCloud 已配)。
//

import SwiftUI
import UIKit

struct SavedReportsView: View {
    @State private var reports: [ReportArchiveService.ArchivedReport] = []
    @State private var shareItemURL: URL?
    @State private var pendingDelete: ReportArchiveService.ArchivedReport?

    private var locale: Locale { AppLanguageManager.currentLocale }

    var body: some View {
        Group {
            if reports.isEmpty {
                emptyState
            } else {
                List {
                    statusSection
                    Section {
                        ForEach(reports) { report in
                            row(report)
                        }
                    } header: {
                        SectionHeader(String(localized: "已归档", locale: locale))
                    } footer: {
                        Text(String(
                            localized: "点开任一报告分享或另存。左滑删除会同时清掉本地 + iCloud 镜像。",
                            locale: locale
                        ))
                        .font(.system(size: 11))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(String(localized: "我的报告", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .onAppear { reload() }
        .sheet(item: Binding(
            get: { shareItemURL.map { ShareItem(url: $0) } },
            set: { _ in shareItemURL = nil }
        )) { item in
            ShareSheet(items: [item.url])
        }
        .alert(
            String(localized: "删除这份报告?", locale: locale),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { report in
            Button(String(localized: "取消", locale: locale), role: .cancel) {
                pendingDelete = nil
            }
            Button(String(localized: "删除", locale: locale), role: .destructive) {
                if let r = pendingDelete {
                    try? ReportArchiveService.delete(r)
                    reload()
                }
                pendingDelete = nil
            }
        } message: { report in
            Text(String(
                localized: "\(report.filename)\n本地 + iCloud 镜像都会删除,无法恢复。",
                locale: locale
            ))
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: ReportArchiveService.isICloudAvailable
                      ? "checkmark.icloud"
                      : "icloud.slash")
                .foregroundStyle(ReportArchiveService.isICloudAvailable ? .green : .secondary)
                Text(ReportArchiveService.diagnosticStatus())
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.fgDim)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(Ink.fgDim)
            Text(String(localized: "还没有归档的报告", locale: locale))
                .font(.system(size: 16, weight: .semibold))
            Text(String(
                localized: "导出 PDF 巡检日志 / SVR 巡检报告 后,会自动出现在这里。",
                locale: locale
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)

            if ReportArchiveService.isICloudAvailable {
                Text(String(
                    localized: "也会同步到 Files App → iCloud Drive → SiteNote",
                    locale: locale
                ))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.bg.ignoresSafeArea())
    }

    // MARK: - Row

    private func row(_ report: ReportArchiveService.ArchivedReport) -> some View {
        Button {
            shareItemURL = report.url
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Ink.accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.filename)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 8) {
                        Text(formatDate(report.createdAt))
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(report.sizeDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                        if report.hasICloudMirror {
                            Image(systemName: "icloud.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.blue)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = report
            } label: {
                Label(
                    String(localized: "删除", locale: locale),
                    systemImage: "trash"
                )
            }
        }
    }

    // MARK: - Helpers

    private func reload() {
        reports = ReportArchiveService.listArchived()
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    /// ShareSheet 的 item wrapper(`.sheet(item:)` 要 Identifiable)。
    private struct ShareItem: Identifiable {
        let url: URL
        var id: URL { url }
    }
}

#Preview {
    NavigationStack {
        SavedReportsView()
    }
}
