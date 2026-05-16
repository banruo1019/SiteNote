//
//  TrashView.swift
//  SiteNote
//
//  垃圾桶:显示已软删的 note。
//  - 左滑:永久删除(带确认,连带删音频/照片文件)
//  - 右滑:恢复(清空 deletedAt,重新调度推送)
//  - 顶部有"清空垃圾桶"按钮,一键永久删除所有
//

import SwiftUI
import SwiftData

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Note> { $0.deletedAt != nil },
        sort: \Note.deletedAt,
        order: .reverse
    ) private var trashedNotes: [Note]

    /// 软删后多少天自动永久删。
    static let retentionDays: Int = 30

    /// App 启动时调用:扫所有 `deletedAt < now - retentionDays` 的 note,做和 `purgeOne` 一样的清理
    /// (删音频/照片 + 历史遗留 LogEntry + Note 本身)。失败静默,不阻塞启动。
    /// 不在 main view 上调度;调用方自己保证在 modelContext 可用的线程。
    @MainActor
    static func runGarbageCollection(modelContext: ModelContext) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())
            ?? Date().addingTimeInterval(-Double(retentionDays) * 86_400)

        // 用 deletedAt < cutoff 间接表达"已删 + 已过保留期":
        // - deletedAt == nil → 整个比较 nil,Predicate 视为不匹配(SwiftData 的 #Predicate 对
        //   Optional<Date> 直接比较是支持的,但用 ?? 兜底会编译失败,见 SR-Note 编译报错)。
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { note in
                note.deletedAt != nil && note.deletedAt! < cutoff
            }
        )
        guard let expired = try? modelContext.fetch(descriptor), !expired.isEmpty else { return }

        let fm = FileManager.default
        for note in expired {
            // 音频
            if let audio = note.audioFilePath,
               let url = VoiceCaptureService.absoluteURL(forRelative: audio) {
                try? fm.removeItem(at: url)
            }
            // 照片
            for photo in note.photoPaths {
                if let url = PhotoStorage.absoluteURL(forRelative: photo) {
                    try? fm.removeItem(at: url)
                }
            }
            // 历史遗留 LogEntry(v1.2 减负前抽取的结构化条目,UI 已下架)。
            // 永久删 note 时一并清,避免 DB 留孤儿。
            let noteID = note.id
            if let entries = try? modelContext.fetch(FetchDescriptor<LogEntry>(
                predicate: #Predicate<LogEntry> { $0.sourceNoteID == noteID }
            )) {
                for e in entries { modelContext.delete(e) }
            }
            // 推送(防御性,软删时一般已 cancel)
            NotificationService.shared.cancel(for: note)
            modelContext.delete(note)
        }
        try? modelContext.save()
    }

    @State private var showsEmptyConfirm: Bool = false
    @State private var pendingPurge: Note?

    var body: some View {
        Group {
            if trashedNotes.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(trashedNotes) { note in
                            row(note: note)
                        }
                    } footer: {
                        Text("左滑永久删除 · 右滑恢复。永久删除不可撤销。\n超过 30 天的会在下次启动时自动永久删除。")
                            .font(.system(size: DesignTokens.FontSize.body))
                    }
                }
            }
        }
        .navigationTitle("垃圾桶")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .toolbar {
            if !trashedNotes.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showsEmptyConfirm = true
                    } label: {
                        Text("清空")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .alert("清空垃圾桶?", isPresented: $showsEmptyConfirm) {
            Button("永久删除 \(trashedNotes.count) 条", role: .destructive) {
                purgeAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有速记、对应的录音和照片会被删除,不可恢复。")
        }
        .alert(
            "永久删除这条?",
            isPresented: Binding(
                get: { pendingPurge != nil },
                set: { if !$0 { pendingPurge = nil } }
            )
        ) {
            Button("永久删除", role: .destructive) {
                if let note = pendingPurge { purgeOne(note) }
                pendingPurge = nil
            }
            Button("取消", role: .cancel) { pendingPurge = nil }
        } message: {
            Text("这条速记连同录音、照片会被彻底删除,不可恢复。")
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "trash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("垃圾桶空空如也")
                .font(.system(size: DesignTokens.FontSize.large, weight: .semibold))
            Text("删除的速记会出现在这里,可以恢复或永久删除。")
                .font(.system(size: DesignTokens.FontSize.body))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func row(note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(preview(note))
                .font(.system(size: DesignTokens.FontSize.body))
                .lineLimit(2)
            HStack(spacing: 6) {
                if let tag = note.siteTag {
                    Text(tag)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Capsule())
                }
                if !note.photoPaths.isEmpty {
                    Image(systemName: "photo").font(.system(size: 11))
                }
                if note.audioFilePath != nil {
                    Image(systemName: "waveform").font(.system(size: 11))
                }
                Spacer()
                Text(deletedAgoText(note))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                restore(note)
            } label: {
                Label("恢复", systemImage: "arrow.uturn.left.circle.fill")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingPurge = note
            } label: {
                Label("永久删除", systemImage: "trash.fill")
            }
        }
    }

    private func preview(_ note: Note) -> String {
        if !note.transcription.isEmpty {
            let limit = 50
            return note.transcription.count > limit
                ? String(note.transcription.prefix(limit)) + "…"
                : note.transcription
        }
        if !note.photoPaths.isEmpty || note.audioFilePath != nil {
            return String(localized: "(仅录音/照片)", locale: AppLanguageManager.currentLocale)
        }
        return String(localized: "(空速记)", locale: AppLanguageManager.currentLocale)
    }

    private func deletedAgoText(_ note: Note) -> String {
        guard let deletedAt = note.deletedAt else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .short
        let rel = formatter.localizedString(for: deletedAt, relativeTo: Date())
        return String(localized: "删于 \(rel)", locale: AppLanguageManager.currentLocale)
    }

    private func restore(_ note: Note) {
        note.deletedAt = nil
        if !note.isDone {
            NotificationService.shared.schedule(for: note)
        }
    }

    private func purgeOne(_ note: Note) {
        if let audio = note.audioFilePath,
           let url = VoiceCaptureService.absoluteURL(forRelative: audio) {
            try? FileManager.default.removeItem(at: url)
        }
        for photo in note.photoPaths {
            if let url = PhotoStorage.absoluteURL(forRelative: photo) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        // 历史遗留 LogEntry(v1.2 减负前抽取的结构化条目,UI 已下架)。
        // 永久删除 note 时一并清,避免 DB 留孤儿。
        let noteID = note.id
        if let entries = try? modelContext.fetch(FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { $0.sourceNoteID == noteID }
        )) {
            for e in entries { modelContext.delete(e) }
        }
        modelContext.delete(note)
    }

    private func purgeAll() {
        for note in trashedNotes { purgeOne(note) }
    }
}
