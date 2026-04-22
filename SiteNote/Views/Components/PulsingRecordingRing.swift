//
//  PulsingRecordingRing.swift
//  SiteNote
//
//  录音时大麦克风按钮外围的脉冲光环。3 米外也能看见正在录音。
//

import SwiftUI

/// 两层红色光环无限向外扩散再淡出,给工地场景高可见性。
struct PulsingRecordingRing: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            ForEach(0..<2) { index in
                Circle()
                    .stroke(Color.red.opacity(0.55), lineWidth: 4)
                    .scaleEffect(isAnimating ? 1.6 + CGFloat(index) * 0.15 : 1.0)
                    .opacity(isAnimating ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: 1.4)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.5),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
        .allowsHitTesting(false)
    }
}
