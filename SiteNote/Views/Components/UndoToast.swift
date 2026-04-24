//
//  UndoToast.swift
//  SiteNote
//
//  P0-2 版:4 按钮 2x2 布局。
//  - Row 1:✓ 摘要 + 倒计时(纯文字)
//  - Row 2:[🚨 标隐患] [📓 存为日记]  —— 分类
//  - Row 3:[✎ 细记]   [⟲ 撤销]      —— 导航 / 撤回
//

import SwiftUI

struct UndoToast: View {
    let message: String
    let secondsRemaining: Int

    let onMarkHazard: () -> Void
    let onSaveAsDiary: () -> Void
    let onDetail: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            summaryRow
            HStack(spacing: 8) {
                actionButton(
                    icon: "exclamationmark.triangle.fill",
                    label: "标隐患",
                    foreground: .white,
                    background: Ink.red,
                    action: onMarkHazard
                )
                actionButton(
                    icon: "book.fill",
                    label: "存为日记",
                    foreground: .white,
                    background: Ink.accentBlue,
                    action: onSaveAsDiary
                )
            }
            HStack(spacing: 8) {
                actionButton(
                    icon: "pencil",
                    label: "细记",
                    foreground: Ink.fg,
                    background: Ink.card,
                    action: onDetail
                )
                actionButton(
                    icon: "arrow.uturn.backward",
                    label: "撤销",
                    foreground: Ink.fg,
                    background: nil,
                    action: onUndo
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
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
            Text("\(secondsRemaining)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ink.fgDim)
                .monospacedDigit()
                .frame(width: 28, height: 28)
                .background(Ink.card)
                .clipShape(Circle())
                .contentTransition(.numericText())
        }
    }

    private func actionButton(
        icon: String,
        label: String,
        foreground: Color,
        background: Color?,
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
            .background(background ?? Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(background == nil ? Ink.fg : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
