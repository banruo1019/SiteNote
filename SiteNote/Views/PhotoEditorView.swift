//
//  PhotoEditorView.swift
//  SiteNote
//
//  用 PencilKit 在照片上画箭头/圈注/涂鸦 + 文字标注。保存时把笔迹和文字扁平化到图片里。
//

import SwiftUI
import PencilKit
import UIKit

/// 工具模式。影响画布和文字层的响应。
enum PhotoEditTool {
    case pen
    case eraser
    case text
    case line
}

/// 一个可拖动的文字标注。位置以 canvasBounds 坐标系(左上原点)为准。
struct PhotoTextItem: Identifiable {
    let id = UUID()
    var text: String
    var position: CGPoint
    var color: UIColor
}

/// 照片标注编辑器。手指 / Apple Pencil 都能画。
///
/// 保存时把画布笔迹 + 文字标注烧录到原图里返回,得到一张新 UIImage。
struct PhotoEditorView: View {
    let originalImage: UIImage
    let onSave: (UIImage) -> Void

    @State private var canvas = PKCanvasView()
    @State private var selectedColor: Color = .red
    @State private var toolMode: PhotoEditTool = .pen
    @State private var textItems: [PhotoTextItem] = []
    @FocusState private var focusedTextID: UUID?
    @State private var canvasBounds: CGRect = .zero
    @State private var showsClearConfirm: Bool = false
    // 直线工具:drag 过程中的临时端点。drag end 时 commit 到 canvas.drawing。
    @State private var lineStart: CGPoint? = nil
    @State private var lineCurrent: CGPoint? = nil
    // 文字标注的 undo 栈(近似 LIFO:undo 撤销最后一次添加)。
    @State private var textAddOrder: [UUID] = []
    @Environment(\.dismiss) private var dismiss

    private let penWidth: CGFloat = 6
    private let textFontSize: CGFloat = 24

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                headerBar
                GeometryReader { geo in
                    ZStack {
                        Image(uiImage: originalImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                        PencilCanvas(
                            canvas: $canvas,
                            color: UIColor(selectedColor),
                            width: penWidth,
                            mode: toolMode
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        lineOverlay(size: geo.size)
                        textOverlay(size: geo.size)
                    }
                    .onAppear { canvasBounds = CGRect(origin: .zero, size: geo.size) }
                    .onChange(of: geo.size) { _, newSize in
                        canvasBounds = CGRect(origin: .zero, size: newSize)
                    }
                }
                unifiedToolBar
            }
        }
        .alert("清空所有标注?", isPresented: $showsClearConfirm) {
            Button("清空", role: .destructive) {
                canvas.drawing = PKDrawing()
                textItems.removeAll()
                textAddOrder.removeAll()
                lineStart = nil
                lineCurrent = nil
                focusedTextID = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会一次性抹掉所有笔迹和文字。")
        }
    }

    /// 直线工具叠加层。仅在 line 模式下吃手势,其它模式让事件穿透到 PencilKit。
    /// 思路:用 SwiftUI overlay 捕捉 drag 显示预览(GPU 便宜 + 视觉跟手),
    /// drag end 时把这条线作为单 stroke PKDrawing 合并进 canvas.drawing。
    /// 这样 PencilKit 的 undoManager 自然把它当成一个可撤销的 stroke。
    @ViewBuilder
    private func lineOverlay(size: CGSize) -> some View {
        ZStack {
            if toolMode == .line {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                if lineStart == nil { lineStart = value.startLocation }
                                lineCurrent = value.location
                            }
                            .onEnded { value in
                                let start = lineStart ?? value.startLocation
                                let end = value.location
                                commitLine(from: start, to: end)
                                lineStart = nil
                                lineCurrent = nil
                            }
                    )
            }
            // 预览(drag 进行中)
            if toolMode == .line, let s = lineStart, let c = lineCurrent {
                Path { p in
                    p.move(to: s)
                    p.addLine(to: c)
                }
                .stroke(selectedColor, style: StrokeStyle(lineWidth: penWidth, lineCap: .round))
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(toolMode == .line)
    }

    /// 把一条直线 commit 成 PKDrawing 的单笔 stroke,合并进 canvas.drawing。
    /// 走 canvas.drawing 赋值会被 PKCanvasView 的 undoManager 记录,支持 undo/redo。
    private func commitLine(from start: CGPoint, to end: CGPoint) {
        // 退化:零长度不画。
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx * dx + dy * dy > 1 else { return }

        let ink = PKInk(.pen, color: UIColor(selectedColor))
        // 两个端点足以画一段直线。给一个稳定 force,保证粗细均匀。
        let p1 = PKStrokePoint(
            location: start,
            timeOffset: 0,
            size: CGSize(width: penWidth, height: penWidth),
            opacity: 1,
            force: 1,
            azimuth: 0,
            altitude: 0
        )
        let p2 = PKStrokePoint(
            location: end,
            timeOffset: 0.01,
            size: CGSize(width: penWidth, height: penWidth),
            opacity: 1,
            force: 1,
            azimuth: 0,
            altitude: 0
        )
        let path = PKStrokePath(controlPoints: [p1, p2], creationDate: Date())
        let stroke = PKStroke(ink: ink, path: path)
        // 用现有 strokes + 新 stroke 重建一个 PKDrawing,然后整体赋值。
        // 整体赋值会触发 PKCanvasView 的 undoManager 注册。
        let merged = PKDrawing(strokes: canvas.drawing.strokes + [stroke])
        canvas.drawing = merged
    }

    /// 顶部只是标题。
    private var headerBar: some View {
        Text("标注照片")
            .foregroundStyle(.white)
            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
    }

    /// 文字叠加层。文字模式下:背景接收点击创建新文字;已有文字可拖动 + 双击编辑。
    @ViewBuilder
    private func textOverlay(size: CGSize) -> some View {
        ZStack {
            if toolMode == .text {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        addTextItem(at: location)
                    }
            }
            ForEach($textItems) { $item in
                textItemView(item: $item)
                    .position(item.position)
            }
        }
        .frame(width: size.width, height: size.height)
        // 只有文字模式时整层接收事件;画笔/橡皮模式下点击穿透到 PencilKit。
        .allowsHitTesting(toolMode == .text)
    }

    /// 单个文字节点视图。编辑中 = TextField + 焦点;非编辑 = Text + 点击进入编辑 + 拖动。
    private func textItemView(item: Binding<PhotoTextItem>) -> some View {
        let isEditing = focusedTextID == item.wrappedValue.id
        return Group {
            if isEditing {
                // **不要用 .fixedSize()**:空字符串时宽度会塌陷成一个小方块,看不到输入光标。
                // 用 .frame(minWidth:) 保证空也有可见宽度;打字时 TextField 会自然变宽。
                TextField("输入文字…", text: item.text)
                    .focused($focusedTextID, equals: item.wrappedValue.id)
                    .font(.system(size: textFontSize, weight: .semibold))
                    .foregroundStyle(Color(item.wrappedValue.color))
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 120)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onSubmit { focusedTextID = nil; pruneEmptyTexts() }
            } else {
                Text(item.wrappedValue.text.isEmpty ? " " : item.wrappedValue.text)
                    .font(.system(size: textFontSize, weight: .semibold))
                    .foregroundStyle(Color(item.wrappedValue.color))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { focusedTextID = item.wrappedValue.id }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                item.wrappedValue.position = CGPoint(
                                    x: item.wrappedValue.position.x + value.translation.width,
                                    y: item.wrappedValue.position.y + value.translation.height
                                )
                            }
                            .onEnded { _ in }
                    )
            }
        }
    }

    private func addTextItem(at location: CGPoint) {
        let new = PhotoTextItem(
            text: "",
            position: location,
            color: UIColor(selectedColor)
        )
        textItems.append(new)
        textAddOrder.append(new.id)
        // DispatchQueue.main.async 在 iOS 上 TextField 还没 mount 就 set focus 会失败 —
        // 用户看到空 box 但键盘不弹。延迟 150ms 等 TextField/ForEach 渲染完成,
        // focus 才会真正切到新 item,键盘弹起,可以输入。
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            focusedTextID = new.id
        }
    }

    /// 文字标注 undo:删除最后添加的一条(近似 LIFO,不还原编辑/拖动)。
    private func undoLastText() {
        guard let lastID = textAddOrder.popLast() else { return }
        textItems.removeAll { $0.id == lastID }
        if focusedTextID == lastID { focusedTextID = nil }
    }

    /// 完成编辑时把空文字项清掉(用户点了但没打字就跑了)。
    private func pruneEmptyTexts() {
        textItems.removeAll { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// 底部 toolbar:三行 —— 颜色 / 工具模式 + 清空 / 取消+保存。
    private var unifiedToolBar: some View {
        VStack(spacing: 10) {
            // Row 1: 颜色圆点
            HStack(spacing: 12) {
                ForEach([Color.red, Color.yellow, Color.green, Color.blue, Color.white, Color.black], id: \.self) { color in
                    Button {
                        selectedColor = color
                        // 颜色变化同步到当前正在编辑的文字。
                        if let id = focusedTextID,
                           let idx = textItems.firstIndex(where: { $0.id == id }) {
                            textItems[idx].color = UIColor(color)
                        }
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
            }
            .padding(.horizontal, 20)

            // Row 2: 工具模式切换 + Undo/Redo + 清空
            HStack(spacing: 8) {
                toolButton(icon: "pencil.tip", label: "画笔", mode: .pen)
                toolButton(icon: "line.diagonal", label: "直线", mode: .line)
                toolButton(icon: "eraser", label: "橡皮", mode: .eraser)
                toolButton(icon: "textformat", label: "文字", mode: .text)
                Spacer()
                actionIconButton(systemName: "arrow.uturn.backward", labelText: String(localized: "撤销", locale: AppLanguageManager.currentLocale)) {
                    performUndo()
                }
                actionIconButton(systemName: "arrow.uturn.forward", labelText: String(localized: "重做", locale: AppLanguageManager.currentLocale)) {
                    performRedo()
                }
                actionIconButton(systemName: "trash", labelText: String(localized: "清空全部", locale: AppLanguageManager.currentLocale)) {
                    showsClearConfirm = true
                }
            }
            .padding(.horizontal, 20)

            // Row 3: 取消 / 保存
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

    /// 图标按钮(撤销/重做/清空 共用样式)。和 toolButton 的尺寸视觉对齐。
    private func actionIconButton(systemName: String, labelText: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(.white)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 48)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(labelText)
    }

    /// 优先撤销 PencilKit 笔迹;PencilKit 没东西可撤了再撤销最后一条文字。
    private func performUndo() {
        // 先把正在编辑的文字提交,避免和 undo 状态错位。
        focusedTextID = nil
        if let um = canvas.undoManager, um.canUndo {
            um.undo()
            return
        }
        undoLastText()
    }

    /// Redo 只走 PencilKit 自带栈;文字 redo 太烧脑,暂不做。
    private func performRedo() {
        focusedTextID = nil
        if let um = canvas.undoManager, um.canRedo {
            um.redo()
        }
    }

    private func toolButton(icon: String, label: LocalizedStringKey, mode: PhotoEditTool) -> some View {
        let active = toolMode == mode
        return Button {
            // 切到非文字模式时,退出文字编辑。
            if mode != .text { focusedTextID = nil; pruneEmptyTexts() }
            // 切走 line 时清掉残留预览(避免下次进入 line 看见旧线段)。
            if mode != .line { lineStart = nil; lineCurrent = nil }
            toolMode = mode
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.system(size: 11))
            }
            .foregroundStyle(active ? Color.black : Color.white)
            .frame(width: 56, height: 48)
            .background(active ? Color.white : Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(label)
    }

    /// 把原图 + 画布笔迹 + 文字合成一张新 UIImage。
    private func save() {
        focusedTextID = nil
        pruneEmptyTexts()

        guard canvasBounds.width > 0, canvasBounds.height > 0 else {
            dismiss()
            return
        }

        let size = canvasBounds.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let result = renderer.image { _ in
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

            let strokeImage = canvas.drawing.image(from: canvasBounds, scale: UIScreen.main.scale)
            strokeImage.draw(in: canvasBounds)

            // 文字:SwiftUI 用 .position 是"中心对齐",这里用 NSString.draw 也按中心算 rect。
            for item in textItems {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: textFontSize, weight: .semibold),
                    .foregroundColor: item.color
                ]
                let ns = item.text as NSString
                let ts = ns.size(withAttributes: attrs)
                let padH: CGFloat = 10
                let padV: CGFloat = 4
                let boxW = ts.width + padH * 2
                let boxH = ts.height + padV * 2
                let box = CGRect(
                    x: item.position.x - boxW / 2,
                    y: item.position.y - boxH / 2,
                    width: boxW,
                    height: boxH
                )
                // 半透明底(与预览一致)
                UIColor.black.withAlphaComponent(0.25).setFill()
                UIBezierPath(roundedRect: box, cornerRadius: 6).fill()
                // 文字本体
                let textRect = box.insetBy(dx: padH, dy: padV)
                ns.draw(in: textRect, withAttributes: attrs)
            }
        }
        onSave(result)
        dismiss()
    }
}

/// PKCanvasView 的 SwiftUI 包装。按 mode 切换 PKInkingTool / PKEraserTool,文字模式下禁用交互。
struct PencilCanvas: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    let color: UIColor
    let width: CGFloat
    let mode: PhotoEditTool

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        applyTool(canvas)
        canvas.isUserInteractionEnabled = isInteractive(mode)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        applyTool(uiView)
        uiView.isUserInteractionEnabled = isInteractive(mode)
    }

    /// 文字 / 直线模式下让事件穿透给上层 overlay。
    private func isInteractive(_ mode: PhotoEditTool) -> Bool {
        switch mode {
        case .text, .line: return false
        case .pen, .eraser: return true
        }
    }

    private func applyTool(_ view: PKCanvasView) {
        switch mode {
        case .pen:
            view.tool = PKInkingTool(.pen, color: color, width: width)
        case .eraser:
            // **bitmap 模式 = 按像素擦,能擦局部**。原来用 .vector 是"碰到笔画就整条删",
            // 用户想擦半笔擦不掉。bitmap 默认有合适粗细,跟着手指走。
            view.tool = PKEraserTool(.bitmap)
        case .text, .line:
            // 用上层 overlay 接手势,canvas 这边不需要工具。保持当前 tool 不动。
            break
        }
    }
}
