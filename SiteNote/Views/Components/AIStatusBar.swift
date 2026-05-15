//
//  AIStatusBar.swift
//  SiteNote
//
//  顶部细长状态条:让 AI 状态从"黑盒"变成"可见"。
//
//  显示:
//    - 引擎名(OpenAI / Apple / 本地不可用)
//    - 今日 LogEntry 抽出条数
//    - 待确认的 NoteClassificationCard 数
//
//  Tap → 进 AISettingsDiagnostic(暂时跳到 InputAISettingsView)。
//
//  挂在每个 tab 的标题下方。挂法:用 modifier 包一下根 ZStack 即可,
//  不侵入各 tab 的现有 layout。
//

import SwiftUI
import SwiftData

struct AIStatusBar: View {
    @Query(filter: #Predicate<LogEntry> { $0.deletedAt == nil })
    private var allEntries: [LogEntry]

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

    private var todayEntryCount: Int {
        let dayStart = Calendar.current.startOfDay(for: Date())
        return allEntries.filter { $0.createdAt >= dayStart }.count
    }

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
            if AIService.isLanguageModelAvailable {
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.dim)
                Text("今日 \(todayEntryCount) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
                    .monospacedDigit()
                if pendingCount > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(Ink.red).frame(width: 5, height: 5)
                        Text("\(pendingCount) 待确认")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Ink.red)
                            .monospacedDigit()
                    }
                    .padding(.leading, 2)
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
