//
//  ProfileSelectorView.swift
//  SiteNote
//
//  3 个角色卡片选择器,onboarding 第 2 步 + Settings 角色切换页 共用。
//  暗背景模式(onboarding 用)和正常模式(Settings 用)通过 `mode` 参数切换。
//

import SwiftUI

struct ProfileSelectorView: View {
    @Binding var selection: ProfileKind
    var mode: Mode = .light

    enum Mode {
        case onboarding   // 暗背景 + 白文字(给 OnboardingView 用)
        case light        // 浅背景(给 Settings 用)
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(ProfileKind.allCases) { kind in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selection = kind
                    }
                } label: {
                    card(for: kind)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func card(for kind: ProfileKind) -> some View {
        let isSelected = selection == kind
        let accent = themeColor(kind)

        HStack(alignment: .top, spacing: 14) {
            // 左侧图标
            ZStack {
                Circle()
                    .fill(isSelected ? accent : Color.gray.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: kind.sfSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : (mode == .onboarding ? Color.white : Ink.fg))
            }

            // 右侧文字
            // 三层文字在 onboarding 暗背景宽度有限,英文(Project Manager · PM / Builder / Foreman)
            // 容易被截断 —— displayName 行加 lineLimit + minimumScaleFactor;
            // subtitle 单独占一行,避免 displayName 让位给 subtitle。
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(kind.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(kind.description)
                    .font(.system(size: 12))
                    .foregroundStyle(textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            // 选中标记
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(accent)
                    .padding(.top, 2)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(textSecondary.opacity(0.4))
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground(isSelected: isSelected, accent: accent))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderStroke(isSelected: isSelected, accent: accent),
                              lineWidth: borderLineWidth(isSelected: isSelected))
        )
    }

    // MARK: - 配色辅助(适配 mode)

    private var textPrimary: Color {
        mode == .onboarding ? .white : Ink.fg
    }

    private var textSecondary: Color {
        mode == .onboarding ? Color.white.opacity(0.7) : Ink.fgDim
    }

    private var borderColor: Color {
        mode == .onboarding ? Color.white.opacity(0.2) : Ink.line
    }

    /// 选中态边框颜色。onboarding 暗背景下用纯白(对比度高,工地光线下也分得清),
    /// light 模式仍用 accent 色保留品牌色。
    private func borderStroke(isSelected: Bool, accent: Color) -> Color {
        if isSelected {
            return mode == .onboarding ? Color.white : accent
        }
        return borderColor
    }

    /// 选中 2pt / 未选 1pt(onboarding) — 比之前 1.5/0.5 宽阔,工地手套点也能 confirm。
    private func borderLineWidth(isSelected: Bool) -> CGFloat {
        if mode == .onboarding {
            return isSelected ? 2.0 : 1.0
        }
        return isSelected ? 1.5 : 0.5
    }

    private func cardBackground(isSelected: Bool, accent: Color) -> Color {
        if mode == .onboarding {
            // 选中 0.22 / 未选 0.05 — 之前 0.10/0.05 差异太弱,工地光线下分不出。
            return isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.05)
        } else {
            return isSelected ? accent.opacity(0.06) : Ink.card
        }
    }

    private func themeColor(_ kind: ProfileKind) -> Color {
        switch kind {
        case .siteTeam: return Ink.accent          // 工地橙
        case .engineer: return Ink.accentBlue
        }
    }
}
