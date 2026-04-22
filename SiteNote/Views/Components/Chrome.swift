//
//  Chrome.swift
//  SiteNote
//
//  M1 风不用"仪表元信息条"。这里保留 Chrome 名字为了向下兼容旧调用点,
//  但实际只渲染一条 1px 细线 + 可选状态点(录音态红点脉冲),
//  没有 mono 大写标签,没有背景块。
//

import SwiftUI

struct Chrome: View {
    /// Recording 时右侧显示"REC"红点。其他情况这个 view 啥都不画。
    var tab: String = ""
    var recording: Bool = false
    var site: String? = nil
    var weather: String? = nil

    var body: some View {
        // M1 里 chrome 退化。默认空,若录音中则右上一个极小 REC 指示。
        Group {
            if recording {
                HStack(spacing: 6) {
                    Spacer()
                    PulsingDot(color: Ink.red)
                    Text("REC")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.red)
                        .tracking(0.3)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 8)
            } else {
                EmptyView()
            }
        }
    }
}

/// 红色脉冲圆点(录音状态)。
struct PulsingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(pulse ? 1.2 : 1.0)
            .opacity(pulse ? 0.6 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

/// 旧 `StatusDot` 别名(Chrome.swift 上版里导出过)。保留以免引用点报错。
struct StatusDot: View {
    let recording: Bool
    var body: some View {
        Circle()
            .fill(recording ? Ink.red : Ink.fgDim)
            .frame(width: 6, height: 6)
    }
}
