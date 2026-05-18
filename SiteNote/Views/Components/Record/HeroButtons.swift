//
//  HeroButtons.swift
//  SiteNote
//
//  主屏底部两个 132pt 大圆按钮 —— camera(左)+ mic(右)。
//  工地手套场景的硬约束:位置 / 尺寸 / 颜色一字不动(M1 design spec)。
//
//  从 RecordView 提取出来,viewModel 通过参数注入(HomeViewModel 是
//  @Observable,直接读 + 调方法,不需要 binding)。`onShowCamera` 是 closure
//  让 parent 控制 sheet 显示。
//
//  micButton 的手势是 DragGesture(minimumDistance:0),onChanged 开始录、
//  onEnded 停止并保存。**节点必须稳定**(不能因为 recording 态切换而被
//  重建),不然 DragGesture 目标消失,松手不触发 onEnded。所以 caller
//  在 recording / idle 切换时不要重建本 view。
//

import SwiftUI

struct HeroButtons: View {
    /// HomeViewModel(@Observable),直接读 isRecording / 调 startRecording / stopAndSave / cancelRecording。
    @Bindable var viewModel: HomeViewModel
    /// 点击 camera 时回调 parent 弹 sheet。
    let onShowCamera: () -> Void
    /// 真正开始录音前给 parent 一次拦截机会(默认总允许)。
    /// 返回 false → 本次 mic 按下不开始录音(parent 应负责弹替代 UI 比如 StartInspectionSheet)。
    /// 用例:Engineer 没在巡检中长按 mic → 弹「先选工地开巡检」。
    var canStartRecording: () -> Bool = { true }

    /// 上滑取消阈值(pt)。向上拖超过这个距离 = 松手取消而非保存。
    private let cancelSwipeThreshold: CGFloat = 80

    /// 当前 drag 累计 Y 偏移(负数 = 向上)。用于 hint pill 高亮"即将取消"。
    @State private var dragOffsetY: CGFloat = 0

    /// 暴露给 parent 用于显示"松手取消"高亮状态(可选用)。
    var willCancelOnRelease: Bool {
        viewModel.isRecording && dragOffsetY <= -cancelSwipeThreshold
    }

    var body: some View {
        HStack(spacing: 16) {
            cameraButton
                .opacity(viewModel.isRecording ? 0 : 1)
                .allowsHitTesting(!viewModel.isRecording)
            micButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var micButton: some View {
        ZStack {
            Circle()
                .fill(circleColor)
                .frame(width: 132, height: 132)
            if viewModel.isRecording {
                Circle()
                    .stroke(circleColor.opacity(0.12), lineWidth: 10)
                    .frame(width: 142, height: 142)
            }
            Image(systemName: "mic.fill")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Color.white)
        }
        .frame(width: 132, height: 132)
        .contentShape(Rectangle())
        // 上滑取消手势:onChanged 实时追踪 Y 偏移;onEnded 按方向决定 save vs cancel
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !viewModel.isRecording {
                        // 给 parent 拦截机会(Engineer idle → 弹 StartSheet 而不是直接录)
                        guard canStartRecording() else { return }
                        viewModel.startRecording()
                    }
                    dragOffsetY = value.translation.height
                }
                .onEnded { value in
                    let yOffset = value.translation.height
                    dragOffsetY = 0
                    guard viewModel.isRecording else { return }
                    if yOffset <= -cancelSwipeThreshold {
                        // 上滑超阈值 → 取消,不保存
                        viewModel.cancelRecording()
                    } else {
                        Task { await viewModel.stopAndSave() }
                    }
                }
        )
        .sensoryFeedback(.impact(weight: .heavy), trigger: viewModel.isRecording)
        // 上滑超阈值时给一次反馈(让用户感知到"即将取消")
        .sensoryFeedback(.impact(weight: .light), trigger: willCancelOnRelease)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("录音")
        .accessibilityHint("长按开始录音,松手保存,上划取消")
    }

    private var circleColor: Color {
        viewModel.isRecording ? Ink.red : Ink.fg
    }

    private var cameraButton: some View {
        Circle()
            .fill(Ink.bg)
            .overlay(Circle().strokeBorder(Ink.fg, lineWidth: 1.5))
            .frame(width: 132, height: 132)
            .overlay(
                Image(systemName: "camera.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Ink.fg)
            )
            .onTapGesture(perform: onShowCamera)
            .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.isRecording)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("拍照")
    }
}
