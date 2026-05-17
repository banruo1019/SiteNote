//
//  UndoToast.swift
//  SiteNote
//
//  录音保存后的浮卡(M1)。
//  单行,覆盖在 mic+camera 大按钮上方,不替换它们 — 用户随时可继续录新条。
//  ● 已记录 · 摘要…   撤销 9s
//  整行可点(= 进详情);右侧"撤销 9s"独立点击区,9 秒后自动消失。
//

import SwiftUI

struct UndoToast: View {
    let message: String
    let secondsRemaining: Int

    let onDetail: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 左:点这块进详情
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

            // 右:撤销 + 倒计时
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Ink.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Ink.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 16, y: 4)
    }

    /// 用户提示语:已记录 · 摘要。摘要为空时回落到纯标识。
    private var prefixedMessage: String {
        let prefix = String(localized: "已记录", locale: AppLanguageManager.currentLocale)
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? prefix : "\(prefix) · \(trimmed)"
    }
}
