//
//  UndoToast.swift
//  SiteNote
//
//  录音保存后的浮窗。v1.2 大减负后简化:
//  - Row 1: ✓ 摘要(左) + 倒计时 + 撤销按钮(右上)
//  - Row 2: [✎ 进详情]  —— 唯一命令(进详情设置 deadline / 改信息)
//
//  默认沉默最舒服:5s 不动 = 自动消失,note 留在 Inbox(默认)。
//

import SwiftUI

struct UndoToast: View {
    let message: String
    let secondsRemaining: Int

    let onDetail: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            summaryRow
            detailButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Ink.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
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

    private var detailButton: some View {
        Button(action: onDetail) {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .regular))
                Text("进详情")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Ink.fg)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Ink.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
