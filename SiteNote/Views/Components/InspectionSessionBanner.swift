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
    /// 主 CTA 触感反馈的 trigger — 每次点击 toggle,sensoryFeedback 监听变化触发 haptic。
    @State private var completeTapTrigger: Int = 0

    /// 用户点"完成巡检"时回调 — caller 负责弹 EndInspectionSheet 走收尾流程。
    var onComplete: (InspectionReport) -> Void

    var body: some View {
        // 没有 active session → 不渲染任何东西,也不占布局空间。
        if let report = sessionManager.currentReport(in: modelContext) {
            content(for: report)
        } else if sessionManager.isActive {
            // ghost session:currentSessionID 非空但 SwiftData 查不到对应 report
            // (可能上次 session 中途 App 被杀 / 用户「清空所有内容」/ 数据迁移失败)。
            // 给用户一个一键清除出口,避免 RecordView 卡在 active 态没法回 idle。
            ghostSessionBanner
        }
    }

    /// ghost-session 兜底:橙底 + ✕ 清除按钮,点完 sessionManager.cancel() 立即恢复 idle。
    private var ghostSessionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "上次巡检状态异常", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(String(localized: "点右侧清除即可回到首页", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 8)
            Button {
                sessionManager.cancel()
            } label: {
                Text(String(localized: "清除", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.22)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Ink.amber)
        )
    }

    // MARK: - Banner 内容

    /// 设计决策(2026-05-17 重设计):
    /// 旧版把 CTA 放在右上"白 0.18 半透明胶囊"里 — 视觉弱、热区小、
    /// 在大屏(Pro Max)拇指够不着,且和 ⋯ menu 抢位看起来很挤。
    ///
    /// 新版 = Option A(底部全宽 CTA):
    /// - 上半部:信息密度区 — 脉冲红点 + "正在巡检" + 项目 + 副标,左对齐自然铺满。
    /// - 右上角:仅一个 ⋯ menu(取消巡检出口),小、安静、不抢戏。
    /// - 下半部:**全宽白色实心胶囊** "✓ 完成巡检",黑字,符合 M1
    ///   "黑/白/灰 90% 纪律";拇指区 + 44pt 最小高度 + 触感反馈,
    ///   戴薄手套也好按。
    @ViewBuilder
    private func content(for report: InspectionReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 上半部:信息行 + 右上角 ⋯ menu
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        PulsingDot(color: Ink.red)
                        Text(String(localized: "正在巡检", locale: AppLanguageManager.currentLocale))
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                    }

                    Text(titleLine(for: report))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(subtitleLine(for: report))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // ⋯ menu — 取消巡检的兜底出口,保留以防 ghost session。
                // 视觉做轻,因为主操作已经下放到底部大按钮。
                Menu {
                    Button(role: .destructive) {
                        sessionManager.cancel()
                    } label: {
                        Label(
                            String(localized: "取消巡检", locale: AppLanguageManager.currentLocale),
                            systemImage: "xmark.circle"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "更多", locale: AppLanguageManager.currentLocale))
            }

            // 下半部:全宽主 CTA — 白底黑字胶囊,44pt 高,触感反馈。
            Button {
                completeTapTrigger &+= 1
                onComplete(report)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                    Text(String(localized: "完成巡检", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Ink.fg)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    Capsule().fill(Ink.bg)
                )
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .medium), trigger: completeTapTrigger)
            .accessibilityLabel(String(localized: "完成巡检", locale: AppLanguageManager.currentLocale))
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
