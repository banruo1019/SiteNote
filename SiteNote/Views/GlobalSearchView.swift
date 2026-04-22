//
//  GlobalSearchView.swift
//  SiteNote
//
//  全局搜索:跨 Note (transcription / siteTag / otherTags) + LogEntry (subject) 一起搜。
//
//  入口:每个 tab 标题行右上角的放大镜按钮 → sheet 弹出。
//
//  搜索模式(默认关键字,可切换 AI 语义):
//    · 关键字:大小写不敏感的子串匹配,纯本地、瞬时
//    · AI 语义:跑 SemanticSearchService(已有 embedding 服务),适合"找漏电的事"这种模糊查询
//
//  结果:Note 和 LogEntry 按时间倒序混排。tap Note 进详情;tap LogEntry 也进它的源 Note。
//

import SwiftUI
import SwiftData

struct GlobalSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: [SortDescriptor(\Note.createdAt, order: .reverse)]
    ) private var allNotes: [Note]

    @Query(
        filter: #Predicate<LogEntry> { $0.deletedAt == nil },
        sort: [SortDescriptor(\LogEntry.createdAt, order: .reverse)]
    ) private var allEntries: [LogEntry]

    @State private var query: String = ""
    @State private var aiMode: Bool = false
    @State private var semanticHits: [Note]? = nil
    @State private var isSemanticSearching: Bool = false
    @FocusState private var queryFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                aiToggleRow
                Divider().overlay(Ink.line)
                resultsArea
            }
            .background(Ink.bg.ignoresSafeArea())
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .navigationDestination(for: Note.self) { note in
                NoteRouter(note: note)
            }
            .onAppear { queryFocused = true }
            .onChange(of: query) { _, _ in runSemanticIfNeeded() }
            .onChange(of: aiMode) { _, _ in runSemanticIfNeeded() }
        }
    }

    // MARK: - Top:输入 + AI 切换

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Ink.fgDim)
            TextField("搜笔记内容、工地名、工种...", text: $query)
                .font(.system(size: 14))
                .focused($queryFocused)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.fgDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Ink.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var aiToggleRow: some View {
        HStack {
            Toggle(isOn: $aiMode) {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11))
                    Text("AI 语义搜索")
                        .font(.system(size: 12, weight: .medium))
                    if isSemanticSearching {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(Ink.accent)
            .disabled(!AIService.isLanguageModelAvailable)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsArea: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            emptyHint
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    if !noteHits.isEmpty {
                        sectionHeader("速记 \(noteHits.count)")
                        ForEach(noteHits) { note in
                            noteResultRow(note)
                        }
                    }
                    if !entryHits.isEmpty {
                        sectionHeader("工地条目 \(entryHits.count)")
                        ForEach(entryHits) { entry in
                            entryResultRow(entry)
                        }
                    }
                    if noteHits.isEmpty && entryHits.isEmpty {
                        Text("没找到匹配")
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.fgDim)
                            .padding(.top, 32)
                    }
                }
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 60)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(Ink.dim)
            Text("搜笔记内容 / 工地 / 工种 / 设备")
                .font(.system(size: 13))
                .foregroundStyle(Ink.fgDim)
            if AIService.isLanguageModelAvailable {
                Text("打开 AI 语义搜索可以问"漏电的事"这类模糊查询")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.dim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Ink.fgDim)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func noteResultRow(_ note: Note) -> some View {
        NavigationLink(value: note) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if note.isDiaryRecord {
                        Image(systemName: "person.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Ink.accentBlue)
                    }
                    if note.isHazard {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Ink.red)
                    }
                    Text(note.transcription.isEmpty ? "(仅录音/照片)" : highlight(note.transcription))
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.fg)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let s = note.siteTag, !s.isEmpty {
                        Text(s)
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                    }
                    Text(timeAgo(note.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.dim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Ink.line).frame(height: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func entryResultRow(_ entry: LogEntry) -> some View {
        // 找到源 Note 才能 NavigationLink。找不到只显示文字。
        let sourceNote = allNotes.first { $0.id == entry.sourceNoteID }
        return Group {
            if let note = sourceNote {
                NavigationLink(value: note) { entryRowBody(entry) }
                    .buttonStyle(.plain)
            } else {
                entryRowBody(entry)
            }
        }
    }

    private func entryRowBody(_ entry: LogEntry) -> some View {
        HStack(spacing: 10) {
            Text(iconFor(entry.kind))
                .font(.system(size: 14))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.kind.displayName)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.3)
                        .textCase(.uppercase)
                        .foregroundStyle(Ink.dim)
                    Text(highlight(entry.subject))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.fg)
                    if let q = entry.quantity, q > 0, !entry.isAbsent {
                        Text("×\(q)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Ink.fgDim)
                            .monospacedDigit()
                    }
                }
                if let n = entry.note, !n.isEmpty {
                    Text(n)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                }
            }
            Spacer()
            Text(timeAgo(entry.startAt))
                .font(.system(size: 11))
                .foregroundStyle(Ink.dim)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: 0.5)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Filtering

    private var noteHits: [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if aiMode, let sem = semanticHits { return sem }

        let lower = trimmed.lowercased()
        return allNotes.filter { n in
            n.transcription.lowercased().contains(lower)
                || (n.siteTag?.lowercased().contains(lower) ?? false)
                || (n.locationAddress?.lowercased().contains(lower) ?? false)
                || n.otherTags.contains(where: { $0.lowercased().contains(lower) })
        }
    }

    private var entryHits: [LogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        return allEntries.filter { e in
            e.subject.lowercased().contains(lower)
                || (e.note?.lowercased().contains(lower) ?? false)
                || (e.siteTag?.lowercased().contains(lower) ?? false)
        }
    }

    private func runSemanticIfNeeded() {
        guard aiMode else {
            semanticHits = nil
            return
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            semanticHits = nil
            return
        }
        isSemanticSearching = true
        let snapshot = allNotes
        Task {
            let result = await SemanticSearchService.shared.search(query: trimmed, in: snapshot)
            semanticHits = result
            isSemanticSearching = false
        }
    }

    // MARK: - Helpers

    private func iconFor(_ k: LogKind) -> String {
        switch k {
        case .person: return "👥"
        case .plant: return "🚜"
        case .delivery: return "📦"
        case .visitor: return "🧑"
        case .event: return "⚠️"
        }
    }

    private func timeAgo(_ d: Date) -> String {
        let secs = Date().timeIntervalSince(d)
        if secs < 3600 { return "\(Int(secs / 60)) 分钟前" }
        if secs < 86400 { return "\(Int(secs / 3600)) 小时前" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日"
        return f.string(from: d)
    }

    /// 简易高亮——给文本套一下,实际命中的子串用强调色。
    /// 暂时返回原文(未来可加 attributed string 高亮)。
    private func highlight(_ text: String) -> String { text }
}
