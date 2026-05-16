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
    ) private var allNotes: [Note]

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    titleRow
                    ScrollView {
                        VStack(spacing: 0) {
                            mainCard
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

    // MARK: - Main card(唯一入口:出巡检报告)

    private var mainCard: some View {
        NavigationLink(value: ReportDestination.pdfHub) {
            HStack(spacing: 16) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Ink.accent)
                    .frame(width: 56, height: 56)
                    .background(Ink.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("出巡检报告")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                    Text("把这段时间的速记拼成 PDF 巡检日志,给上级/业主/法律存档")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.fgDim)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.dim)
            }
            .padding(20)
            .background(Ink.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Ink.line, lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .buttonStyle(.plain)
    }

    private var footerHint: some View {
        Text("想要的格式不在这里?进设置 → 高级 → 数据导出")
            .font(.system(size: 12))
            .foregroundStyle(Ink.fgDim)
            .frame(maxWidth: .infinity, alignment: .center)
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
            if profile.current == .pm {
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
