//
//  SparkleLoading.swift
//  SiteNote
//
//  AI 处理时的旋转 sparkle 动画。替代默认 ProgressView,更有"AI 在干活"的感觉。
//

import SwiftUI

/// AI 加载指示器。紫色 sparkles 图标缓慢旋转 + 缩放脉冲。
struct SparkleLoading: View {
    var label: String? = nil

    @State private var rotate: Double = 0
    @State private var scale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Ink.fg)
                .rotationEffect(.degrees(rotate))
                .scaleEffect(scale)
                .onAppear {
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        rotate = 360
                    }
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        scale = 1.2
                    }
                }
            if let label {
                Text(label)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .foregroundStyle(Ink.fg)
            }
        }
    }
}
