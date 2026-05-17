//
//  RecordingTopArea.swift
//  SiteNote
//
//  录音态的顶部大块视觉:
//  - 顶部一行:REC dot + 工地 chip + zh+en 语种标
//  - 64pt 等宽数字大字计时(TimelineView 0.5s tick)
//  - "录音中 · ~1.2 MB" mini 副标
//  - 28 段 AudioWaveformView 实时电平
//  - 实时转写文本 + 闪烁光标
//  - 手势提示 pill:松手保存 / 上划取消(纯视觉,不接收 hit)
//
//  从 RecordView 提取(~130 行),依赖通过参数注入,无 @State。
//  注:`siteTag` 直接传 String? 而不是 allNotes,让 caller 负责挑出 last note,
//  这层只关心展示。
//

import SwiftUI

struct RecordingTopArea: View {
    /// 来自 HomeViewModel 的实时状态。
    let isRecording: Bool
    let audioLevel: Float
    let partialTranscription: String
    /// 录音开始时间;nil 时 timer 显示占位。
    let recordingStartTime: Date?
    /// 顶部 chip 显示的工地标签(取最近一条 Note 的 siteTag,可空)。
    let siteTag: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部一行:REC dot + 工地 chip + zh+en
            HStack(spacing: 8) {
                PulsingDot(color: Ink.red)
                Text("REC")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Ink.red)
                if let s = siteTag, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Ink.fg2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Ink.card)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                Text("zh + en")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
                    .monospacedDigit()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            // 大字计时
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                Text(durationLabel(now: ctx.date))
                    .font(.system(size: 64, weight: .medium))
                    .tracking(-2)
                    .foregroundStyle(Ink.fg)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)

            Text("录音中  ·  ~1.2 MB")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Ink.fgDim)
                .padding(.horizontal, 24)
                .padding(.top, 4)

            AudioWaveformView(level: audioLevel)
                .frame(height: 84)
                .padding(.horizontal, 24)
                .padding(.top, 28)

            // 转写
            VStack(alignment: .leading, spacing: 8) {
                Text("转写 · 实时")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Ink.fgDim)
                HStack(alignment: .top, spacing: 2) {
                    Text(partialTranscription.isEmpty ? "…" : partialTranscription)
                        .font(.system(size: 18, weight: .regular))
                        .tracking(-0.2)
                        .lineSpacing(4)
                        .foregroundStyle(Ink.fg)
                    if !partialTranscription.isEmpty {
                        BlinkingCursor()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)

            Spacer()

            // 手势提示 pill:松手保存 / 上划取消(只展示,不可点)
            HStack(spacing: 10) {
                Text(String(localized: "松手保存", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(Ink.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Ink.fg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(localized: "上划取消", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Ink.fgDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Ink.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 16)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// MM:SS 计时(start 为 nil 时显示占位)。
    private func durationLabel(now: Date) -> String {
        guard let start = recordingStartTime else { return "●:●●" }
        let elapsed = max(0, now.timeIntervalSince(start))
        let total = Int(elapsed)
        let mm = total / 60
        let ss = total % 60
        return String(format: "%02d:%02d", mm, ss)
    }
}

/// 转写实时态的闪烁光标 — 在末尾显示一个 "|" 闪。
/// 原在 RecordView 文件尾的私有 struct,提到这里跟唯一调用方一起住。
struct BlinkingCursor: View {
    @State private var on = true
    var body: some View {
        Text("|")
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(Ink.fgDim)
            .opacity(on ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    on.toggle()
                }
            }
    }
}
