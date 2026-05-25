//
//  PhotoEditorView.swift
//  SiteNote
//
//  照片标注编辑器。两套绘图通道:
//  1) 画笔(pen) / 橡皮(eraser) → PencilKit PKDrawing(自由涂,无法元素化)
//  2) 直线 / 矩形 / 椭圆 / 文字 → 可编辑 AnnotationElement(像 Keynote 图元)
//     可拖动、缩放、旋转、改颜色、改粗细、删除。
//  保存时按顺序把 image + PKDrawing + elements 渲染到一张 UIImage。
//
//  交互改造(2026-05-17):
//  - 去掉「选择」工具:任何工具模式下,点元素都自动切到选中态。
//  - 文字编辑时画布不被键盘 inset 压缩,且自动平移让文字始终在键盘上方。
//  - 拖动 / 缩放用 base + delta(snapshot)模式,避免增量累加导致的 jitter。
//

import SwiftUI
import PencilKit
import UIKit
import Combine

// MARK: - 工具模式

/// 工具模式。影响画布层和元素层的响应。
/// 注意:没有 select 工具 — 点元素就自动选中,统一手势模型。
enum PhotoEditTool {
    case pen        // 自由涂(PKDrawing)
    case eraser     // 橡皮(PKDrawing)
    case line       // 创建直线元素
    case rect       // 创建矩形元素
    case circle     // 创建椭圆元素
    case text       // 创建文字元素
}

// MARK: - 元素模型

/// 元素 ID + 类型擦除盒子。用 class 共享给手势 closure 时方便 mutate。
struct LineElement: Identifiable, Equatable {
    let id: UUID
    var start: CGPoint
    var end: CGPoint
    var color: Color
    var lineWidth: CGFloat
}

struct RectElement: Identifiable, Equatable {
    let id: UUID
    var rect: CGRect          // 未旋转的轴对齐 rect
    var color: Color
    var lineWidth: CGFloat
    var rotation: Angle       // 围绕 rect 中心
}

struct CircleElement: Identifiable, Equatable {
    let id: UUID
    var rect: CGRect          // 椭圆的外接矩形(未旋转)
    var color: Color
    var lineWidth: CGFloat
    var rotation: Angle
}

struct TextElement: Identifiable, Equatable {
    let id: UUID
    var center: CGPoint       // 中心位置
    var content: String
    var fontSize: CGFloat
    var color: Color
    var rotation: Angle
}

/// 元素枚举,共享 id 方便选择 / 删除 / undo。
enum AnnotationElement: Identifiable, Equatable {
    case line(LineElement)
    case rect(RectElement)
    case circle(CircleElement)
    case text(TextElement)

    var id: UUID {
        switch self {
        case .line(let l): return l.id
        case .rect(let r): return r.id
        case .circle(let c): return c.id
        case .text(let t): return t.id
        }
    }

    var color: Color {
        get {
            switch self {
            case .line(let l): return l.color
            case .rect(let r): return r.color
            case .circle(let c): return c.color
            case .text(let t): return t.color
            }
        }
        set {
            switch self {
            case .line(var l): l.color = newValue; self = .line(l)
            case .rect(var r): r.color = newValue; self = .rect(r)
            case .circle(var c): c.color = newValue; self = .circle(c)
            case .text(var t): t.color = newValue; self = .text(t)
            }
        }
    }

    var lineWidth: CGFloat {
        get {
            switch self {
            case .line(let l): return l.lineWidth
            case .rect(let r): return r.lineWidth
            case .circle(let c): return c.lineWidth
            case .text: return 0
            }
        }
        set {
            switch self {
            case .line(var l): l.lineWidth = newValue; self = .line(l)
            case .rect(var r): r.lineWidth = newValue; self = .rect(r)
            case .circle(var c): c.lineWidth = newValue; self = .circle(c)
            case .text: break
            }
        }
    }
}

// MARK: - 键盘监听 ViewModifier

/// 监听系统键盘高度,把当前值写到外部 binding。
/// 用 NotificationCenter 而不是 SwiftUI 的 keyboard safe area,这样我们可以自己决定怎么避让。
struct KeyboardHeightModifier: ViewModifier {
    @Binding var height: CGFloat

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
                if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    height = frame.height
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                height = 0
            }
    }
}

extension View {
    func keyboardHeightAware(_ binding: Binding<CGFloat>) -> some View {
        modifier(KeyboardHeightModifier(height: binding))
    }
}

// MARK: - 主视图

/// 照片标注编辑器。手指 / Apple Pencil 都能画。
///
/// 保存时把画布笔迹 + 元素图层烧录到原图里返回,得到一张新 UIImage。
struct PhotoEditorView: View {
    let originalImage: UIImage
    let onSave: (UIImage) -> Void

    @State private var canvas = PKCanvasView()
    @State private var selectedColor: Color = .red
    @State private var selectedLineWidth: CGFloat = 6
    @State private var toolMode: PhotoEditTool = .pen

    // 元素层
    @State private var elements: [AnnotationElement] = []
    @State private var selectedElementID: UUID? = nil
    @State private var editingTextID: UUID? = nil
    @FocusState private var focusedTextID: UUID?
    // 元素 add 顺序的 LIFO 栈,用于元素 undo。
    @State private var elementAddOrder: [UUID] = []
    @State private var elementUndoRedoStack: [UUID] = []  // 删掉后保留的元素 id,供 redo 用
    @State private var deletedElements: [UUID: AnnotationElement] = [:]

    // Drag-to-create 临时端点(line / rect / circle)
    @State private var createStart: CGPoint? = nil
    @State private var createCurrent: CGPoint? = nil

    @State private var canvasBounds: CGRect = .zero
    @State private var showsClearConfirm: Bool = false
    @Environment(\.dismiss) private var dismiss

    // 键盘适配:监听键盘高度;editingTextID ≠ nil 时给主 ZStack 加 y offset 让文字可见。
    @State private var keyboardHeight: CGFloat = 0
    @State private var screenHeight: CGFloat = 0

    // 拖动 / 缩放 / 旋转的 base 快照(SwiftUI @State,避免 onChanged 的累计 jitter)。
    @State private var dragStartElementSnapshot: AnnotationElement? = nil
    @State private var resizeStartSnapshot: AnnotationElement? = nil
    @State private var rotateStartSnapshot: AnnotationElement? = nil

    private let textFontSize: CGFloat = 24
    private let lineWidthOptions: [CGFloat] = [3, 6, 10]

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
                            width: selectedLineWidth,
                            mode: toolMode
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        // 元素渲染:不响应手势,纯绘制(包括文字 TextField)。
                        elementsLayer(size: geo.size)
                        // 创建 overlay:line/rect/circle drag-to-create + 文字点击创建。
                        createOverlay(size: geo.size)
                        textCreationOverlay(size: geo.size)
                        // 元素 hit-test 层:每个元素 bounding rect 一个透明命中区,
                        // 优先于 canvas / createOverlay 接 tap 切到选中态。
                        elementHitTestLayer(size: geo.size)
                        selectionLayer(size: geo.size)
                    }
                    .onAppear {
                        canvasBounds = CGRect(origin: .zero, size: geo.size)
                        screenHeight = UIScreen.main.bounds.height
                    }
                    .onChange(of: geo.size) { _, newSize in
                        canvasBounds = CGRect(origin: .zero, size: newSize)
                    }
                }
                unifiedToolBar
            }
            .offset(y: -keyboardShift)
            .animation(.easeOut(duration: 0.25), value: keyboardShift)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .keyboardHeightAware($keyboardHeight)
        .alert("清空所有标注?", isPresented: $showsClearConfirm) {
            Button("清空", role: .destructive) {
                canvas.drawing = PKDrawing()
                elements.removeAll()
                elementAddOrder.removeAll()
                elementUndoRedoStack.removeAll()
                deletedElements.removeAll()
                selectedElementID = nil
                editingTextID = nil
                focusedTextID = nil
                createStart = nil
                createCurrent = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会一次性抹掉所有笔迹和元素。")
        }
    }

    // MARK: - 键盘 shift 计算

    /// 编辑文字时,如果文字元素 y 落在键盘遮挡区,把整个视图向上平移让它在键盘上方约 60pt。
    /// shift = max(0, (elementCenterY + 60) - (screenHeight - keyboardHeight))
    private var keyboardShift: CGFloat {
        guard let editingID = editingTextID, keyboardHeight > 0,
              let el = elements.first(where: { $0.id == editingID }),
              case .text(let t) = el,
              screenHeight > 0 else {
            return 0
        }
        let visibleBottom = screenHeight - keyboardHeight
        let wantedTop = t.center.y + 60
        return max(0, wantedTop - visibleBottom)
    }

    // MARK: - Layers

    /// 元素渲染层。每个元素根据自身 rotation / rect / color 画出来。
    /// 不响应手势(命中走 elementHitTestLayer)。
    @ViewBuilder
    private func elementsLayer(size: CGSize) -> some View {
        ZStack {
            ForEach(elements) { el in
                elementVisual(el)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)  // 渲染层不吃手势
    }

    /// 元素的纯渲染(不带手势)。文字编辑态用 TextField,可正常响应键盘。
    @ViewBuilder
    private func elementVisual(_ el: AnnotationElement) -> some View {
        switch el {
        case .line(let l):
            let rect = lineBounds(l)
            Path { p in
                p.move(to: CGPoint(x: l.start.x - rect.minX, y: l.start.y - rect.minY))
                p.addLine(to: CGPoint(x: l.end.x - rect.minX, y: l.end.y - rect.minY))
            }
            .stroke(l.color, style: StrokeStyle(lineWidth: l.lineWidth, lineCap: .round))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
        case .rect(let r):
            Rectangle()
                .stroke(r.color, style: StrokeStyle(lineWidth: r.lineWidth, lineCap: .round, lineJoin: .round))
                .frame(width: max(r.rect.width, 1), height: max(r.rect.height, 1))
                .rotationEffect(r.rotation)
                .position(x: r.rect.midX, y: r.rect.midY)
        case .circle(let c):
            Ellipse()
                .stroke(c.color, style: StrokeStyle(lineWidth: c.lineWidth, lineCap: .round))
                .frame(width: max(c.rect.width, 1), height: max(c.rect.height, 1))
                .rotationEffect(c.rotation)
                .position(x: c.rect.midX, y: c.rect.midY)
        case .text(let t):
            let isEditing = editingTextID == t.id
            Group {
                if isEditing {
                    TextField("输入文字…", text: bindingForTextContent(t.id))
                        .focused($focusedTextID, equals: t.id)
                        .font(.system(size: t.fontSize, weight: .semibold))
                        .foregroundStyle(t.color)
                        .multilineTextAlignment(.center)
                        .frame(minWidth: 120)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onSubmit {
                            commitTextEdit(id: t.id)
                        }
                } else {
                    Text(t.content.isEmpty ? " " : t.content)
                        .font(.system(size: t.fontSize, weight: .semibold))
                        .foregroundStyle(t.color)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .rotationEffect(t.rotation)
            .position(t.center)
            // 编辑态的 TextField 需要响应输入 — 单独放行它的命中,但其他都关。
            .allowsHitTesting(isEditing)
        }
    }

    /// 元素 hit-test 层。每个元素的轴对齐 bounding rect 一个透明命中区。
    /// 优先级在 canvas / createOverlay 之上 — 任何工具模式下点元素都能选中。
    /// 编辑文字时整个层让位(避免吞掉键盘外点击)。
    @ViewBuilder
    private func elementHitTestLayer(size: CGSize) -> some View {
        ZStack {
            ForEach(elements) { el in
                elementHitArea(el)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(editingTextID == nil)
    }

    /// 单个元素的命中区:透明 rect 在元素 bounding box 处,接 tap + drag。
    @ViewBuilder
    private func elementHitArea(_ el: AnnotationElement) -> some View {
        let box = boundingBox(el)
        let rot = elementRotation(el)
        let hitW = max(box.width, 24)
        let hitH = max(box.height, 24)
        Color.clear
            .contentShape(Rectangle())
            .frame(width: hitW, height: hitH)
            .rotationEffect(rot)
            .position(x: box.midX, y: box.midY)
            .onTapGesture {
                selectElement(el.id)
            }
            .gesture(elementDragGesture(elementID: el.id))
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded { _ in
                        if case .text = el { beginTextEdit(el.id) }
                    }
            )
    }

    /// 选中元素的 chrome:虚线外框 + handle(rotate / delete / resize)。
    @ViewBuilder
    private func selectionLayer(size: CGSize) -> some View {
        if let sid = selectedElementID, editingTextID == nil,
           let el = elements.first(where: { $0.id == sid }) {
            selectionChrome(el)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(true)
        }
    }

    @ViewBuilder
    private func selectionChrome(_ el: AnnotationElement) -> some View {
        let box = boundingBox(el)
        let rot = elementRotation(el)
        let chromeColor = Color.cyan
        ZStack {
            // 虚线外框
            Rectangle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(chromeColor)
                .frame(width: max(box.width, 24), height: max(box.height, 24))
                .rotationEffect(rot)
                .position(x: box.midX, y: box.midY)
                .allowsHitTesting(false)

            // 4 角缩放 handle(锚定对角)
            ForEach(0..<4) { i in
                let cornerLocal = cornerOffset(index: i, box: box)
                let cornerWorld = rotatedPoint(local: cornerLocal, center: CGPoint(x: box.midX, y: box.midY), rotation: rot)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(chromeColor, lineWidth: 2))
                    .frame(width: 18, height: 18)
                    .position(cornerWorld)
                    .gesture(resizeGesture(cornerIndex: i, elementID: el.id))
            }

            // 旋转 handle:外框正上方 28pt
            let topMid = CGPoint(x: 0, y: -max(box.height, 24) / 2 - 28)
            let rotHandleWorld = rotatedPoint(local: topMid, center: CGPoint(x: box.midX, y: box.midY), rotation: rot)
            Circle()
                .fill(chromeColor)
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                )
                .position(rotHandleWorld)
                .gesture(rotateGesture(elementID: el.id))

            // 删除 handle:外框右上 +18,-18 (相对中心)
            let delLocal = CGPoint(x: max(box.width, 24) / 2 + 16, y: -max(box.height, 24) / 2 - 16)
            let delWorld = rotatedPoint(local: delLocal, center: CGPoint(x: box.midX, y: box.midY), rotation: rot)
            Button {
                deleteElement(el.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            .position(delWorld)
        }
    }

    /// drag-to-create overlay(line / rect / circle 模式)。
    /// 元素 hit-test 层在它上面,所以点已有元素优先切到选中,不会误开 create。
    @ViewBuilder
    private func createOverlay(size: CGSize) -> some View {
        let isCreating = toolMode == .line || toolMode == .rect || toolMode == .circle
        ZStack {
            if isCreating {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                if createStart == nil { createStart = value.startLocation }
                                createCurrent = value.location
                            }
                            .onEnded { value in
                                let start = createStart ?? value.startLocation
                                let end = value.location
                                commitCreation(start: start, end: end)
                                createStart = nil
                                createCurrent = nil
                            }
                    )
            }
            // 预览
            if let s = createStart, let c = createCurrent {
                let r = boundingRect(from: s, to: c)
                switch toolMode {
                case .line:
                    Path { p in
                        p.move(to: s)
                        p.addLine(to: c)
                    }
                    .stroke(selectedColor, style: StrokeStyle(lineWidth: selectedLineWidth, lineCap: .round))
                case .rect:
                    Rectangle()
                        .stroke(selectedColor, style: StrokeStyle(lineWidth: selectedLineWidth, lineCap: .round, lineJoin: .round))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                case .circle:
                    Ellipse()
                        .stroke(selectedColor, style: StrokeStyle(lineWidth: selectedLineWidth, lineCap: .round))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                default:
                    EmptyView()
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(isCreating)
    }

    /// .text 模式下,点空白处创建文字元素。
    @ViewBuilder
    private func textCreationOverlay(size: CGSize) -> some View {
        ZStack {
            if toolMode == .text {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        addTextElement(at: location)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(toolMode == .text && editingTextID == nil)
    }

    // MARK: - 元素创建

    private func commitCreation(start: CGPoint, end: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx * dx + dy * dy > 9 else { return }  // 太短不画
        switch toolMode {
        case .line:
            let el = LineElement(id: UUID(), start: start, end: end,
                                 color: selectedColor, lineWidth: selectedLineWidth)
            registerElement(.line(el))
        case .rect:
            let r = boundingRect(from: start, to: end)
            guard r.width > 4, r.height > 4 else { return }
            let el = RectElement(id: UUID(), rect: r, color: selectedColor,
                                 lineWidth: selectedLineWidth, rotation: .zero)
            registerElement(.rect(el))
        case .circle:
            let r = boundingRect(from: start, to: end)
            guard r.width > 4, r.height > 4 else { return }
            let el = CircleElement(id: UUID(), rect: r, color: selectedColor,
                                   lineWidth: selectedLineWidth, rotation: .zero)
            registerElement(.circle(el))
        default:
            break
        }
    }

    /// 文字元素创建 + 立刻进入编辑态。
    private func addTextElement(at location: CGPoint) {
        let new = TextElement(
            id: UUID(),
            center: location,
            content: "",
            fontSize: textFontSize,
            color: selectedColor,
            rotation: .zero
        )
        registerElement(.text(new))
        editingTextID = new.id
        selectedElementID = new.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            focusedTextID = new.id
        }
    }

    private func registerElement(_ el: AnnotationElement) {
        elements.append(el)
        elementAddOrder.append(el.id)
        elementUndoRedoStack.removeAll()
    }

    // MARK: - 文字编辑

    private func bindingForTextContent(_ id: UUID) -> Binding<String> {
        Binding<String>(
            get: {
                if case .text(let t) = elements.first(where: { $0.id == id }) ?? .text(TextElement(id: id, center: .zero, content: "", fontSize: 0, color: .clear, rotation: .zero)) {
                    return t.content
                }
                return ""
            },
            set: { newValue in
                if let idx = elements.firstIndex(where: { $0.id == id }),
                   case .text(var t) = elements[idx] {
                    t.content = newValue
                    elements[idx] = .text(t)
                }
            }
        )
    }

    private func beginTextEdit(_ id: UUID) {
        editingTextID = id
        selectedElementID = id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            focusedTextID = id
        }
    }

    private func commitTextEdit(id: UUID) {
        focusedTextID = nil
        editingTextID = nil
        // 空文字直接删
        if let idx = elements.firstIndex(where: { $0.id == id }),
           case .text(let t) = elements[idx],
           t.content.trimmingCharacters(in: .whitespaces).isEmpty {
            deleteElement(id, silent: true)
        }
    }

    private func cancelTextEditIfAny() {
        if let id = editingTextID {
            commitTextEdit(id: id)
        }
    }

    // MARK: - 选中 / 拖动 / 缩放 / 旋转 / 删除

    /// 点元素 → 直接切到选中态。编辑中文字时跳过(键盘 dismiss 由 TextField 自己管)。
    private func selectElement(_ id: UUID) {
        if editingTextID != nil { return }
        selectedElementID = id
    }

    /// 元素整体拖动手势。base + delta 模式:onChanged 第一帧 snapshot,后续帧用 translation 算绝对位置。
    /// 不在拖动中加 animation(避免迟滞),用 transaction 显式关掉。
    private func elementDragGesture(elementID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard editingTextID == nil else { return }
                if selectedElementID != elementID { selectedElementID = elementID }
                if dragStartElementSnapshot?.id != elementID {
                    dragStartElementSnapshot = elements.first(where: { $0.id == elementID })
                }
                var t = Transaction()
                t.animation = nil
                t.disablesAnimations = true
                withTransaction(t) {
                    translateElement(elementID, by: value.translation)
                }
            }
            .onEnded { _ in
                dragStartElementSnapshot = nil
            }
    }

    /// 平移 — 用 snapshot + translation 算绝对位置,避免增量累加 jitter。
    private func translateElement(_ id: UUID, by translation: CGSize) {
        guard let idx = elements.firstIndex(where: { $0.id == id }),
              let snap = dragStartElementSnapshot else { return }
        let dx = translation.width
        let dy = translation.height
        switch snap {
        case .line(let l):
            var n = l
            n.start = CGPoint(x: l.start.x + dx, y: l.start.y + dy)
            n.end = CGPoint(x: l.end.x + dx, y: l.end.y + dy)
            elements[idx] = .line(n)
        case .rect(let r):
            var n = r
            n.rect = r.rect.offsetBy(dx: dx, dy: dy)
            elements[idx] = .rect(n)
        case .circle(let c):
            var n = c
            n.rect = c.rect.offsetBy(dx: dx, dy: dy)
            elements[idx] = .circle(n)
        case .text(let t):
            var n = t
            n.center = CGPoint(x: t.center.x + dx, y: t.center.y + dy)
            elements[idx] = .text(n)
        }
    }

    /// resize handle 拖动 — 缩放元素。锚定对角保持不动。
    /// base + delta:snapshot 当帧 rect / 端点,后续用 translation 算 new rect。
    private func resizeGesture(cornerIndex: Int, elementID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard let idx = elements.firstIndex(where: { $0.id == elementID }) else { return }
                if resizeStartSnapshot?.id != elementID {
                    resizeStartSnapshot = elements[idx]
                }
                guard let snap = resizeStartSnapshot else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                var t = Transaction()
                t.animation = nil
                t.disablesAnimations = true
                withTransaction(t) {
                    switch snap {
                    case .line(let l):
                        var n = l
                        if cornerIndex == 0 || cornerIndex == 3 {
                            n.start = CGPoint(x: l.start.x + dx, y: l.start.y + dy)
                        } else {
                            n.end = CGPoint(x: l.end.x + dx, y: l.end.y + dy)
                        }
                        elements[idx] = .line(n)
                    case .rect(let r):
                        var n = r
                        n.rect = resizedRect(from: r.rect, corner: cornerIndex, dx: dx, dy: dy)
                        elements[idx] = .rect(n)
                    case .circle(let c):
                        var n = c
                        n.rect = resizedRect(from: c.rect, corner: cornerIndex, dx: dx, dy: dy)
                        elements[idx] = .circle(n)
                    case .text(let t):
                        // 文字用 corner drag 改字号(基于 snapshot 字号 + dy 线性缩放)
                        var n = t
                        let dir: CGFloat = (cornerIndex == 0 || cornerIndex == 1) ? -1 : 1
                        let scale = max(0.4, 1 + (dy / 100.0) * dir)
                        n.fontSize = max(8, min(120, t.fontSize * scale))
                        elements[idx] = .text(n)
                    }
                }
            }
            .onEnded { _ in
                resizeStartSnapshot = nil
            }
    }

    /// 旋转 handle 拖动 — 围绕元素中心旋转。
    /// 用 snapshot.angle + (currentAngle - startAngle) 的方式,避免初始跳变。
    @State private var rotateStartHandleAngle: Double = 0
    @State private var rotateStartElementAngle: Angle = .zero

    private func rotateGesture(elementID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard let idx = elements.firstIndex(where: { $0.id == elementID }) else { return }
                if rotateStartSnapshot?.id != elementID {
                    rotateStartSnapshot = elements[idx]
                    rotateStartElementAngle = elementRotation(elements[idx])
                    let snapBox = boundingBox(elements[idx])
                    let center = CGPoint(x: snapBox.midX, y: snapBox.midY)
                    let v0 = CGPoint(x: value.startLocation.x - center.x, y: value.startLocation.y - center.y)
                    rotateStartHandleAngle = atan2(Double(v0.x), Double(-v0.y))
                }
                guard let snap = rotateStartSnapshot else { return }
                let box = boundingBox(snap)
                let center = CGPoint(x: box.midX, y: box.midY)
                let v = CGPoint(x: value.location.x - center.x, y: value.location.y - center.y)
                let nowAngle = atan2(Double(v.x), Double(-v.y))
                let delta = nowAngle - rotateStartHandleAngle
                let newAngle = Angle(radians: rotateStartElementAngle.radians + delta)
                var t = Transaction()
                t.animation = nil
                t.disablesAnimations = true
                withTransaction(t) {
                    switch snap {
                    case .line:
                        rotateLine(idx: idx, snapshot: snap, newAngle: newAngle)
                    case .rect(let r):
                        var n = r
                        n.rotation = newAngle
                        elements[idx] = .rect(n)
                    case .circle(let c):
                        var n = c
                        n.rotation = newAngle
                        elements[idx] = .circle(n)
                    case .text(let t):
                        var n = t
                        n.rotation = newAngle
                        elements[idx] = .text(n)
                    }
                }
            }
            .onEnded { _ in
                rotateStartSnapshot = nil
            }
    }

    private func rotateLine(idx: Int, snapshot: AnnotationElement, newAngle: Angle) {
        guard case .line(let l) = snapshot else { return }
        let center = CGPoint(x: (l.start.x + l.end.x) / 2, y: (l.start.y + l.end.y) / 2)
        let half = hypot(l.end.x - l.start.x, l.end.y - l.start.y) / 2
        // 0° = up 对线段来说定义"end 朝上"
        let a = newAngle.radians
        let dx = sin(a) * half
        let dy = -cos(a) * half
        var n = l
        n.start = CGPoint(x: center.x - dx, y: center.y - dy)
        n.end = CGPoint(x: center.x + dx, y: center.y + dy)
        elements[idx] = .line(n)
    }

    private func deleteElement(_ id: UUID, silent: Bool = false) {
        guard let idx = elements.firstIndex(where: { $0.id == id }) else { return }
        let removed = elements.remove(at: idx)
        if !silent {
            deletedElements[id] = removed
            elementUndoRedoStack.append(id)
        }
        elementAddOrder.removeAll { $0 == id }
        if selectedElementID == id { selectedElementID = nil }
        if editingTextID == id { editingTextID = nil }
        if focusedTextID == id { focusedTextID = nil }
    }

    // MARK: - 撤销 / 重做

    /// PencilKit 自带撤销栈优先;否则撤销最后一个元素。
    private func performUndo() {
        cancelTextEditIfAny()
        if let um = canvas.undoManager, um.canUndo {
            um.undo()
            return
        }
        guard let lastID = elementAddOrder.popLast() else { return }
        if let idx = elements.firstIndex(where: { $0.id == lastID }) {
            let removed = elements.remove(at: idx)
            deletedElements[lastID] = removed
            elementUndoRedoStack.append(lastID)
        }
        if selectedElementID == lastID { selectedElementID = nil }
    }

    private func performRedo() {
        cancelTextEditIfAny()
        if let um = canvas.undoManager, um.canRedo {
            um.redo()
            return
        }
        guard let lastID = elementUndoRedoStack.popLast(),
              let restored = deletedElements.removeValue(forKey: lastID) else { return }
        elements.append(restored)
        elementAddOrder.append(lastID)
    }

    // MARK: - 工具栏

    private var headerBar: some View {
        Text("标注照片")
            .foregroundStyle(.white)
            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
    }

    /// 底部工具栏:4 行布局。
    /// Row 1: 颜色 + 粗细
    /// Row 2: 工具(画笔/直线/矩形/椭圆/文字/橡皮)— 选择按钮已去掉
    /// Row 3: 撤销 / 重做 / 清空
    /// Row 4: 取消 / 保存
    private var unifiedToolBar: some View {
        VStack(spacing: 10) {
            colorAndWidthRow
            toolRow
            actionIconsRow
            bottomActionsRow
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color.black)
    }

    /// Row 1: 6 颜色 + 3 档粗细
    private var colorAndWidthRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                ForEach([Color.red, Color.yellow, Color.green, Color.blue, Color.white, Color.black], id: \.self) { color in
                    Button {
                        selectedColor = color
                        if let id = selectedElementID,
                           let idx = elements.firstIndex(where: { $0.id == id }) {
                            var e = elements[idx]
                            e.color = color
                            elements[idx] = e
                        }
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle().stroke(Color.white, lineWidth: selectedColor == color ? 3 : 1)
                            )
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(String(localized: "选择颜色", locale: AppLanguageManager.currentLocale))
                }
            }
            HStack(spacing: 16) {
                ForEach(lineWidthOptions, id: \.self) { w in
                    Button {
                        selectedLineWidth = w
                        if let id = selectedElementID,
                           let idx = elements.firstIndex(where: { $0.id == id }) {
                            var e = elements[idx]
                            e.lineWidth = w
                            elements[idx] = e
                        }
                    } label: {
                        Capsule()
                            .fill(Color.white)
                            .frame(width: 28, height: w)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedLineWidth == w ? Color.white.opacity(0.25) : Color.white.opacity(0.08))
                            )
                    }
                    .accessibilityLabel(String(localized: "粗细"))
                }
            }
        }
    }

    /// Row 2: 6 工具均分宽度。选择按钮已移除(点元素自动选中)。
    private var toolRow: some View {
        HStack(spacing: 4) {
            toolButton(icon: "pencil.tip", label: "画笔", mode: .pen)
            toolButton(icon: "line.diagonal", label: "直线", mode: .line)
            toolButton(icon: "square", label: "框", mode: .rect)
            toolButton(icon: "circle", label: "圆", mode: .circle)
            toolButton(icon: "textformat", label: "文字", mode: .text)
            toolButton(icon: "eraser", label: "橡皮", mode: .eraser)
        }
        .padding(.horizontal, 10)
    }

    private var actionIconsRow: some View {
        HStack(spacing: 10) {
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
    }

    private var bottomActionsRow: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Text(String(localized: "取消", locale: AppLanguageManager.currentLocale))
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
                Text(String(localized: "保存", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
    }

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

    private func toolButton(icon: String, label: LocalizedStringKey, mode: PhotoEditTool) -> some View {
        let active = toolMode == mode
        return Button {
            cancelTextEditIfAny()
            // 切工具时清空选中,避免选择 chrome 卡在画布上
            selectedElementID = nil
            if mode != .line && mode != .rect && mode != .circle {
                createStart = nil
                createCurrent = nil
            }
            toolMode = mode
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(active ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(active ? Color.white : Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(label)
    }

    // MARK: - 保存(image + PKDrawing + elements)

    private func save() {
        cancelTextEditIfAny()
        elements.removeAll { el in
            if case .text(let t) = el {
                return t.content.trimmingCharacters(in: .whitespaces).isEmpty
            }
            return false
        }
        selectedElementID = nil

        guard canvasBounds.width > 0, canvasBounds.height > 0 else {
            dismiss()
            return
        }

        // **R6#3 关键修**:渲染到 originalImage.size(真实像素),不再用 canvasBounds.size。
        // 之前用 canvas 尺寸(~300×400 points)→ 保存后图片严重缩小,丢失原图分辨率。
        // annotation 坐标在 canvas 空间,需要变换到原图空间(scaleBy + translateBy)。
        let outputSize = originalImage.size
        let canvasSize = canvasBounds.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // 1:1 像素,避免 retina 二次放大

        // 计算原图在 canvas 内的 aspect-fit 矩形(elements 是在这个空间画的)
        let imageAspect = outputSize.width / outputSize.height
        let canvasAspect = canvasSize.width / canvasSize.height
        let fittedImageRect: CGRect
        if imageAspect > canvasAspect {
            let h = canvasSize.width / imageAspect
            fittedImageRect = CGRect(x: 0, y: (canvasSize.height - h) / 2, width: canvasSize.width, height: h)
        } else {
            let w = canvasSize.height * imageAspect
            fittedImageRect = CGRect(x: (canvasSize.width - w) / 2, y: 0, width: w, height: canvasSize.height)
        }
        // 缩放因子:canvas(fittedImageRect)→ outputSize
        let scaleX = outputSize.width / fittedImageRect.width
        let scaleY = outputSize.height / fittedImageRect.height

        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let result = renderer.image { rendererCtx in
            let ctx = rendererCtx.cgContext

            // 1) 原图填满整个 output(无 letterbox)
            originalImage.draw(in: CGRect(origin: .zero, size: outputSize))

            // 2) 把 ctx 变换到 canvas 空间(scaleBy + translateBy),让所有后续 draw 自动放大
            ctx.saveGState()
            ctx.scaleBy(x: scaleX, y: scaleY)
            ctx.translateBy(x: -fittedImageRect.origin.x, y: -fittedImageRect.origin.y)

            // PKDrawing:绘制到 canvas 空间;scale 由上面 scaleBy 完成
            let strokeImage = canvas.drawing.image(from: canvasBounds, scale: UIScreen.main.scale)
            strokeImage.draw(in: canvasBounds)

            // Elements:坐标在 canvas 空间;变换已经 apply
            for el in elements {
                drawElement(el, in: ctx, size: canvasSize)
            }
            ctx.restoreGState()
        }
        onSave(result)
        dismiss()
    }

    /// 把 element 绘制到当前 CGContext。处理旋转 / 字体 / stroke。
    private func drawElement(_ el: AnnotationElement, in ctx: CGContext, size: CGSize) {
        switch el {
        case .line(let l):
            ctx.saveGState()
            ctx.setStrokeColor(UIColor(l.color).cgColor)
            ctx.setLineWidth(l.lineWidth)
            ctx.setLineCap(.round)
            ctx.move(to: l.start)
            ctx.addLine(to: l.end)
            ctx.strokePath()
            ctx.restoreGState()
        case .rect(let r):
            ctx.saveGState()
            ctx.translateBy(x: r.rect.midX, y: r.rect.midY)
            ctx.rotate(by: CGFloat(r.rotation.radians))
            ctx.translateBy(x: -r.rect.midX, y: -r.rect.midY)
            ctx.setStrokeColor(UIColor(r.color).cgColor)
            ctx.setLineWidth(r.lineWidth)
            ctx.setLineJoin(.round)
            ctx.stroke(r.rect)
            ctx.restoreGState()
        case .circle(let c):
            ctx.saveGState()
            ctx.translateBy(x: c.rect.midX, y: c.rect.midY)
            ctx.rotate(by: CGFloat(c.rotation.radians))
            ctx.translateBy(x: -c.rect.midX, y: -c.rect.midY)
            ctx.setStrokeColor(UIColor(c.color).cgColor)
            ctx.setLineWidth(c.lineWidth)
            ctx.setLineCap(.round)
            ctx.strokeEllipse(in: c.rect)
            ctx.restoreGState()
        case .text(let t):
            guard !t.content.isEmpty else { return }
            ctx.saveGState()
            ctx.translateBy(x: t.center.x, y: t.center.y)
            ctx.rotate(by: CGFloat(t.rotation.radians))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: t.fontSize, weight: .semibold),
                .foregroundColor: UIColor(t.color)
            ]
            let ns = t.content as NSString
            let ts = ns.size(withAttributes: attrs)
            let padH: CGFloat = 10
            let padV: CGFloat = 4
            let boxW = ts.width + padH * 2
            let boxH = ts.height + padV * 2
            let box = CGRect(x: -boxW / 2, y: -boxH / 2, width: boxW, height: boxH)
            UIColor.black.withAlphaComponent(0.25).setFill()
            UIBezierPath(roundedRect: box, cornerRadius: 6).fill()
            let textRect = box.insetBy(dx: padH, dy: padV)
            ns.draw(in: textRect, withAttributes: attrs)
            ctx.restoreGState()
        }
    }

    // MARK: - Helpers

    private func boundingRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    private func lineBounds(_ l: LineElement) -> CGRect {
        let pad = max(l.lineWidth, 8)
        return CGRect(
            x: min(l.start.x, l.end.x) - pad,
            y: min(l.start.y, l.end.y) - pad,
            width: abs(l.end.x - l.start.x) + pad * 2,
            height: abs(l.end.y - l.start.y) + pad * 2
        )
    }

    /// 元素的轴对齐外接 rect(未含旋转;chrome 里再加旋转效果)。
    private func boundingBox(_ el: AnnotationElement) -> CGRect {
        switch el {
        case .line(let l):
            return lineBounds(l)
        case .rect(let r): return r.rect
        case .circle(let c): return c.rect
        case .text(let t):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: t.fontSize, weight: .semibold)
            ]
            let ns = (t.content.isEmpty ? " " : t.content) as NSString
            let ts = ns.size(withAttributes: attrs)
            let w = ts.width + 20
            let h = ts.height + 8
            return CGRect(x: t.center.x - w / 2, y: t.center.y - h / 2, width: w, height: h)
        }
    }

    private func elementRotation(_ el: AnnotationElement) -> Angle {
        switch el {
        case .line(let l):
            let a = atan2(l.end.x - l.start.x, -(l.end.y - l.start.y))
            return Angle(radians: Double(a))
        case .rect(let r): return r.rotation
        case .circle(let c): return c.rotation
        case .text(let t): return t.rotation
        }
    }

    /// 4 角偏移(以 box 中心为原点)
    private func cornerOffset(index: Int, box: CGRect) -> CGPoint {
        let w = max(box.width, 24) / 2
        let h = max(box.height, 24) / 2
        switch index {
        case 0: return CGPoint(x: -w, y: -h)
        case 1: return CGPoint(x: w, y: -h)
        case 2: return CGPoint(x: w, y: h)
        default: return CGPoint(x: -w, y: h)
        }
    }

    private func rotatedPoint(local: CGPoint, center: CGPoint, rotation: Angle) -> CGPoint {
        let cosA = cos(rotation.radians)
        let sinA = sin(rotation.radians)
        let rx = local.x * cosA - local.y * sinA
        let ry = local.x * sinA + local.y * cosA
        return CGPoint(x: center.x + rx, y: center.y + ry)
    }

    /// resize:corner 0=TL, 1=TR, 2=BR, 3=BL。锚定对角不动。
    private func resizedRect(from rect: CGRect, corner: Int, dx: CGFloat, dy: CGFloat) -> CGRect {
        var x = rect.origin.x
        var y = rect.origin.y
        var w = rect.width
        var h = rect.height
        switch corner {
        case 0: // top-left, anchor BR
            x += dx; y += dy; w -= dx; h -= dy
        case 1: // top-right, anchor BL
            y += dy; w += dx; h -= dy
        case 2: // bottom-right, anchor TL
            w += dx; h += dy
        default: // bottom-left, anchor TR
            x += dx; w -= dx; h += dy
        }
        if w < 8 { w = 8 }
        if h < 8 { h = 8 }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - PKCanvasView 包装

/// PKCanvasView 的 SwiftUI 包装。按 mode 切换 PKInkingTool / PKEraserTool,
/// 非 pen/eraser 模式下禁用交互让事件穿透给上层 overlay。
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

    private func isInteractive(_ mode: PhotoEditTool) -> Bool {
        switch mode {
        case .pen, .eraser: return true
        case .text, .line, .rect, .circle: return false
        }
    }

    private func applyTool(_ view: PKCanvasView) {
        switch mode {
        case .pen:
            view.tool = PKInkingTool(.pen, color: color, width: width)
        case .eraser:
            view.tool = PKEraserTool(.bitmap)
        case .text, .line, .rect, .circle:
            break
        }
    }
}
