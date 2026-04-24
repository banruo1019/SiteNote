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
