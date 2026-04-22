//
//  WeeklySummaryView.swift
//  SiteNote
//
//  生成本周总结文本,让用户复制或分享。
//

import SwiftUI
import SwiftData
import UIKit

/// 本周总结页(任务 10)。
struct WeeklySummaryView: View {
    @Query(filter: #Predicate<Note> { $0.deletedAt == nil }) private var allNotes: [Note]

    @State private var weekStart: Date = Self.startOfThisWeek()
    @State private var weekEnd: Date = Self.endOfThisWeek()
    @State private var summaryText: String = ""
    @State private var didGenerate: Bool = false
    @State private var showsShare: Bool = false

    var body: some View {
        Form {
            Section("统计范围") {
                DatePicker("开始", selection: $weekStart, displayedComponents: .date)
                    .font(.system(size: DesignTokens.FontSize.body))
                DatePicker("结束", selection: $weekEnd, in: weekStart..., displayedComponents: .date)
                    .font(.system(size: DesignTokens.FontSize.body))
            }

            Section {
                Button {
                    generate()
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text(didGenerate ? "重新生成" : "生成总结")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    }
                }
            }

            if didGenerate {
                Section {
                    Text(summaryText)
                        .font(.system(size: DesignTokens.FontSize.body))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    HStack {
                        Text("总结")
                        Spacer()
                        Button {
                            UIPasteboard.general.string = summaryText
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
                    Text("点右上图标可一键复制或分享出去。")
                        .font(.system(size: DesignTokens.FontSize.body))
                }
            }
        }
        .navigationTitle("本周总结")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .sheet(isPresented: $showsShare) {
            ShareSheet(items: [summaryText])
        }
    }

    private func generate() {
        let startOfStart = Calendar.current.startOfDay(for: weekStart)
        let endOfEnd = Calendar.current.date(
            bySettingHour: 23, minute: 59, second: 59, of: weekEnd
        ) ?? weekEnd
        let summary = WeeklySummaryService.summarize(
            notes: allNotes,
            weekStart: startOfStart,
            weekEnd: endOfEnd
        )
        summaryText = WeeklySummaryService.formatAsText(summary)
        didGenerate = true
    }

    // MARK: - Week defaults

    private static func startOfThisWeek() -> Date {
        let cal = Calendar.current
        let now = Date()
        if let interval = cal.dateInterval(of: .weekOfYear, for: now) {
            return interval.start
        }
        return cal.date(byAdding: .day, value: -7, to: now) ?? now
    }

    private static func endOfThisWeek() -> Date {
        Date()
    }
}
