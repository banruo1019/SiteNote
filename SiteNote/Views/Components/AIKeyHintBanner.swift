//
//  AIKeyHintBanner.swift
//  SiteNote
//
//  AI 未配置时的温和引导卡。挂在 RecordView idle 顶区。
//
//  逻辑:
//   - 首次进入 + AI 不可用 → 显示
//   - 用户 tap "配置" → 跳 InputAISettingsView
//   - 用户 tap "X" → 永远不再显示
//   - AI 可用后自动消失
//

import SwiftUI

struct AIKeyHintBanner: View {
    private static let dismissedKey = "settings.aiKeyHint.dismissed.v1"

    @State private var dismissed: Bool = UserDefaults.standard.bool(forKey: dismissedKey)

    var body: some View {
        if dismissed || AIService.isLanguageModelAvailable {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        NavigationLink(value: AIStatusDestination()) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Ink.accentBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("配 AI Key 让自动识别更准")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                    Text("可选 OpenAI 或 Apple Intelligence(iOS 26)")
                        .font(.system(size: 10))
                        .foregroundStyle(Ink.fgDim)
                }
                Spacer()
                Button {
                    dismissForever()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.dim)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Ink.accentBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Ink.accentBlue.opacity(0.25), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
        .buttonStyle(.plain)
    }

    private func dismissForever() {
        UserDefaults.standard.set(true, forKey: Self.dismissedKey)
        withAnimation(.easeOut(duration: 0.2)) { dismissed = true }
    }
}
