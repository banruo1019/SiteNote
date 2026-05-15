//
//  DiaryConversionBanner.swift
//  SiteNote
//
//  顶部 banner:AI 从一条 note 抽出 ≥1 条 LogEntry 后,RecordView 顶部浮起
//  "AI 抽到 N 条 · [标为施工日志] [保留提醒]"。
//
//  数据源:DiaryConversionTracker.shared.pendingConversion(@Observable)。
//  - 标为施工日志:note.isDiaryRecord=true + deadline=.archive(永不提醒)+ cancel 推送
//  - 保留提醒:不动 note 状态(LogEntry 已写库,作为台账数据保留)
//
//  banner 不自动消失——LLM 误判 → 静默丢提醒是产品红线(project_ai_strategy.md)。
//  必须用户主动选一条路径。
//

import SwiftUI
import SwiftData

struct DiaryConversionBanner: View {
    @Environment(\.modelContext) private var modelContext
    @State private var tracker = DiaryConversionTracker.shared

    var body: some View {
        if let c = tracker.current {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ink.accentBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI 识别为施工日志?")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Ink.fg)
                        Text("已抽出 \(c.entriesCount) 条台账记录,需要把这条退出提醒吗?")
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("保留提醒") {
                        DiaryConversionTracker.shared.dismissCurrent()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.fgDim)

                    Button("标为施工日志") {
                        confirmDiary(noteID: c.noteID)
                        DiaryConversionTracker.shared.dismissCurrent()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ink.accentBlue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Ink.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Ink.line, lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeOut(duration: 0.25), value: tracker.current)
        }
    }

    /// 用户确认:把 note 翻成施工日记 + 改 deadline 为 .archive(永不提醒) + 取消已排推送。
    /// AI 已写入的 LogEntry 不动(它们是合法台账)。详情页可手动改 isDiaryRecord 回 false。
    private func confirmDiary(noteID: UUID) {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.id == noteID }
        )
        guard let note = try? modelContext.fetch(descriptor).first else { return }
        note.isDiaryRecord = true
        note.deadline = .archive
        note.dueDate = Deadline.archive.dueDate(from: note.createdAt)
        NotificationService.shared.cancel(for: note)
    }
}
