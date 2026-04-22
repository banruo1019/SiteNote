//
//  OnboardingView.swift
//  SiteNote
//
//  首次启动 3 步引导。
//  - Step 1:欢迎 + 隐私
//  - Step 2:建第一个工地(可跳过)
//  - Step 3:介绍录音手势(教学层会在用户进 RecordView 时再次展示)
//
//  完成后 UserDefaults 标记 dismissed,不再出现。
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isShown: Bool

    @State private var step: Int = 0
    @State private var firstSiteName: String = ""

    private static let dismissedKey = "settings.onboarding.dismissed.v1"

    static var needsToShow: Bool {
        !UserDefaults.standard.bool(forKey: dismissedKey)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // 步骤指示
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Capsule()
                            .fill(i == step ? Color.white : Color.white.opacity(0.25))
                            .frame(width: i == step ? 28 : 8, height: 4)
                    }
                }

                // 步骤内容
                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: firstSiteStep
                    default: gestureStep
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer()

                // Action 按钮
                VStack(spacing: 8) {
                    Button {
                        advanceStep()
                    } label: {
                        Text(step < 2 ? "下一步" : "开始用")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    if step == 1 {
                        Button {
                            advanceStep()
                        } label: {
                            Text("跳过,以后再加")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: 380)
        }
        .transition(.opacity)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "mic.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white)
                .padding(28)
                .background(Circle().fill(Color.white.opacity(0.1)))

            Text("欢迎用 SiteNote")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)

            Text("一个按钮录音 · AI 帮你整理 · 一键导出日报")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("录音、位置和分类都在你设备本地处理。可选 OpenAI Key 提升 AI 质量。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 12)
        }
        .padding(.horizontal, 28)
    }

    private var firstSiteStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white)
                .padding(24)
                .background(Circle().fill(Color.white.opacity(0.1)))

            Text("先建一个工地")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            Text("AI 会用工地名分类记录;\n之后你可以在设置里加更多。")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            TextField("如 悉尼 Olympic Park", text: $firstSiteName)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .tint(.white)
                .padding(14)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
                .padding(.horizontal, 28)
                .padding(.top, 8)
        }
        .padding(.horizontal, 28)
    }

    private var gestureStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white)
                .padding(24)
                .background(Circle().fill(Color.white.opacity(0.1)))

            Text("录音三种手势")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 14) {
                gestureLine(icon: "mic.fill", color: Ink.red, title: "按住说话", sub: "松开 = 普通速记")
                gestureLine(icon: "arrow.up", color: Ink.accentBlue, title: "按住 + 上滑", sub: "松开 = 存为施工日记")
                gestureLine(icon: "xmark", color: Ink.dim, title: "按住 + 下滑", sub: "松开 = 取消录音")
            }
            .padding(.horizontal, 24)
        }
        .padding(.horizontal, 28)
    }

    private func gestureLine(icon: String, color: Color, title: String, sub: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
    }

    // MARK: - Logic

    private func advanceStep() {
        if step == 1 {
            // 保存工地(若填了)
            let trimmed = firstSiteName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                SiteTagsStorage.add(trimmed)
            }
        }
        if step >= 2 {
            UserDefaults.standard.set(true, forKey: Self.dismissedKey)
            withAnimation(.easeOut(duration: 0.25)) {
                isShown = false
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                step += 1
            }
        }
    }
}
