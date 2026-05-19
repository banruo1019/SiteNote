//
//  ReportsView.swift
//  SiteNote
//
//  v1.2 大减负:报告 Tab 只留「出巡检报告」一个入口。
//  本月统计 / 本周 sparkline / Top 5 / AI 发现 / 平面图 / 我们刻意不做 — 全砍。
//

import SwiftUI
import SwiftData

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.createdAt
    ) private var allNotesAllRoles: [Note]

    /// v1.5:只显示当前角色的 note(historical nil → PM)。
    private var allNotes: [Note] {
        allNotesAllRoles.filter { $0.belongsToCurrentRole }
    }

    /// 工地过滤器:nil = 全部工地。决定大卡片导 PDF 时预选哪些 Note。
    @State private var siteFilter: String? = nil

    /// 已知工地列表(从 Note + SiteTagsStorage 合并)。
    private var allSiteTags: [String] {
        let fromNotes = Set(allNotes.compactMap { $0.siteTag })
        let configured = Set(SiteTagsStorage.load())
        return Array(fromNotes.union(configured)).sorted()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    titleRow
                    ScrollView {
                        VStack(spacing: 0) {
                            mainCard
                            // v1.6 (en-v1):Site Team Reports 加 Recent Reports list 段(用 archive 数据)
                            if UserProfileManager.shared.current == .siteTeam {
                                recentReportsSection
                            }
                            footerHint
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: ReportDestination.self) { dest in
                destinationView(for: dest)
            }
            .navigationDestination(for: SettingsDestination.self) { _ in
                SettingsView()
            }
            .navigationDestination(for: Note.self) { note in
                NoteRouter(note: note)
            }
        }
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("报告")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Ink.fg)
            Spacer()
            siteFilterMenu
            SearchBarButton()
            NavigationLink(value: SettingsDestination()) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Ink.fgDim)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }

    /// 工地 picker — 共享组件 `SiteFilterMenu`。
    private var siteFilterMenu: some View {
        SiteFilterMenu(allTags: allSiteTags, selection: $siteFilter)
    }

    // MARK: - Main card(唯一入口:出巡检报告)
    //
    // PM:直接跳 PDFExportView,省掉 PDFHubView 这层中间页。
    // Engineer:仍走 PDFHubView,因为他要在 Inspection Report 和 PDF 巡检日志 间选。

    @ViewBuilder
    private var mainCard: some View {
        if UserProfileManager.shared.current == .siteTeam {
            NavigationLink {
                // R3#9:PM 选了 siteFilter 后跳 PDFExportView,带过去预选工地
                PDFExportView(initialSiteTag: siteFilter)
            } label: {
                mainCardLabel
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: ReportDestination.pdfHub) {
                mainCardLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var mainCardLabel: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                pdfThumb
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "PDF 巡检日志", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Ink.fgDim)
                    Text(String(localized: "出 PDF 巡检日志", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Ink.fg)
                        .padding(.top, 2)
                    Text(String(localized: "选日期 + 工地 + 速记,生成可直接发给业主的 PDF。", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.fgDim)
                        .lineSpacing(2)
                        .padding(.top, 4)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text(String(localized: "开始", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Ink.bg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Ink.fg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(18)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Ink.line, lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    /// PDF 缩略图占位 — M1 视觉锚点,告诉用户输出是 PDF。
    private var pdfThumb: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Ink.fg).frame(height: 6).clipShape(RoundedRectangle(cornerRadius: 1))
            Rectangle().fill(Ink.line2).frame(height: 3).clipShape(RoundedRectangle(cornerRadius: 1)).frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 12)
            Rectangle().fill(Ink.line2).frame(height: 3).clipShape(RoundedRectangle(cornerRadius: 1))
            Rectangle().fill(Ink.line2).frame(height: 3).clipShape(RoundedRectangle(cornerRadius: 1)).frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 18)
            Rectangle().fill(Ink.card2).frame(height: 18).clipShape(RoundedRectangle(cornerRadius: 2))
            Rectangle().fill(Ink.line2).frame(height: 3).clipShape(RoundedRectangle(cornerRadius: 1))
            Rectangle().fill(Ink.line2).frame(height: 3).clipShape(RoundedRectangle(cornerRadius: 1)).frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 24)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 72, height: 96)
        .background(Ink.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Ink.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: - Recent Reports (v1.6 en-v1)
    //
    // Site Team Reports Tab 的"已生成报告"列表。数据源:ReportArchiveService.listArchived()。
    // 行点击 → share(用 ShareSheet)。没归档 → 空态 hint("Tap above to create your first")。

    @State private var archivedReports: [ReportArchiveService.ArchivedReport] = []
    @State private var shareReportURL: URL?

    private var recentReportsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(String(localized: "RECENT REPORTS", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Ink.fgDim)
                if !archivedReports.isEmpty {
                    Text("\(archivedReports.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Ink.fg2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Ink.card)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 6)

            if archivedReports.isEmpty {
                Text(String(localized: "No reports yet. Tap above to create your first.", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.fgDim)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(archivedReports.prefix(20)) { report in
                        recentReportRow(report)
                        if report.id != archivedReports.prefix(20).last?.id {
                            Rectangle()
                                .fill(Ink.line)
                                .frame(height: 1)
                                .padding(.leading, 24 + 32 + 12)  // align with text
                        }
                    }
                }
            }
        }
        .task {
            archivedReports = ReportArchiveService.listArchived()
        }
        .sheet(isPresented: Binding(
            get: { shareReportURL != nil },
            set: { if !$0 { shareReportURL = nil } }
        )) {
            if let url = shareReportURL {
                ShareSheet(items: [url])
            }
        }
    }

    @ViewBuilder
    private func recentReportRow(_ report: ReportArchiveService.ArchivedReport) -> some View {
        Button {
            shareReportURL = report.url
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Ink.fg2)
                    .frame(width: 32, height: 32)
                    .background(Ink.card)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.projectFolder.isEmpty ? "—" : report.projectFolder)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.fg)
                        .lineLimit(1)
                    Text(recentReportSubtitle(report))
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.dim)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func recentReportSubtitle(_ report: ReportArchiveService.ArchivedReport) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_AU")
        df.dateStyle = .medium
        let dateStr = df.string(from: report.createdAt)
        return "\(dateStr) · \(report.sizeDescription)"
    }

    private var footerHint: some View {
        Text(String(localized: "v1.2 后报告 Tab 只保留 PDF 巡检日志一个入口。", locale: AppLanguageManager.currentLocale))
            .font(.system(size: 11))
            .foregroundStyle(Ink.fgDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 16)
    }

    @ViewBuilder
    private func destinationView(for dest: ReportDestination) -> some View {
        switch dest {
        case .pdfHub: PDFHubView()
        }
    }
}

enum ReportDestination: Hashable {
    case pdfHub
}

// MARK: - 子菜单:出 PDF
//
// v1.2 大减负:删 WeeklySummary / EOT 索赔 入口,只留 2 个 PDF 模板。
// PM 默认看到"PDF 巡检日志",Engineer 默认看到"Inspection Report"。

struct PDFHubView: View {
    @State private var profile = UserProfileManager.shared

    var body: some View {
        List {
            Section {
                if profile.current == .engineer {
                    NavigationLink {
                        InspectionReportListView()
                    } label: {
                        pdfRow(icon: "checkmark.seal.fill", title: String(localized: "Inspection Report", locale: AppLanguageManager.currentLocale), sub: String(localized: "工程师 · 巡检报告 + 图纸标注", locale: AppLanguageManager.currentLocale))
                    }
                }
                NavigationLink {
                    PDFExportView()
                } label: {
                    pdfRow(icon: "doc.text", title: String(localized: "PDF 巡检日志", locale: AppLanguageManager.currentLocale), sub: String(localized: "按日期或工地导出", locale: AppLanguageManager.currentLocale))
                }
            }

            // PM 视角:Inspection Report SVR 作为可选模板,放第二段不突出。
            if profile.current == .siteTeam {
                Section {
                    NavigationLink {
                        InspectionReportListView()
                    } label: {
                        pdfRow(icon: "checkmark.seal", title: String(localized: "Inspection Report", locale: AppLanguageManager.currentLocale), sub: String(localized: "(工程师专用模板 · 也可导)", locale: AppLanguageManager.currentLocale))
                    }
                } header: {
                    Text("其他模板")
                }
            }
        }
        .navigationTitle("出 PDF")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pdfRow(icon: String, title: String, sub: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Ink.fg2)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium))
                Text(sub).font(.system(size: 12)).foregroundStyle(Ink.fgDim)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Backup export (保留原样)

struct BackupExportView: View {
    @State private var shareURL: URL?
    @State private var errorMessage: String?
    @State private var isBuilding = false

    var body: some View {
        Form {
            Section {
                Text("生成一个包含所有录音 + 照片 + 平面图的 ZIP 文件,可通过分享面板存到 iCloud Drive / 邮件 / AirDrop。")
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.fgDim)
            }
            Section {
                Button {
                    exportZip()
                } label: {
                    HStack {
                        if isBuilding {
                            ProgressView()
                            Text("正在打包...")
                        } else {
                            Image(systemName: "externaldrive.fill.badge.timemachine")
                            Text("生成 ZIP 并分享")
                        }
                        Spacer()
                    }
                    .font(.system(size: 14, weight: .medium))
                }
                .disabled(isBuilding)
            }
        }
        .industrialForm()
        .navigationTitle("备份导出")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { shareURL.map { BackupShareURL(url: $0) } },
            set: { _ in shareURL = nil }
        )) { item in
            ShareSheet(items: [item.url])
        }
        .alert("出错了", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func exportZip() {
        isBuilding = true
        Task {
            do {
                let url = try BackupService.createBackupZip()
                shareURL = url
                isBuilding = false
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isBuilding = false
            }
        }
    }
}

private struct BackupShareURL: Identifiable {
    let id = UUID()
    let url: URL
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, ShareLog.self, configurations: config)
    return ReportsView().modelContainer(container)
}
