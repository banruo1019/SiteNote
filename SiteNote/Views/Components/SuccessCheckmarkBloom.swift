//
//  SuccessCheckmarkBloom.swift
//  SiteNote
//
//  保存成功时从按钮位置"绽放"的大绿钩。弹簧动画出现,淡出消失。满足感反馈。
//

import SwiftUI

/// 保存成功绽放动画。放在 overlay 里,生命周期由父视图控制。
struct SuccessCheckmarkBloom: View {
    @State private var scale: CGFloat = 0.2
    @State private var opacity: Double = 1.0

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 100, weight: .bold))
            .foregroundStyle(.white, .green)
            .scaleEffect(scale)
            .opacity(opacity)
            .shadow(color: .green.opacity(0.6), radius: 16)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                    scale = 1.5
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.35)) {
                    opacity = 0
                    scale = 2.0
                }
            }
            .allowsHitTesting(false)
    }
}
