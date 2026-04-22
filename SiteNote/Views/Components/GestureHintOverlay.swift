//
//  GestureHintOverlay.swift
//  SiteNote
//
//  RecordView 第一次出现时的录音手势教学层。
//  - 展示三种手势:按住说话 / 上滑日志 / 下滑取消
//  - 用户点"知道了"或屏幕任意位置后消失
//  - UserDefaults 标记不再出现
//

import SwiftUI

struct GestureHintOverlay: View {
    @Binding var isShown: Bool
    @State private var pulseUp = false
    @State private var pulseDown = false

    private static let dismissedKey = "settings.gestureHint.dismissed.v1"

    /// 是否需要显示(没标记过 dismissed 就显示)。
    static var needsToShow: Bool {
        !UserDefaults.standard.bool(forKey: dismissedKey)
    }

    static func markShown() {
        UserDefaults.standard.set(true, forKey: dismissedKey)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 28) {
                Text("一个按钮 · 三种手势")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                VStack(spacing: 18) {
                    hintRow(
                        icon: "mic.fill",
                        bgColor: Ink.red,
                        title: "按住说话",
                        subtitle: "松开 = 普通速记(AI 自动分类)",
                        arrow: nil
                    )
                    hintRow(
                        icon: "person.fill",
                        bgColor: Ink.accentBlue,
                        title: "按住 + 上滑",
                        subtitle: "松开 = 存为施工日记",
                        arrow: ("arrow.up", pulseUp)
                    )
                    hintRow(
                        icon: "xmark",
                        bgColor: Ink.dim,
                        title: "按住 + 下滑",
                        subtitle: "松开 = 丢弃录音",
                        arrow: ("arrow.down", pulseDown)
                    )
                }

                Button {
                    dismiss()
                } label: {
                    Text("知道了,开始用")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .frame(maxWidth: 360)
        }
        .transition(.opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseUp = true
                pulseDown = true
            }
        }
    }

    private func hintRow(
        icon: String,
        bgColor: Color,
        title: String,
        subtitle: String,
        arrow: (String, Bool)?
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(bgColor)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            if let (arrowIcon, pulsing) = arrow {
                Image(systemName: arrowIcon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(pulsing ? 1.0 : 0.3))
            }
        }
    }

    private func dismiss() {
        Self.markShown()
        withAnimation(.easeOut(duration: 0.2)) {
            isShown = false
        }
    }
}
