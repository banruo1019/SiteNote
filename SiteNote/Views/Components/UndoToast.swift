//
//  UndoToast.swift
//  SiteNote
//
//  M1 Linear 风 Undo Toast:
//  - 白底 + 顶部 1px 线,无阴影
//  - Row 1:✓ 消息 + 倒计时(整行可点 → 跳详情页)
//  - Row 2:四档分类 [今天][3 天][本周][归档] — 黑底白字,紧凑
//  - Row 3:[待分类][撤销] — 左 ghost 边框,右红色填充
//

import SwiftUI

struct UndoToast: View {
    let message: String
    let secondsRemaining: Int

    let onClassify: (Deadline) -> Void
    let onKeepInbox: () -> Void
    let onDetail: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            summaryRow
            classifyRow
            undoRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(Ink.bg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Ink.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 24, y: 4)
    }

    // MARK: - Rows

    private var summaryRow: some View {
        Button(action: onDetail) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Ink.fg)
                Text(message)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(Ink.fg)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.fgDim)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var classifyRow: some View {
        HStack(spacing: 6) {
            classifyButton(.today, label: "今天")
            classifyButton(.threeDays, label: "3 天")
            classifyButton(.thisWeek, label: "本周")
            classifyButton(.archive, label: "归档")
        }
    }

    private var undoRow: some View {
        HStack(spacing: 8) {
            Button(action: onKeepInbox) {
                HStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 14, weight: .regular))
                    Text("待分类")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Ink.fg)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Ink.fg, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            Button(action: onUndo) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .regular))
                    Text("撤销")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Ink.red)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private func classifyButton(_ deadline: Deadline, label: String) -> some View {
        Button {
            onClassify(deadline)
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Ink.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Ink.fg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
