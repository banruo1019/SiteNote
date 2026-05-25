//
//  UndoToast.swift
//  SiteNote
//
//  录音保存后的浮卡(M1)。覆盖在 mic+camera 大按钮上方,不替换它们。
//
//  v1.5 双模式:
//   • **PM 模式**:双行,4 等宽按钮一字排
//       ┌────────────────────────────────────┐
//       │ ✓ 已记录 · 摘要 ...     [撤销 4s]   │
//       │ [今日] [3 天 ✓] [7 天] [详情 ›]     │
//       └────────────────────────────────────┘
//      4 按钮 minHeight 44pt(Apple HIG 触摸目标),详情贴最右(右手拇指 sweet spot)。
//      点任何按钮 → 立即 dismiss toast(由 caller 在 callback 里调 dismissToastManually)。
//
//   • **Engineer 模式**:单行,整行 tap = 详情
//       ┌────────────────────────────────────┐
//       │ ✓ 已记录 · 摘要 ...     [撤销 4s]   │
//       └────────────────────────────────────┘
//      Engineer 工作流是 session-based,deadline 通常不用,简化为只详情 + 撤销。
//

import SwiftUI

struct UndoToast: View {
    let message: String
    let secondsRemaining: Int
    /// PM 模式 = true 显示 4 等宽按钮双行;Engineer 模式 = false 走单行老布局。
    let showsDeadlineActions: Bool
    /// 当前 note 的 deadline — 决定 PM 模式哪个 chip 高亮。Engineer 模式不读这个值。
    let currentDeadline: Deadline

    let onDetail: () -> Void
    let onUndo: () -> Void
    /// 用户点 chip 时调用。仅 PM 模式触发 — Engineer 模式 chip 不渲染所以永远不会调。
    let onSetDeadline: (Deadline) -> Void

    var body: some View {
        Group {
            if showsDeadlineActions {
                pmBody
            } else {
                engineerBody
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, showsDeadlineActions ? 12 : 10)
        .background(Ink.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Ink.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 16, y: 4)
    }

    // MARK: - PM 模式(双行 + 4 等宽按钮)

    private var pmBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            pmTopRow
            pmActionRow
        }
    }

    /// PM 第一行:摘要(纯展示) + 撤销
    private var pmTopRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Ink.fg)
            Text(prefixedMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.fg)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            undoCapsule
        }
    }

    /// PM 第二行:4 个等宽按钮(3 个 chip + 1 详情)
    private var pmActionRow: some View {
        HStack(spacing: 8) {
            chipButton(
                .today,
                label: String(localized: "今日", locale: AppLanguageManager.currentLocale)
            )
            chipButton(
                .threeDays,
                label: String(localized: "3 天", locale: AppLanguageManager.currentLocale)
            )
            chipButton(
                .thisWeek,
                label: String(localized: "7 天", locale: AppLanguageManager.currentLocale)
            )
            detailButton
        }
    }

    // MARK: - Engineer 模式(单行,整行 tap = 详情)

    private var engineerBody: some View {
        HStack(spacing: 10) {
            // 左:整块可点 = 进详情
            Button(action: onDetail) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Ink.fg)
                    Text(prefixedMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.fg)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            undoCapsule
        }
    }

    // MARK: - 子组件

    /// 撤销胶囊 — 两个模式共用。
    private var undoCapsule: some View {
        Button(action: onUndo) {
            HStack(spacing: 4) {
                Text(String(localized: "撤销", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 12, weight: .semibold))
                Text("\(secondsRemaining)s")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Ink.fgDim)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(Ink.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Ink.card)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(
            localized: "撤销刚才的录音,\(secondsRemaining) 秒后自动消失",
            locale: AppLanguageManager.currentLocale
        ))
    }

    /// deadline chip:当前 deadline **深灰**底白字(Ink.fg2),其他白底深字 + 1pt 描边。
    /// 故意**不用纯黑** — 跟下面 detailButton 的纯黑 Ink.fg 区分主次,避免视觉混淆
    /// (AI 语音识别预选的 chip ≠ 用户主操作的「详情」)。
    /// `.frame(maxWidth: .infinity, minHeight: 44)` 让 4 按钮等宽 + 满足 Apple HIG 触摸目标。
    @ViewBuilder
    private func chipButton(_ kind: Deadline, label: String) -> some View {
        let isOn = currentDeadline == kind
        Button {
            onSetDeadline(kind)
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Ink.fg)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(isOn ? Ink.fg2 : Ink.bg))
                .overlay(
                    Capsule().stroke(isOn ? Color.clear : Ink.line, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// 详情按钮:主操作风格,黑底白字 + chevron.right,贴最右(右手拇指 sweet spot)。
    private var detailButton: some View {
        Button(action: onDetail) {
            HStack(spacing: 3) {
                Text(String(localized: "详情", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(Ink.fg))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "打开详情", locale: AppLanguageManager.currentLocale))
    }

    // MARK: - Helpers

    /// 用户提示语:已记录 · 摘要。摘要为空时回落到纯标识。
    private var prefixedMessage: String {
        let prefix = String(localized: "已记录", locale: AppLanguageManager.currentLocale)
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? prefix : "\(prefix) · \(trimmed)"
    }
}
