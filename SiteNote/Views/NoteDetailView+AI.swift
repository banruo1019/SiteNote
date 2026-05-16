//
//  NoteDetailView+AI.swift
//  SiteNote
//
//  v1.2 AI 精简后:**只保留 AI 转写润色**(Apple Intelligence 本地)。
//  照片分析整套下架(GPT-4V 调用没了)。
//

import SwiftUI
import SwiftData

extension NoteDetailView {

    // MARK: - AI 润色 overlay

    var aiLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: DesignTokens.Spacing.medium) {
                ProgressView().scaleEffect(1.4).tint(.white)
                Text(String(localized: "AI 润色中…", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .foregroundStyle(.white)
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

    /// 取消当前 AI Task 并立刻收尾 UI。
    func cancelAITask() {
        currentAITask?.cancel()
        currentAITask = nil
        aiWorking = false
    }

    /// 手动触发 polish(详情页用户点"AI 润色"按钮时调)。
    /// Apple Intelligence 不可用时 polishTranscription 会直接返回原文,这里检测一致即提示。
    func runAIPolish() {
        let current = note.transcription
        guard !current.isEmpty else { return }
        aiWorking = true
        let task: Task<Void, Never> = Task {
            do {
                let polished = try await AIService.shared.polishTranscription(current)
                if Task.isCancelled { return }
                if polished.trimmingCharacters(in: .whitespacesAndNewlines)
                    == current.trimmingCharacters(in: .whitespacesAndNewlines) {
                    aiError = String(
                        localized: "润色后和原文相同,无需更新。(可能 Apple Intelligence 未启用)",
                        locale: AppLanguageManager.currentLocale
                    )
                } else {
                    polishPreview = PolishPreview(before: current, after: polished)
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                aiError = String(
                    localized: "润色失败: \(error.localizedDescription)",
                    locale: AppLanguageManager.currentLocale
                )
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
}
