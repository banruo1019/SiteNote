//
//  InsightsView.swift
//  SiteNote
//
//  Phase 10c:主动洞察。Reports 里的一页,展示从历史数据里挖出来的模式和建议。
//

import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.createdAt,
        order: .reverse
    ) private var allNotes: [Note]

    @State private var refreshTick = 0

    private var insights: [InsightsService.Insight] {
        _ = refreshTick
        return InsightsService.analyze(notes: allNotes)
    }

    var body: some View {
        Group {
            if insights.isEmpty {
                emptyState
            } else {
                List(insights) { insight in
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.medium) {
                        Image(systemName: insight.icon)
                            .font(.system(size: 22))
                            .foregroundStyle(color(for: insight.severity))
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(insight.title)
                                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            Text(insight.detail)
                                .font(.system(size: DesignTokens.FontSize.body))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("AI 洞察")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refreshTick += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("重新分析")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("一切都在轨道上")
                .font(.system(size: DesignTokens.FontSize.large, weight: .semibold))
            Text("没有发现值得关注的模式或风险。\n继续保持 👍")
                .font(.system(size: DesignTokens.FontSize.body))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func color(for severity: InsightsService.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
