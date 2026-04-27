//
//  UndoToast.swift
//  SiteNote
//
//  录音保存后的浮窗。重设计原则:**只放命令,不放属性**——
//  - 命令(改 note 的类型/状态/存在):存为日记 / 进详情 / 撤销 → 留在 toast
//  - 属性(note 的字段:isHazard / deadline / siteTag / subTags 等)→ 进详情页改
//
//  布局:
//  - Row 1: ✓ 摘要(左) + 倒计时小字(右上) + 撤销按钮(右上)
//  - Row 2: [📓 存为日记] [✎ 进详情]  —— 两个明确的命令
//
//  默认沉默最舒服:5s 不动 = 自动消失,note 留在 Inbox(默认),之后在「日志 → 待分类」段慢慢分。
//

import SwiftUI

struct UndoToast: View {
    let message: String
    let secondsRemaining: Int

    let onSaveAsDiary: () -> Void
    let onDetail: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            summaryRow
            commandsRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Ink.bg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Ink.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 24, y: 4)
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Ink.fg)
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(Ink.fg)
                .lineLimit(1)
            Spacer(minLength: 4)
            undoButton
        }
    }

    /// 撤销按钮放在右上,最显眼最易点(用户最高频"反悔"动作)。
    /// 倒计时数字直接放在按钮里,省掉一个独立 badge。
    private var undoButton: some View {
        Button(action: onUndo) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .semibold))
                Text("撤销")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(secondsRemaining)s")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Ink.fgDim)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(Ink.fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Ink.card)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("撤销刚才的录音,\(secondsRemaining) 秒后自动消失")
    }

    private var commandsRow: some View {
        HStack(spacing: 8) {
            commandButton(
                icon: "book.fill",
                label: "存为日记",
                foreground: .white,
                background: Ink.accentBlue,
                action: onSaveAsDiary
            )
            commandButton(
                icon: "pencil",
                label: "进详情",
                foreground: Ink.fg,
                background: Ink.card,
                action: onDetail
            )
        }
    }

    private func commandButton(
        icon: String,
        label: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
