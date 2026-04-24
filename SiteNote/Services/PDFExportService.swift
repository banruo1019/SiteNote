//
//  PDFExportService.swift
//  SiteNote
//
//  把一组 Note 渲染成 PDF 巡检日志。用 UIGraphicsPDFRenderer,无第三方依赖。
//

import Foundation
import UIKit

/// 巡检日志 PDF 生成服务。
enum PDFExportService {

    enum ExportError: LocalizedError {
        case renderFailed(String)

        var errorDescription: String? {
            switch self {
            case .renderFailed(let detail): return "PDF 生成失败: \(detail)"
            }
        }
    }

    /// 生成 PDF 并写到临时目录,返回 URL。
    /// - Parameters:
    ///   - notes: 要导出的 note,按调用方顺序渲染(通常按 createdAt 升序)。
    ///   - startDate/endDate: 可选的日期范围,显示在封面。
    ///   - title: PDF 封面大标题。
    ///   - includeCoverPage: 是否生成封面。单条分享时建议 false。
    ///   - filenamePrefix: 生成的 PDF 文件名前缀,默认 `SiteNote-Log`。
    static func generatePDF(
        notes: [Note],
        startDate: Date?,
        endDate: Date?,
        title: String = "SiteNote 巡检日志",
        includeCoverPage: Bool = true,
        filenamePrefix: String = "SiteNote-Log"
    ) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let filename = "\(filenamePrefix)-\(Int(Date().timeIntervalSince1970)).pdf"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: outputURL)

        do {
            try renderer.writePDF(to: outputURL) { context in
                if includeCoverPage {
                    drawCoverPage(
                        context: context,
                        title: title,
                        notes: notes,
                        startDate: startDate,
                        endDate: endDate,
                        in: pageRect
                    )
                }
                for note in notes {
                    context.beginPage()
                    drawNotePage(context: context, note: note, in: pageRect)
                }
            }
        } catch {
            throw ExportError.renderFailed(error.localizedDescription)
        }

        return outputURL
    }

    // MARK: - Pages

    /// 统一的日期时间格式(含小时),和 PDFExportView 的 rangeFormatter 对齐。
    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static func drawCoverPage(
        context: UIGraphicsPDFRendererContext,
        title: String,
        notes: [Note],
        startDate: Date?,
        endDate: Date?,
        in pageRect: CGRect
    ) {
        context.beginPage()

        let leftMargin: CGFloat = 50
        var y: CGFloat = 100

        drawText(title, at: CGPoint(x: leftMargin, y: y), fontSize: 32, bold: true)
        y += 60

        if let start = startDate, let end = endDate {
            let range = "日期范围: \(rangeFormatter.string(from: start))  —  \(rangeFormatter.string(from: end))"
            drawText(range, at: CGPoint(x: leftMargin, y: y), fontSize: 16)
            y += 30
        }

        drawText("共 \(notes.count) 条速记", at: CGPoint(x: leftMargin, y: y), fontSize: 16)
        y += 30

        let exportAt = "导出时间: \(rangeFormatter.string(from: Date()))"
        drawText(exportAt, at: CGPoint(x: leftMargin, y: y), fontSize: 14, color: .darkGray)
    }

    private static func drawNotePage(
        context: UIGraphicsPDFRendererContext,
        note: Note,
        in pageRect: CGRect
    ) {
        let leftMargin: CGFloat = 40
        let contentWidth = pageRect.width - leftMargin * 2
        var y: CGFloat = 50

        // 隐患红色大横幅(首要突出)
        if note.isHazard {
            let bannerRect = CGRect(x: leftMargin, y: y, width: contentWidth, height: 30)
            UIColor.systemRed.withAlphaComponent(0.15).setFill()
            UIBezierPath(roundedRect: bannerRect, cornerRadius: 6).fill()
            drawText(
                "🚨 隐患 / HAZARD",
                at: CGPoint(x: leftMargin + 10, y: y + 6),
                fontSize: 14,
                bold: true,
                color: .systemRed
            )
            y += 38
        }

        // 头部日期时间(精确到小时,格式和封面统一)
        drawText(rangeFormatter.string(from: note.createdAt), at: CGPoint(x: leftMargin, y: y), fontSize: 20, bold: true)
        y += 32

        // 元信息
        var metaLines: [String] = []
        if let addr = note.locationAddress { metaLines.append("位置: \(addr)") }
        if let weather = note.weatherSummary { metaLines.append("天气: \(weather)") }
        if let tag = note.siteTag { metaLines.append("工地: \(tag)") }
        if let assignee = note.assignedTo { metaLines.append("分派给: \(assignee)") }
        if let clauseRef = note.contractClauseRef { metaLines.append("合同条款: \(clauseRef)") }
        for line in metaLines {
            drawText(line, at: CGPoint(x: leftMargin, y: y), fontSize: 12, color: .darkGray)
            y += 18
        }

        // Deadline + 状态
        let dueStr = note.dueDate.formatted(date: .abbreviated, time: .omitted)
        let deadlineStr = "到期: \(note.deadline.displayName) (\(dueStr))"
        let statusStr = note.isDone ? "状态: ✓ 已完成" : "状态: 待处理"
        drawText("\(deadlineStr)    \(statusStr)", at: CGPoint(x: leftMargin, y: y), fontSize: 12)
        y += 24

        // 分隔线
        drawLine(
            from: CGPoint(x: leftMargin, y: y),
            to: CGPoint(x: leftMargin + contentWidth, y: y)
        )
        y += 15

        // 内容
        drawText("内容", at: CGPoint(x: leftMargin, y: y), fontSize: 14, bold: true)
        y += 22

        let bodyText = note.transcription.isEmpty ? "(无转写,仅录音)" : note.transcription
        let bodyHeight = drawWrappedText(
            bodyText,
            in: CGRect(x: leftMargin, y: y, width: contentWidth, height: 250),
            fontSize: 14
        )
        y += bodyHeight + 15

        // 模板 checklist
        if let templateName = note.templateName {
            drawText("巡检模板: \(templateName)",
                     at: CGPoint(x: leftMargin, y: y),
                     fontSize: 14,
                     bold: true)
            y += 20

            let template = InspectionTemplatesStorage.load().first(where: { $0.name == templateName })
            let items = template?.items ?? []
            let checkedSet = Set(note.checkedItems)

            if items.isEmpty {
                drawText("(模板不存在,原检查项: \(note.checkedItems.joined(separator: ", ")))",
                         at: CGPoint(x: leftMargin, y: y),
                         fontSize: 12,
                         color: .darkGray)
                y += 18
            } else {
                for item in items {
                    let checked = checkedSet.contains(item)
                    let marker = checked ? "☑" : "☐"
                    drawText("\(marker) \(item)",
                             at: CGPoint(x: leftMargin, y: y),
                             fontSize: 12,
                             color: checked ? .darkGray : .black)
                    y += 18
                }
            }
            y += 10
        }

        // 平面图(若有)+ 图钉位置
        if let planName = note.floorPlanRef,
           let x = note.floorPlanX,
           let yNorm = note.floorPlanY,
           let plan = FloorPlansStorage.find(name: planName),
           let planURL = FloorPlansStorage.absoluteURL(forRelative: plan.imageRelativePath),
           let planImage = UIImage(contentsOfFile: planURL.path) {
            drawText("平面图位置: \(planName)",
                     at: CGPoint(x: leftMargin, y: y),
                     fontSize: 14,
                     bold: true)
            y += 22

            let planW = contentWidth
            let planH: CGFloat = 240
            let planRect = CGRect(x: leftMargin, y: y, width: planW, height: planH)
            drawFloorPlanWithPin(
                planImage,
                normalizedX: x,
                normalizedY: yNorm,
                in: planRect,
                pinColor: pinUIColor(for: note)
            )
            y += planH + 15
        }

        // 照片 2x2,最多 4 张
        if !note.photoPaths.isEmpty {
            drawText("照片 (\(note.photoPaths.count) 张,最多显示 4)",
                     at: CGPoint(x: leftMargin, y: y),
                     fontSize: 14,
                     bold: true)
            y += 22

            let photoSize: CGFloat = min(220, (contentWidth - 10) / 2)
            let gap: CGFloat = 10
            for (index, photoPath) in note.photoPaths.prefix(4).enumerated() {
                let col = index % 2
                let row = index / 2
                let x = leftMargin + CGFloat(col) * (photoSize + gap)
                let photoY = y + CGFloat(row) * (photoSize + gap)

                if let url = PhotoStorage.absoluteURL(forRelative: photoPath),
                   let image = UIImage(contentsOfFile: url.path) {
                    drawFittedImage(image, in: CGRect(x: x, y: photoY, width: photoSize, height: photoSize))
                }
            }
        }
    }

    /// 画一张平面图并在归一化坐标处打图钉。
    /// 图片按 aspect fit 居中(和 `FloorPlanGeometry.displayRect` 同口径),
    /// 所以 x/y 归一化坐标要在 image-rect 内解释,不是 rect 全框。
    private static func drawFloorPlanWithPin(
        _ image: UIImage,
        normalizedX: Double,
        normalizedY: Double,
        in rect: CGRect,
        pinColor: UIColor
    ) {
        // 浅灰底
        UIColor(white: 0.95, alpha: 1).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()

        let imgRect = fitRect(imageSize: image.size, in: rect)
        image.draw(in: imgRect)

        let pinX = imgRect.minX + imgRect.width * CGFloat(normalizedX)
        let pinY = imgRect.minY + imgRect.height * CGFloat(normalizedY)

        let dotRadius: CGFloat = 7
        let outerRadius: CGFloat = dotRadius + 2

        // 白描边
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(
            x: pinX - outerRadius,
            y: pinY - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        )).fill()

        // 彩点(按分类颜色)
        pinColor.setFill()
        UIBezierPath(ovalIn: CGRect(
            x: pinX - dotRadius,
            y: pinY - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )).fill()

        // 十字准星帮助定位
        UIColor.white.setStroke()
        let cross = UIBezierPath()
        cross.move(to: CGPoint(x: pinX - 3, y: pinY))
        cross.addLine(to: CGPoint(x: pinX + 3, y: pinY))
        cross.move(to: CGPoint(x: pinX, y: pinY - 3))
        cross.addLine(to: CGPoint(x: pinX, y: pinY + 3))
        cross.lineWidth = 1.5
        cross.stroke()
    }

    /// PDF 图钉颜色规则,和 app 里一致:done 灰 → hazard 红 → 分类色 → 默认蓝。
    private static func pinUIColor(for note: Note) -> UIColor {
        if note.isDone { return .systemGray }
        if note.isHazard { return .systemRed }
        if let firstSub = note.otherTags.first {
            return SubTagsStorage.uiColor(name: firstSub)
        }
        return .systemBlue
    }

    /// aspect fit 的辅助:给定图片大小和外框,返回图片实际绘制的居中矩形。
    private static func fitRect(imageSize: CGSize, in frame: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return frame }
        let imgAspect = imageSize.width / imageSize.height
        let frameAspect = frame.width / frame.height
        if imgAspect > frameAspect {
            let h = frame.width / imgAspect
            return CGRect(x: frame.minX, y: frame.minY + (frame.height - h) / 2, width: frame.width, height: h)
        } else {
            let w = frame.height * imgAspect
            return CGRect(x: frame.minX + (frame.width - w) / 2, y: frame.minY, width: w, height: frame.height)
        }
    }

    // MARK: - Primitive drawing helpers

    private static func drawText(
        _ text: String,
        at point: CGPoint,
        fontSize: CGFloat,
        bold: Bool = false,
        color: UIColor = .black
    ) {
        let font = bold ? UIFont.boldSystemFont(ofSize: fontSize) : UIFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        text.draw(at: point, withAttributes: attrs)
    }

    @discardableResult
    private static func drawWrappedText(_ text: String, in rect: CGRect, fontSize: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let bounding = attributed.boundingRect(
            with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let heightNeeded = ceil(bounding.height)
        attributed.draw(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: heightNeeded))
        return heightNeeded
    }

    private static func drawLine(from p1: CGPoint, to p2: CGPoint) {
        let path = UIBezierPath()
        path.move(to: p1)
        path.addLine(to: p2)
        UIColor.lightGray.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    /// 按 aspect fit 规则把图画到目标矩形里(居中,不变形)。
    private static func drawFittedImage(_ image: UIImage, in rect: CGRect) {
        let imageAspect = image.size.width / image.size.height
        let rectAspect = rect.width / rect.height
        let target: CGRect
        if imageAspect > rectAspect {
            let h = rect.width / imageAspect
            target = CGRect(x: rect.minX, y: rect.minY + (rect.height - h) / 2, width: rect.width, height: h)
        } else {
            let w = rect.height * imageAspect
            target = CGRect(x: rect.minX + (rect.width - w) / 2, y: rect.minY, width: w, height: rect.height)
        }
        image.draw(in: target)
    }
}
