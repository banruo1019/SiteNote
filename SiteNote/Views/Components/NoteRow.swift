//
//  NoteRow.swift
//  SiteNote
//
//  M1 Linear 风列表行:
//  - 白底,无卡片填充
//  - 左侧 6pt 圆点(紧迫度色:红/黑/灰)
//  - 正文 14pt,line-height 1.45
//  - 元信息 11pt Ink.fgDim:工地 · 时间 · [wave 时长] · [photo N]
//  - 底部 border-bottom: 1px Ink.line
//

import SwiftUI

extension Urgency {
    var m1DotColor: Color {
        switch self {
        case .overdue, .day:       return Ink.red
        case .threeDays, .week:    return Ink.fg
        case .future:              return Ink.dim
        }
    }

    // 旧代码可能还在引用这两个名字,保留别名
    var dotColor: Color { m1DotColor }
    var backgroundColor: Color? { nil }
}

struct NoteRow: View {
    let note: Note
    let urgency: Urgency?

    private var isJustAdded: Bool {
        HighlightTracker.shared.highlightedNoteID == note.id
    }

    private var dotColor: Color {
        // 隐患优先,无论紧迫度都显红
        if note.isHazard { return Ink.red }
        if let u = urgency { return u.m1DotColor }
        return Ink.dim
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 5) {
                    if note.isHazard {
                        HStack(spacing: 4) {
                            Circle().fill(Ink.red).frame(width: 4, height: 4)
                            Text("隐患")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.5)
                                .textCase(.uppercase)
                                .foregroundStyle(Ink.red)
                        }
                    }
                    Text(previewText)
                        .font(.system(size: 14))
                        .tracking(-0.1)
                        .lineSpacing(2)
                        .foregroundStyle(note.isDone ? Ink.fgDim : Ink.fg)
                        .strikethrough(note.isDone)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    metaRow
                }
                Spacer(minLength: 0)
            }
            // 左 24 右 8:右侧留给 NavigationLink 的 chevron,不再拉开 24pt 空隙。
            .padding(.leading, 24)
            .padding(.trailing, 8)
            .padding(.vertical, 12)

            Rectangle().fill(Ink.line).frame(height: 1)
        }
        .background(isJustAdded ? Ink.card : Color.clear)
        .animation(.easeOut(duration: 0.5), value: isJustAdded)
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            if let site = note.siteTag {
                Text(site)
            } else {
                Text("未命名").foregroundStyle(Ink.dim)
            }
            Text("·")
            Text(relativeTime)
            ForEach(note.otherTags.prefix(2), id: \.self) { tag in
                Text("·")
                Text(tag)
                    .foregroundStyle(SubTagsStorage.color(name: tag))
            }
            if note.audioFilePath != nil {
                Text("·")
                HStack(spacing: 3) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                }
            }
            if !note.photoPaths.isEmpty {
                Text("·")
                HStack(spacing: 3) {
                    Image(systemName: "photo")
                        .font(.system(size: 10))
                    Text("\(note.photoPaths.count)")
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .foregroundStyle(Ink.fgDim)
        .lineLimit(1)
    }

    private var previewText: String {
        if note.transcription.isEmpty {
            return "(仅录音/照片)"
        }
        return note.transcription
    }

    private var relativeTime: String {
        NoteListViewModel.relativeTime(note.createdAt)
    }
}
