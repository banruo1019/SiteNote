//
//  AIStatusBar.swift
//  SiteNote
//
//  顶部细长状态条:让 AI 状态从"黑盒"变成"可见"。
//
//  显示:
//    - 引擎名(OpenAI / Apple / 本地不可用)
//    - 待确认的 NoteClassificationCard 数
//
//  Tap → 进 AISettingsDiagnostic(暂时跳到 InputAISettingsView)。
//
//  v1.2 大减负:删"今日 LogEntry 抽出条数"显示(LogEntry UI 已下架)。
//

import SwiftUI
import SwiftData

struct AIStatusBar: View {
    @Query(
        filter: #Predicate<Note> {
            $0.deletedAt == nil
                && $0.classificationJSON != nil
                && !$0.classificationConfirmed
        }
    )
    private var pendingClassifyNotes: [Note]

    @Environment(\.modelContext) private var modelContext
    @State private var failureTracker = AIFailureTracker.shared

    private var pendingCount: Int { pendingClassifyNotes.count }

    private var engineLabel: String {
        if AIService.isOpenAIAvailable { return "OpenAI ✓" }
        if AIService.isLocalAvailable { return "Apple ✓" }
        return String(localized: "未配置", locale: AppLanguageManager.currentLocale)
    }

    private var engineColor: Color {
        if AIService.isLanguageModelAvailable { return Ink.green }
        return Ink.red
    }

    var body: some View {
        NavigationLink(value: AIStatusDestination()) {
            // 失败可见性优先于常规状态:用户最需要知道"AI 现在不工作"。
            if failureTracker.hasRecentFailure, let f = failureTracker.lastFailure {
                failureRow(reason: f.reason)
            } else {
                normalRow
            }
        }
        .buttonStyle(.plain)
    }

    private var normalRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(engineColor)
            Text(engineLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(engineColor)
            if AIService.isLanguageModelAvailable, pendingCount > 0 {
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.dim)
                HStack(spacing: 3) {
                    Circle().fill(Ink.red).frame(width: 5, height: 5)
                    Text("\(pendingCount) 待确认")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Ink.red)
                        .monospacedDigit()
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Ink.dim)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
        .background(Ink.card.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: 0.5)
        }
    }

    private func failureRow(reason: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ink.red)
            Text("AI 失败 · \(reason)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ink.red)
                .lineLimit(1)
            Spacer()
            Text("检查设置")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Ink.red)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Ink.red.opacity(0.6))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
        .background(Ink.red.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.red.opacity(0.3)).frame(height: 0.5)
        }
    }
}

/// 给 NavigationStack 用的目的地标识(类型唯一即可)。
struct AIStatusDestination: Hashable {}
