//
//  InspectionSessionBanner.swift
//  SiteNote
//
//  v1.4 巡检 session 顶部 sticky banner。
//
//  设计意图:
//  - active session 时,无论用户在 RecordView 还是 EngineerScheduleView,
//    顶部始终能看到"正在巡检 + 已收 N 条 + 一键完成"。
//  - nil session → EmptyView,不占任何高度。
//  - 自身不负责 padding/插入位置,由 caller 决定如何挂载。
//
//  集成点:
//  - RecordView 顶部
//  - EngineerScheduleView 顶部
//  - onComplete 回调里 caller 弹 EndInspectionSheet,本组件不直接结束 session。
//

import SwiftData
import SwiftUI

struct InspectionSessionBanner: View {
    @Environment(\.modelContext) private var modelContext
    @State private var sessionManager = InspectionSessionManager.shared

    /// 用户点"完成巡检"时回调 — caller 负责弹 EndInspectionSheet 走收尾流程。
    var onComplete: (InspectionReport) -> Void

    var body: some View {
        // 没有 active session → 不渲染任何东西,也不占布局空间。
        if let report = sessionManager.currentReport(in: modelContext) {
            content(for: report)
        }
    }

    // MARK: - Banner 内容

    @ViewBuilder
    private func content(for report: InspectionReport) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 左侧文字区
            VStack(alignment: .leading, spacing: 4) {
                // 顶部脉冲点 + "正在巡检"
                HStack(spacing: 6) {
                    PulsingDot(color: Ink.red)
                    Text(String(localized: "正在巡检", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                }

                // 主标:工程 · 巡检类型
                Text(titleLine(for: report))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // 副标:已收 N 条 · 开始 HH:MM
                Text(subtitleLine(for: report))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // 右侧"✓ 完成巡检"胶囊按钮(顶部对齐)
            Button {
                onComplete(report)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(localized: "完成巡检", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.white.opacity(0.18))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Ink.fg)
        )
    }

    // MARK: - 文案组合

    /// 主标行:"项目 · 巡检类型"。任一字段缺失则只显示另一字段。
    private func titleLine(for report: InspectionReport) -> String {
        let project = report.project.trimmingCharacters(in: .whitespaces)
        let type = report.inspectionType.trimmingCharacters(in: .whitespaces)
        switch (project.isEmpty, type.isEmpty) {
        case (false, false): return "\(project) · \(type)"
        case (false, true):  return project
        case (true, false):  return type
        case (true, true):
            // 兜底:连工程都没填,显示报告号
            return report.reportNo.isEmpty
                ? String(localized: "巡检中", locale: AppLanguageManager.currentLocale)
                : report.reportNo
        }
    }

    /// 副标行:"已收 N 条 · 开始 HH:MM"。
    private func subtitleLine(for report: InspectionReport) -> String {
        let count = report.noteIDs.count
        let countText = String(
            format: String(localized: "已收 %d 条", locale: AppLanguageManager.currentLocale),
            count
        )
        let timeText = String(
            format: String(localized: "开始 %@", locale: AppLanguageManager.currentLocale),
            Formatters.hourMinute.string(from: report.createdAt)
        )
        return "\(countText) · \(timeText)"
    }
}
