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
                Text(String(localized: "AI 处理中…", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .foregroundStyle(.white)
                // E1.2:取消按钮。OpenAI 卡 60s 时用户能主动放弃。
                Button {
                    cancelAITask()
                } label: {
                    Text(String(localized: "取消", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(DesignTokens.Spacing.large)
            .background(Color.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// E1.2:取消当前 AI Task 并立刻收尾 UI。
    /// 任务里 catch CancellationError 会直接 return,不弹 error。
    func cancelAITask() {
        currentAITask?.cancel()
        currentAITask = nil
        aiWorking = false
    }

    func runAIPolish() {
        let current = note.transcription
        guard !current.isEmpty else { return }
        aiWorking = true
        // E1.2:把 Task 句柄存起来,overlay 上"取消"按钮可以 cancel。
        let task: Task<Void, Never> = Task {
            do {
                let polished = try await AIService.shared.polishTranscription(current)
                // 取消后不要再写 UI 状态。
                if Task.isCancelled { return }
                if polished.trimmingCharacters(in: .whitespacesAndNewlines) == current.trimmingCharacters(in: .whitespacesAndNewlines) {
                    aiError = String(localized: "润色后和原文相同,无需更新。", locale: AppLanguageManager.currentLocale)
                } else {
                    polishPreview = PolishPreview(before: current, after: polished)
                }
            } catch is CancellationError {
                // 用户主动取消 → 静默,不弹 error。
                return
            } catch {
                if Task.isCancelled { return }
                aiError = String(localized: "润色失败: \(error.localizedDescription)", locale: AppLanguageManager.currentLocale)
            }
            if !Task.isCancelled {
                aiWorking = false
                currentAITask = nil
            }
        }
        currentAITask = task
    }

    func polishPreviewSheet(_ preview: PolishPreview) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                    Text("AI 润色结果")
                        .font(.system(size: DesignTokens.FontSize.large, weight: .bold))

                    labeledBlock(title: String(localized: "原文", locale: AppLanguageManager.currentLocale), text: preview.before, color: .secondary)
                    labeledBlock(title: String(localized: "润色后", locale: AppLanguageManager.currentLocale), text: preview.after, color: Ink.fg)

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
        // Engineer 视角:不调 AI 照片分析(任务 3)。aiMenu 已经把入口隐藏,
        // 这里再加一道防御:如有其它调用路径(测试 / 后续 refactor)也不会触发。
        guard !isEngineerProfile else { return }
        let paths = note.photoPaths
        guard !paths.isEmpty else { return }
        aiWorking = true
        // E1.2:Task 句柄保留,允许用户取消。
        let task: Task<Void, Never> = Task {
            var results: [PhotoAnalysisRow] = []
            for path in paths {
                if Task.isCancelled { return }
                guard let url = PhotoStorage.absoluteURL(forRelative: path),
                      let image = UIImage(contentsOfFile: url.path) else { continue }
                do {
                    let analysis = try await AIService.shared.analyzePhoto(image)
                    if Task.isCancelled { return }
                    results.append(PhotoAnalysisRow(
                        path: path,
                        image: image,
                        description: analysis.description,
                        hazard: analysis.suggestedHazard,
                        action: analysis.suggestedAction
                    ))
                } catch is CancellationError {
                    return
                } catch {
                    if Task.isCancelled { return }
                    results.append(PhotoAnalysisRow(
                        path: path,
                        image: image,
                        description: String(localized: "分析失败: \(error.localizedDescription)", locale: AppLanguageManager.currentLocale),
                        hazard: false,
                        action: nil
                    ))
                }
            }
            if Task.isCancelled { return }
            aiWorking = false
            currentAITask = nil
            if results.isEmpty {
                aiError = String(localized: "没有可分析的照片。", locale: AppLanguageManager.currentLocale)
            } else {
                photoAnalyses = PhotoAnalysesSheet(rows: results)
            }
        }
        currentAITask = task
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
                            .map { row -> String in
                                var s = "• \(row.description)"
                                if let act = row.action {
                                    s += "\n  " + String(localized: "建议: \(act)", locale: AppLanguageManager.currentLocale)
                                }
                                return s
                            }
                            .joined(separator: "\n")
                        let merged = [note.transcription, "", String(localized: "[AI 照片分析]", locale: AppLanguageManager.currentLocale), extras]
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
