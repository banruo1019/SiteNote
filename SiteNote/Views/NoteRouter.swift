//
//  NoteRouter.swift
//  SiteNote
//
//  Note 详情页的路由壳。
//  历史:之前 diary note 走单独的 DiaryNoteDetailView,现已合并到 NoteDetailView 内部。
//       NoteRouter 现在只是一层薄壳,
//       保留是为了不打破 .navigationDestination(for: Note.self) 调用方。
//

import SwiftUI

struct NoteRouter: View {
    let note: Note

    var body: some View {
        NoteDetailView(note: note)
    }
}
