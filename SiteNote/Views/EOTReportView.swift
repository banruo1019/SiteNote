//
//  EOTReportView.swift
//  SiteNote
//
//  让用户选日期范围,分析出不利天气日,预览 + 一键导出 EOT PDF(任务 4)。
//

import SwiftUI
import SwiftData

/// 工期延误(EOT)报告页。
struct EOTReportView: View {
    @Query(filter: #Predicate<Note> { $0.deletedAt == nil }) private var allNotes: [Note]

    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var report: EOTAnalysisService.Report?
    @State private var exportURL: URL?
    @State private var errorMessage: String?
    @State private var isExporting = false
    @State private var isGeneratingLetter = false
    @State private var claimLetter: String?

    var body: some View {
        Form {
            Section("评估范围") {
                DatePicker("开始", selection: $startDate, in: ...Date(), displayedComponents: .date)
                    .font(.system(size: DesignTokens.FontSize.body))
                DatePicker("结束", selection: $endDate, in: startDate...Date(), displayedComponents: .date)
                    .font(.system(size: DesignTokens.FontSize.body))
            }

            Section {
                Button {
                    analyze()
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text(report == nil ? "分析不利天气" : "重新分析")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    }
                }
            }

            if let report {
                Section("分析结果") {
                    HStack {
                        Text("评估日数")
                            .font(.system(size: DesignTokens.FontSize.body))
                        Spacer()
                        Text("\(report.totalCalendarDays) 天")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("不利天气日")
                            .font(.system(size: DesignTokens.FontSize.body))
                        Spacer()
                        Text("\(report.claimableDays) 天")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .bold))
                            .foregroundStyle(report.claimableDays > 0 ? .orange : .secondary)
                    }

                    if report.claimableDays == 0 {
                        Text("评估期间没有记录到不利天气。确认该期间是否有现场记录,或调整日期。")
                            .font(.system(size: DesignTokens.FontSize.body))
                            .foregroundStyle(.secondary)
                    }
                }

                if !report.adverseDays.isEmpty {
                    Section("不利天气日明细") {
                        ForEach(report.adverseDays.indices, id: \.self) { i in
                            let day = report.adverseDays[i]
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                                Text("\(day.reason) · \(day.sourceNotes.count) 条记录")
                                    .font(.system(size: DesignTokens.FontSize.body))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section {
                    Button {
                        exportPDF()
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView()
                                Text("生成中……")
                            } else {
                                Image(systemName: "doc.richtext")
                                Text("导出 EOT 证据 PDF")
                            }
                        }
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    }
                    .disabled(report.claimableDays == 0 || isExporting)

                    Button {
                        generateClaimLetter()
                    } label: {
                        HStack {
                            if isGeneratingLetter {
                                ProgressView()
                                Text("AI 撰写中……")
                            } else {
                                Image(systemName: "sparkles")
                                Text("AI 起草正式 Claim Letter")
                            }
                        }
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                    }
                    .disabled(report.claimableDays == 0 || isGeneratingLetter || !AIService.isLanguageModelAvailable)
                } footer: {
                    Text("PDF 含封面(主张概要)+ 明细页(每天现场记录作为证据),可直接交业主或律师。\nAI 版会起草一封正式英文 claim letter 文本,适合发邮件用。")
                        .font(.system(size: DesignTokens.FontSize.body))
                }
            }
        }
        .sheet(item: Binding(
            get: { claimLetter.map { LetterItem(text: $0) } },
            set: { _ in claimLetter = nil }
        )) { item in
            ClaimLetterView(text: item.text)
        }
        .navigationTitle("EOT 工期延误")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .sheet(item: Binding(
            get: { exportURL.map { EOTShareItem(url: $0) } },
            set: { _ in exportURL = nil }
        )) { item in
            ShareSheet(items: [item.url])
        }
        .alert("生成失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func analyze() {
        report = EOTAnalysisService.analyze(
            notes: allNotes,
            startDate: startDate,
            endDate: endDate
        )
    }

    private func exportPDF() {
        guard let report else { return }
        isExporting = true
        Task {
            do {
                let url = try EOTAnalysisService.generatePDF(report: report)
                exportURL = url
                isExporting = false
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isExporting = false
            }
        }
    }

    private func generateClaimLetter() {
        guard let report else { return }
        isGeneratingLetter = true
        Task {
            do {
                let letter = try await NarrativeService.generateEOTClaimLetter(report: report)
                claimLetter = letter
                isGeneratingLetter = false
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isGeneratingLetter = false
            }
        }
    }
}

private struct EOTShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct LetterItem: Identifiable {
    let id = UUID()
    let text: String
}

/// 展示 AI 生成的 claim letter。可复制/分享。
private struct ClaimLetterView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var showsShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(size: DesignTokens.FontSize.body))
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("EOT Claim Letter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            UIPasteboard.general.string = text
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        Button {
                            showsShare = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showsShare) {
                ShareSheet(items: [text])
            }
        }
    }
}
