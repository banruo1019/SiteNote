//
//  NoteDetailView+AI.swift
//  SiteNote
//
//  从 NoteDetailView.swift 拆分出来的 AI 操作:
//  - aiLoadingOverlay
//  - runAIPolish / polishPreviewSheet / labeledBlock
//  - runPhotoAnalysis / photoAnalysesSheet / photoAnalysisRowView
//

import SwiftUI
import SwiftData
import UIKit

extension NoteDetailView {

    // MARK: - AI 操作

    var aiLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: DesignTokens.Spacing.medium) {
                ProgressView().scaleEffect(1.4).tint(.white)
                Text("AI 处理中…")
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(DesignTokens.Spacing.large)
            .background(Color.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    func runAIPolish() {
        let current = note.transcription
        guard !current.isEmpty else { return }
        aiWorking = true
        Task {
            do {
                let polished = try await AIService.shared.polishTranscription(current)
                if polished.trimmingCharacters(in: .whitespacesAndNewlines) == current.trimmingCharacters(in: .whitespacesAndNewlines) {
                    aiError = "润色后和原文相同,无需更新。"
                } else {
                    polishPreview = PolishPreview(before: current, after: polished)
                }
            } catch {
                aiError = "润色失败: \(error.localizedDescription)"
            }
            aiWorking = false
        }
    }

    func polishPreviewSheet(_ preview: PolishPreview) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                    Text("AI 润色结果")
                        .font(.system(size: DesignTokens.FontSize.large, weight: .bold))

                    labeledBlock(title: "原文", text: preview.before, color: .secondary)
                    labeledBlock(title: "润色后", text: preview.after, color: Ink.fg)

                    HStack(spacing: DesignTokens.Spacing.small) {
                        Button("保留原文") {
                            polishPreview = nil
                        }
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: DesignTokens.ButtonSize.minTap)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            note.transcription = preview.after
                            polishPreview = nil
                        } label: {
                            Text("采用润色版")
                                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: DesignTokens.ButtonSize.minTap)
                                .background(Ink.fg)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("AI 润色")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    func labeledBlock(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: DesignTokens.FontSize.large))
                .textSelection(.enabled)
                .padding(DesignTokens.Spacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Ink.card2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    func runPhotoAnalysis() {
        let paths = note.photoPaths
        guard !paths.isEmpty else { return }
        aiWorking = true
        Task {
            var results: [PhotoAnalysisRow] = []
            for path in paths {
                guard let url = PhotoStorage.absoluteURL(forRelative: path),
                      let image = UIImage(contentsOfFile: url.path) else { continue }
                do {
                    let analysis = try await AIService.shared.analyzePhoto(image)
                    results.append(PhotoAnalysisRow(
                        path: path,
                        image: image,
                        description: analysis.description,
                        hazard: analysis.suggestedHazard,
                        action: analysis.suggestedAction
                    ))
                } catch {
                    results.append(PhotoAnalysisRow(
                        path: path,
                        image: image,
                        description: "分析失败: \(error.localizedDescription)",
                        hazard: false,
                        action: nil
                    ))
                }
            }
            aiWorking = false
            if results.isEmpty {
                aiError = "没有可分析的照片。"
            } else {
                photoAnalyses = PhotoAnalysesSheet(rows: results)
            }
        }
    }

    func photoAnalysesSheet(_ sheet: PhotoAnalysesSheet) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                    let anyHazard = sheet.rows.contains { $0.hazard }
                    if anyHazard && !note.isHazard {
                        Button {
                            note.isHazard = true
                            NotificationService.shared.schedule(for: note)
                            photoAnalyses = nil
                        } label: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("AI 检测到隐患 · 标记这条为隐患")
                            }
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: DesignTokens.ButtonSize.minTap)
                            .background(Ink.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    ForEach(sheet.rows) { row in
                        photoAnalysisRowView(row)
                    }

                    Button {
                        let extras = sheet.rows
                            .map { "• \($0.description)" + ($0.action.map { "\n  建议: \($0)" } ?? "") }
                            .joined(separator: "\n")
                        let merged = [note.transcription, "", "[AI 照片分析]", extras]
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                        note.transcription = merged
                        photoAnalyses = nil
                    } label: {
                        HStack {
                            Image(systemName: "plus.bubble")
                            Text("把分析追加到转写")
                        }
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: DesignTokens.ButtonSize.minTap)
                        .background(Ink.fg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("AI 分析照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { photoAnalyses = nil }
                }
            }
        }
    }

    func photoAnalysisRowView(_ row: PhotoAnalysisRow) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.medium) {
            Image(uiImage: row.image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                if row.hazard {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("疑似隐患")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.red)
                    }
                }
                Text(row.description)
                    .font(.system(size: DesignTokens.FontSize.body))
                if let action = row.action, !action.isEmpty {
                    Text("建议: \(action)")
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.small)
        .background(Ink.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
