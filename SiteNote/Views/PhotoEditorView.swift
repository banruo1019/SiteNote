//
//  PhotoEditorView.swift
//  SiteNote
//
//  用 PencilKit 在照片上画箭头/圈注/涂鸦。保存时把笔迹扁平化到图片里。
//

import SwiftUI
import PencilKit
import UIKit

/// 照片标注编辑器。手指 / Apple Pencil 都能画。
///
/// 保存时把画布上的笔迹烧录到原图里返回,得到一张新 UIImage。
struct PhotoEditorView: View {
    /// 进来时的原图。
    let originalImage: UIImage
    /// 用户点"保存"后的回调,参数是画完的新图。
    let onSave: (UIImage) -> Void

    @State private var canvas = PKCanvasView()
    @State private var selectedColor: Color = .red
    @State private var canvasBounds: CGRect = .zero
    @Environment(\.dismiss) private var dismiss

    private let penWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                // 顶部只留一个极简标题条,不再放操作按钮(全部下移到底部拇指区)
                headerBar
                GeometryReader { geo in
                    ZStack {
                        Image(uiImage: originalImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                        PencilCanvas(canvas: $canvas, color: UIColor(selectedColor), width: penWidth)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .onAppear { canvasBounds = CGRect(origin: .zero, size: geo.size) }
                    .onChange(of: geo.size) { _, newSize in
                        canvasBounds = CGRect(origin: .zero, size: newSize)
                    }
                }
                unifiedToolBar
            }
        }
    }

    /// 极简顶条:只显示标题,不再是操作区。
    private var headerBar: some View {
        Text("标注照片")
            .foregroundStyle(.white)
            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
    }

    /// 底部统一 toolbar:两行。
    /// - 行 1:颜色点(左)+ 清除(右,次级)
    /// - 行 2:取消(左)+ 保存(右,大按钮,拇指可达)
    private var unifiedToolBar: some View {
        VStack(spacing: 12) {
            // 颜色 + 清除
            HStack(spacing: 12) {
                ForEach([Color.red, Color.yellow, Color.green, Color.blue, Color.white, Color.black], id: \.self) { color in
                    Button {
                        selectedColor = color
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 1)
                            )
                    }
                    .accessibilityLabel("选择颜色")
                }
                Spacer()
                Button {
                    canvas.drawing = PKDrawing()
                } label: {
                    Image(systemName: "eraser")
                        .foregroundStyle(.white)
                        .font(.system(size: 20))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("清除所有笔迹")
            }
            .padding(.horizontal, 20)

            // 取消 + 保存(保存在右,方便右手拇指)
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Text("取消")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                        )
                }

                Button(action: save) {
                    Text("保存")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .padding(.top, 12)
        .background(Color.black)
    }

    /// 把原图 + 画布笔迹合成一张新 UIImage。
    private func save() {
        guard canvasBounds.width > 0, canvasBounds.height > 0 else {
            dismiss()
            return
        }

        let size = canvasBounds.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let result = renderer.image { _ in
            // 先画原图(scaledToFit 居中)
            let imageAspect = originalImage.size.width / originalImage.size.height
            let viewAspect = size.width / size.height
            let imageRect: CGRect
            if imageAspect > viewAspect {
                let h = size.width / imageAspect
                imageRect = CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
            } else {
                let w = size.height * imageAspect
                imageRect = CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
            }
            originalImage.draw(in: imageRect)

            // 覆盖笔迹(保持原色,不加光晕)
            let strokeImage = canvas.drawing.image(from: canvasBounds, scale: UIScreen.main.scale)
            strokeImage.draw(in: canvasBounds)
        }
        onSave(result)
        dismiss()
    }
}

/// PKCanvasView 的 SwiftUI 包装。颜色/粗细变化会更新画笔工具。
struct PencilCanvas: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    let color: UIColor
    let width: CGFloat

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: color, width: width)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = PKInkingTool(.pen, color: color, width: width)
    }
}
