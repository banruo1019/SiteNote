//
//  NoteRouter.swift
//  SiteNote
//
//  按 Note 类型路由到合适的详情页。
//  - isDiaryRecord == true  → DiaryNoteDetailView(精简版)
//  - 否则                    → NoteDetailView(完整版)
//
//  各 tab 的 `.navigationDestination(for: Note.self)` 统一用这个,而不是直接挂 NoteDetailView,
//  避免每个入口重复判断。
//

import SwiftUI

struct NoteRouter: View {
    let note: Note

    var body: some View {
        if note.isDiaryRecord {
            DiaryNoteDetailView(note: note)
        } else {
            NoteDetailView(note: note)
        }
    }
}
