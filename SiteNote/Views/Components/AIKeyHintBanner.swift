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
        // 紧凑单行(过去两行占位过高,把 statsRow 推离标题太远)。
        HStack(spacing: 8) {
            NavigationLink(value: AIStatusDestination()) {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.accentBlue)
                    Text("配 AI Key 让识别更准")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Ink.accentBlue)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Ink.accentBlue.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                dismissForever()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.dim)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Ink.accentBlue.opacity(0.07), in: Capsule())
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }

    private func dismissForever() {
        UserDefaults.standard.set(true, forKey: Self.dismissedKey)
        withAnimation(.easeOut(duration: 0.2)) { dismissed = true }
    }
}
