//
//  DailyNarrativeView.swift
//  SiteNote
//
//  Phase 10b:选一天 → 用 AI 把当天 notes 拼成施工日志。可复制/分享。
//

import SwiftUI
import SwiftData

struct DailyNarrativeView: View {
    @Query(filter: #Predicate<Note> { $0.deletedAt == nil }) private var allNotes: [Note]

    @State private var selectedDate: Date = Date()
    @State private var narrative: String = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showsShare = false

    private var notesOnSelectedDate: [Note] {
        let cal = Calendar.current
        return allNotes.filter {
            cal.isDate($0.createdAt, inSameDayAs: selectedDate)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        Form {
            Section("日期") {
                DatePicker("生成哪一天的日志", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                    .font(.system(size: DesignTokens.FontSize.body))
            }

            Section {
                HStack {
                    Text("当天记录")
                        .font(.system(size: DesignTokens.FontSize.body))
                    Spacer()
                    Text("\(notesOnSelectedDate.count) 条")
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    generate()
                } label: {
                    HStack {
                        if isGenerating {
                            ProgressView()
                            Text("AI 正在撰写…")
                        } else {
                            Image(systemName: "sparkles")
                            Text(narrative.isEmpty ? "用 AI 生成施工日志" : "重新生成")
                                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        }
                        Spacer()
                    }
                }
                .disabled(notesOnSelectedDate.isEmpty || isGenerating)
            } footer: {
                if !AIService.isLanguageModelAvailable {
                    Text("⚠️ 本机不支持 Apple Intelligence,无法生成。")
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(Ink.red)
                }
            }

            if !narrative.isEmpty {
                Section {
                    Text(narrative)
                        .font(.system(size: DesignTokens.FontSize.body))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    HStack {
                        Text("施工日志")
                        Spacer()
                        Button {
                            UIPasteboard.general.string = narrative
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        Button {
                            showsShare = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                } footer: {
                    Text("点右上图标复制全文或分享。")
                        .font(.system(size: DesignTokens.FontSize.body))
                }
            }
        }
        .navigationTitle("AI 日记叙事")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .sheet(isPresented: $showsShare) {
            ShareSheet(items: [narrative])
        }
        .alert("生成失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func generate() {
        let notes = notesOnSelectedDate
        let date = selectedDate
        isGenerating = true
        Task {
            do {
                let result = try await NarrativeService.generateDailyNarrative(notes: notes, date: date)
                narrative = result
                isGenerating = false
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isGenerating = false
            }
        }
    }
}
