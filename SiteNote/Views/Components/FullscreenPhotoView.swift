//
//  FullscreenPhotoView.swift
//  SiteNote
//
//  全屏照片预览(支持捏合缩放)。
//  从 NoteDetailView.swift 拆分出来,作为可复用 UI 组件。
//

import SwiftUI
import UIKit

struct FullscreenPhotoView: View {
    let image: UIImage
    /// 可选回调:点"标注"按钮时触发。父视图收到后应先 dismiss 全屏,再弹 PhotoEditorView。
    /// 不传则不显示标注按钮。
    var onAnnotate: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1, min(value, 4))
                        }
                        .onEnded { _ in
                            withAnimation { scale = max(1, scale) }
                        }
                )
            VStack {
                HStack {
                    if onAnnotate != nil {
                        Button {
                            // 先关全屏,父视图监听 dismiss 后再弹标注 sheet。
                            // 直接同栈再弹 sheet 在 iOS 17 会被 SwiftUI 吞掉。
                            dismiss()
                            // 延时一点确保 dismiss 动画启动后再触发回调。
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                onAnnotate?()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil.tip.crop.circle")
                                Text(String(localized: "标注", locale: AppLanguageManager.currentLocale))
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.5), in: Capsule())
                        }
                        .padding(.leading)
                        .accessibilityLabel(String(localized: "标注此照片", locale: AppLanguageManager.currentLocale))
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white, Color.black.opacity(0.5))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}
