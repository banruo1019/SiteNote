//
//  AudioWaveformView.swift
//  SiteNote
//
//  录音时在麦克风按钮内显示的 5 条音量波形。bar 高度随 level (0-1) 变化,
//  两端矮中间高,带轻微随机相位,比纯阶梯好看。
//

import SwiftUI

struct AudioWaveformView: View {
    /// 当前音频电平,0-1。由 VoiceCaptureService 的 tap 回调喂。
    let level: Float

    /// 每根 bar 的相对高度系数(中间高两边低)。
    private let factors: [CGFloat] = [0.35, 0.7, 1.0, 0.7, 0.35]

    /// bar 的最小 / 最大高度(pt)。
    private let minHeight: CGFloat = 6
    private let maxHeight: CGFloat = 56

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(factors.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 5, height: heightForBar(i))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
        .frame(height: maxHeight)
        .allowsHitTesting(false)
    }

    private func heightForBar(_ index: Int) -> CGFloat {
        let clamped = CGFloat(min(max(level, 0), 1))
        return minHeight + clamped * (maxHeight - minHeight) * factors[index]
    }
}
