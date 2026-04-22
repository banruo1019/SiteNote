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

    private var todayEntryCount: Int {
        let dayStart = Calendar.current.startOfDay(for: Date())
        return allEntries.filter { $0.createdAt >= dayStart }.count
    }

    private var pendingCount: Int { pendingClassifyNotes.count }

    private var engineLabel: String {
        if AIService.isOpenAIAvailable { return "OpenAI ✓" }
        if AIService.isLocalAvailable { return "Apple ✓" }
        return "未配置"
    }

    private var engineColor: Color {
        if AIService.isLanguageModelAvailable { return Ink.green }
        return Ink.red
    }

    var body: some View {
        NavigationLink(value: AIStatusDestination()) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 10))
                    .foregroundStyle(engineColor)
                Text("AI:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Ink.fgDim)
                Text(engineLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(engineColor)
                if AIService.isLanguageModelAvailable {
                    Text("·")
                        .foregroundStyle(Ink.dim)
                    Text("今日识别 \(todayEntryCount)")
                        .font(.system(size: 10))
                        .foregroundStyle(Ink.fgDim)
                        .monospacedDigit()
                    if pendingCount > 0 {
                        Text("·")
                            .foregroundStyle(Ink.dim)
                        HStack(spacing: 2) {
                            Circle().fill(Ink.red).frame(width: 5, height: 5)
                            Text("\(pendingCount) 待确认")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Ink.red)
                                .monospacedDigit()
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Ink.dim)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
            .background(Ink.card.opacity(0.5))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Ink.line).frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

/// 给 NavigationStack 用的目的地标识(类型唯一即可)。
struct AIStatusDestination: Hashable {}
