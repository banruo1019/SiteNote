//
//  NoteTimelineRow.swift
//  SiteNote
//
//  M1 时间线 row — 主屏"记" Tab 主列表的单条 Note 视觉单元。
//  从 RecordView 提取出来,让 RecordView 不再背 ~140 行 row 渲染逻辑。
//  本 view **只渲染**,不管 NavigationLink 也不管 swipeActions —— 那些
//  绑 parent 状态(navPath / softDelete / toggleDone),留在 parent 包一层。
//
//  布局:状态点 / HH:MM / 摘要 + metaLine。
//  状态点:已完成空心圈、未完成实心(隐患红、其他黑)。
//  metaLine:工地 chip + 分类 + 录音/照片/隐患 icons。
//

import SwiftUI

struct NoteTimelineRow: View {
    let note: Note
    /// v1.6 (en-v1):Site Team 主屏「已逾期」段把这个传 true → 圆点染红。
    /// 默认 false 保持原行为(Engineer 主屏 / 详情页 等其他场景不变)。
    var isOverdue: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusDot
                .padding(.top, 7)
            Text(Formatters.hourMinute.string(from: note.createdAt))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Ink.fgDim)
                .monospacedDigit()
                .frame(width: 38, alignment: .leading)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(summary)
                    .font(.system(size: 14, weight: note.isDone ? .regular : .medium))
                    .foregroundStyle(
                        note.isDone ? Ink.fgDim : (note.isHazard ? Ink.red : Ink.fg)
                    )
                    .strikethrough(note.isDone, color: Ink.fgDim)
                    .lineLimit(2)
                metaLine
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: 1)
                .padding(.leading, 24)
                .padding(.trailing, 24)
        }
        .contentShape(Rectangle())
    }

    /// 行首状态点 — 已完成空心圈,未完成实心(隐患 / 逾期红、其他黑)。
    @ViewBuilder
    private var statusDot: some View {
        if note.isDone {
            Circle()
                .strokeBorder(Ink.dim, lineWidth: 1.5)
                .frame(width: 6, height: 6)
        } else {
            Circle()
                .fill((note.isHazard || isOverdue) ? Ink.red : Ink.fg)
                .frame(width: 6, height: 6)
        }
    }

    /// 副信息:工地 chip · 分类 — 右侧 录音/照片/隐患 icon。
    @ViewBuilder
    private var metaLine: some View {
        HStack(spacing: 8) {
            if let site = note.siteTag, !site.isEmpty {
                Text(site)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Ink.fg2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Ink.card)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if let tag = note.otherTags.first {
                Text(tag)
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
            }
            Spacer(minLength: 0)
            if note.audioFilePath != nil {
                Image(systemName: "waveform")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
            }
            if !note.photoPaths.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "photo")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                    if note.photoPaths.count > 1 {
                        Text("\(note.photoPaths.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
            }
            if note.isHazard {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.red)
            }
        }
    }

    /// 转写文本的摘要(空时给占位)。
    private var summary: String {
        let t = note.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return String(localized: "(仅录音/照片)", locale: AppLanguageManager.currentLocale)
    }
}
