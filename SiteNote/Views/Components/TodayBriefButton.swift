//
//  TodayBriefButton.swift
//  SiteNote
//
//  统一的"今日简报"按钮:每个 tab 标题行右上角共享一个。
//
//  Tap → 收集今天的所有 Note + LogEntry → 跑 SiteDiaryPDFBuilder → 弹分享 sheet。
//  这是产品的"最后一公里"——把碎记录变成可发出去的 PDF。
//

import SwiftUI
import SwiftData

struct TodayBriefButton: View {
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: [SortDescriptor(\Note.createdAt)]
    ) private var allNotes: [Note]

    @Query(
        filter: #Predicate<LogEntry> { $0.deletedAt == nil },
        sort: [SortDescriptor(\LogEntry.startAt)]
    ) private var allEntries: [LogEntry]

    @State private var isGenerating: Bool = false
    @State private var sharePDFURL: URL?
    @State private var errorMessage: String?
    @Environment(\.modelContext) private var modelContext

    private var dayStart: Date { Calendar.current.startOfDay(for: Date()) }
    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }

    private var todayNotes: [Note] {
        allNotes.filter { $0.createdAt >= dayStart && $0.createdAt < dayEnd }
    }

    private var todayEntries: [LogEntry] {
        allEntries.filter { $0.startAt >= dayStart && $0.startAt < dayEnd }
    }

    private var hasContent: Bool {
        !todayNotes.isEmpty || !todayEntries.isEmpty
    }

    var body: some View {
        Button {
            generateBrief()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isGenerating ? "hourglass" : "square.and.arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                Text(isGenerating ? "生成中" : "简报")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.3)
            }
            .foregroundStyle(hasContent ? Ink.fg : Ink.dim)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(hasContent ? Ink.card : Color.clear, in: Capsule())
            .overlay(
                Capsule().strokeBorder(hasContent ? Ink.fg.opacity(0.2) : Ink.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isGenerating || !hasContent)
        .sheet(item: Binding(
            get: { sharePDFURL.map { TodayBriefShareItem(url: $0) } },
            set: { _ in sharePDFURL = nil }
        )) { item in
            ShareSheet(
                items: [item.url],
                onActivity: { activityType, completed in
                    let log = ShareLog(
                        format: "today-brief",
                        activityType: activityType,
                        completed: completed,
                        noteIDs: todayNotes.map { $0.id }
                    )
                    modelContext.insert(log)
                }
            )
        }
        .alert("生成出错", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func generateBrief() {
        isGenerating = true
        let notes = todayNotes
        let entries = todayEntries
        let weather = notes.compactMap { $0.weatherSummary }.first
        Task {
            do {
                let url = try await SiteDiaryPDFBuilder.build(
                    date: Date(),
                    siteTag: nil,        // 全部工地合并
                    entries: entries,
                    notes: notes,
                    weatherSummary: weather
                )
                sharePDFURL = url
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            isGenerating = false
        }
    }
}

private struct TodayBriefShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
