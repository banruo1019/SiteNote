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
            case .renderFailed(let detail): return String(localized: "PDF 生成失败:\(detail)", locale: AppLanguageManager.currentLocale)
            }
        }
    }

    /// 生成 PDF 并写到临时目录,返回 URL。
    /// v1.6 (en-v1) 大改:
    ///   • 封面改成 4 行 KV 表(Site / Date / Prepared by / Entries),无 summary
    ///   • Per-note 砍 7 个 meta 行(位置/天气/工地/分派/合同/到期/状态)
    ///   • 紧凑布局:一页可堆 5-6 条,floor plan 缩成 80pt 缩略图 + pin
    /// - Parameters:
    ///   - notes: 要导出的 note,按调用方顺序渲染(通常按 createdAt 升序)。
    ///   - startDate/endDate: 可选的日期范围,显示在封面。
    ///   - title: PDF 封面大标题(默认 "DAILY SITE DIARY")。
    ///   - includeCoverPage: 是否生成封面。单条分享时建议 false。
    ///   - filenamePrefix: 生成的 PDF 文件名前缀,默认 `SiteNote-Log`。
    static func generatePDF(
        notes: [Note],
        startDate: Date?,
        endDate: Date?,
        title: String = String(localized: "DAILY SITE DIARY", locale: AppLanguageManager.currentLocale),
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
                drawNotesCompact(context: context, notes: notes, in: pageRect)
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

    /// v1.6 (en-v1):Daily Site Diary 封面 — 大标题 + 工地名 + 4 行 KV 表。
    /// 取代原"日期范围 + 条数 + 导出时间"3 行流水文字。
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
        let contentWidth = pageRect.width - leftMargin * 2

        // 顶部右上 Logo(若 BrandingStorage 提供)
        if let logo = BrandingStorage.loadLogo() {
            let maxEdge: CGFloat = 50
            let scale = min(maxEdge / logo.size.width, maxEdge / logo.size.height, 1.0)
            let drawW = logo.size.width * scale
            let drawH = logo.size.height * scale
            logo.draw(in: CGRect(
                x: pageRect.width - leftMargin - drawW,
                y: 50,
                width: drawW, height: drawH
            ))
        }

        // 顶部右上日期
        let topDateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.darkGray
        ]
        let mainDate = startDate ?? Date()
        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_AU")
        dateOnly.dateStyle = .long
        let dateStr = dateOnly.string(from: mainDate)
        let dateText = dateStr as NSString
        let dateSize = dateText.size(withAttributes: topDateAttrs)
        dateText.draw(
            at: CGPoint(
                x: pageRect.width - leftMargin - dateSize.width,
                y: 110
            ),
            withAttributes: topDateAttrs
        )

        var y: CGFloat = 160

        // 大标题(居中,粗黑)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        let titleNS = title as NSString
        let titleSize = titleNS.size(withAttributes: titleAttrs)
        titleNS.draw(
            at: CGPoint(x: (pageRect.width - titleSize.width) / 2, y: y),
            withAttributes: titleAttrs
        )
        y += titleSize.height + 6

        // 工地名副标题(居中)— 取首条 Note 的 siteTag,空时用 "—"
        let siteNameSubtitle = notes.compactMap { $0.siteTag }.first ?? "—"
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.darkGray
        ]
        let subNS = siteNameSubtitle as NSString
        let subSize = subNS.size(withAttributes: subAttrs)
        subNS.draw(
            at: CGPoint(x: (pageRect.width - subSize.width) / 2, y: y),
            withAttributes: subAttrs
        )
        y += subSize.height + 28

        // Divider
        drawLine(from: CGPoint(x: leftMargin, y: y), to: CGPoint(x: leftMargin + contentWidth, y: y))
        y += 20

        // KV 4-row table
        let dateRange: String
        if let s = startDate, let e = endDate {
            if Calendar.current.isDate(s, inSameDayAs: e) {
                dateRange = dateOnly.string(from: s)
            } else {
                dateRange = "\(dateOnly.string(from: s)) — \(dateOnly.string(from: e))"
            }
        } else {
            dateRange = dateOnly.string(from: mainDate)
        }

        let userName = (UserDefaults.standard.string(forKey: "settings.userProfile.displayName") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let companyName = (UserDefaults.standard.string(forKey: "settings.engineerCompanyName") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preparedBy: String = {
            switch (userName.isEmpty, companyName.isEmpty) {
            case (false, false): return "\(userName) · \(companyName)"
            case (false, true):  return userName
            case (true, false):  return companyName
            default:             return "—"
            }
        }()

        let photoCount = notes.reduce(0) { $0 + $1.photoPaths.count }
        let entriesValue = String(localized: "\(notes.count) notes · \(photoCount) photos", locale: AppLanguageManager.currentLocale)

        let kvRows: [(String, String)] = [
            (String(localized: "Site", locale: AppLanguageManager.currentLocale), siteNameSubtitle),
            (String(localized: "Date", locale: AppLanguageManager.currentLocale), dateRange),
            (String(localized: "Prepared by", locale: AppLanguageManager.currentLocale), preparedBy),
            (String(localized: "Entries", locale: AppLanguageManager.currentLocale), entriesValue)
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.darkGray
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12.5),
            .foregroundColor: UIColor.black
        ]
        let labelColWidth: CGFloat = 110
        let rowHeight: CGFloat = 24
        for (lbl, val) in kvRows {
            (lbl as NSString).draw(at: CGPoint(x: leftMargin, y: y), withAttributes: labelAttrs)
            let valRect = CGRect(
                x: leftMargin + labelColWidth, y: y - 1,
                width: contentWidth - labelColWidth, height: rowHeight
            )
            (val as NSString).draw(in: valRect, withAttributes: valueAttrs)
            y += rowHeight
        }
    }

    // MARK: - Compact per-note rendering
    //
    // v1.6 (en-v1) 新:多条 note 堆同一页,自动换页。每条只剩 时间 · 标签 · 转写 · 照片 + 平面图缩略图。
    // 砍掉位置 / 天气 / 工地 / 分派 / 合同 / 到期 / 状态 7 个字段(都已在 cover 集中表达或不再展示)。

    private static let topMargin: CGFloat = 50
    private static let bottomMargin: CGFloat = 60   // 留给 footer
    private static let sideMargin: CGFloat = 40

    private static func drawNotesCompact(
        context: UIGraphicsPDFRendererContext,
        notes: [Note],
        in pageRect: CGRect
    ) {
        guard !notes.isEmpty else { return }
        let contentWidth = pageRect.width - sideMargin * 2
        var pageIndex = 1     // page 1 已是 cover;per-note 从 page 2 起
        var cursorY: CGFloat = topMargin
        var pageOpen = false

        func beginNotePage() {
            context.beginPage()
            pageIndex += 1
            cursorY = topMargin
            pageOpen = true
        }

        for note in notes {
            // 先算这条 note 大概要多少高(估算,允许超 30pt 容差)
            let estHeight = estimateCompactNoteHeight(note: note, contentWidth: contentWidth)

            if !pageOpen {
                beginNotePage()
            } else if cursorY + estHeight > pageRect.height - bottomMargin {
                // 不够 → 在当前页画 footer,翻页
                drawPageFooter(in: pageRect, pageIndex: pageIndex)
                beginNotePage()
            }

            cursorY = drawCompactNote(
                note: note,
                pageRect: pageRect,
                startY: cursorY,
                contentWidth: contentWidth
            )
            cursorY += 12  // 条间距
        }

        if pageOpen {
            drawPageFooter(in: pageRect, pageIndex: pageIndex)
        }
    }

    /// 估计一条 compact note 占多少垂直空间。粗略 — 不精确也无碍,够触发翻页判断即可。
    private static func estimateCompactNoteHeight(note: Note, contentWidth: CGFloat) -> CGFloat {
        var h: CGFloat = 0
        h += 20  // 标题行
        // 转写行高(粗估每 80 字符 1 行,12pt 行高)
        let chars = note.transcription.count
        let lines = max(1, min(4, (chars + 79) / 80))  // 1-4 行
        h += CGFloat(lines) * 16
        // 附件行(照片 / 平面图)
        let hasMedia = !note.photoPaths.isEmpty
            || ((note.floorPlanRef ?? "").isEmpty == false && note.floorPlanX != nil)
        if hasMedia { h += 90 }
        h += 12  // 分隔线 + spacing
        return h
    }

    /// 画一条 compact note,返回新的 cursorY。
    private static func drawCompactNote(
        note: Note,
        pageRect: CGRect,
        startY: CGFloat,
        contentWidth: CGFloat
    ) -> CGFloat {
        var y = startY

        // === 标题行 ===
        // 时间 (10:30) · [🚨 Hazard or • Note] · tag
        let hourMin = DateFormatter()
        hourMin.dateFormat = "HH:mm"
        let timeStr = hourMin.string(from: note.createdAt)

        let titleColor = note.isHazard ? UIColor.systemRed : UIColor.black
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: titleColor
        ]

        var titleParts: [String] = [timeStr]
        if note.isHazard {
            titleParts.append("🚨 " + String(localized: "Hazard", locale: AppLanguageManager.currentLocale))
        }
        if let tag = note.otherTags.first, !tag.isEmpty {
            titleParts.append(tag)
        }
        let title = titleParts.joined(separator: " · ")
        (title as NSString).draw(
            at: CGPoint(x: sideMargin, y: y),
            withAttributes: titleAttrs
        )
        y += 18

        // === 转写文本 ===
        let body = note.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            let bodyHeight = drawWrappedText(
                body,
                in: CGRect(x: sideMargin, y: y, width: contentWidth, height: 80),
                fontSize: 11.5
            )
            y += bodyHeight + 4
        }

        // === 附件行:照片(64pt)+ 平面图缩略图(80pt with pin)===
        let hasFloorPin = (note.floorPlanRef ?? "").isEmpty == false
            && note.floorPlanX != nil
            && note.floorPlanY != nil
        let photoCount = min(note.photoPaths.count, 3)  // 最多 3 张 thumb

        if photoCount > 0 || hasFloorPin {
            let photoSize: CGFloat = 64
            let planSize: CGFloat = 80
            let gap: CGFloat = 8
            var x: CGFloat = sideMargin

            // 照片 thumbs
            for path in note.photoPaths.prefix(3) {
                if let url = PhotoStorage.absoluteURL(forRelative: path),
                   let img = UIImage(contentsOfFile: url.path) {
                    drawFittedImage(img, in: CGRect(x: x, y: y, width: photoSize, height: photoSize))
                }
                x += photoSize + gap
            }

            // 平面图缩略图(若有 pin)
            if hasFloorPin,
               let planName = note.floorPlanRef,
               let xN = note.floorPlanX,
               let yN = note.floorPlanY,
               let plan = FloorPlansStorage.find(name: planName),
               let planURL = FloorPlansStorage.absoluteURL(forRelative: plan.imageRelativePath),
               let planImg = UIImage(contentsOfFile: planURL.path) {
                let planRect = CGRect(x: x, y: y, width: planSize, height: planSize)
                drawFloorPlanWithPin(
                    planImg,
                    normalizedX: xN,
                    normalizedY: yN,
                    in: planRect,
                    pinColor: pinUIColor(for: note)
                )
                // 平面图名(小灰字)
                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 8.5),
                    .foregroundColor: UIColor.darkGray
                ]
                (planName as NSString).draw(
                    at: CGPoint(x: x, y: y + planSize + 1),
                    withAttributes: nameAttrs
                )
            }

            y += max(photoCount > 0 ? photoSize : 0, hasFloorPin ? planSize + 12 : 0)
            y += 6
        }

        // === 分隔线 ===
        drawLine(
            from: CGPoint(x: sideMargin, y: y + 4),
            to: CGPoint(x: sideMargin + contentWidth, y: y + 4)
        )
        return y + 8
    }

    /// Page footer: "[Company] · Page N"
    private static func drawPageFooter(in pageRect: CGRect, pageIndex: Int) {
        let companyName = (UserDefaults.standard.string(forKey: "settings.engineerCompanyName") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let label: String
        if companyName.isEmpty {
            label = String(localized: "Page \(pageIndex)", locale: AppLanguageManager.currentLocale)
        } else {
            label = "\(companyName) · " + String(localized: "Page \(pageIndex)", locale: AppLanguageManager.currentLocale)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.lightGray
        ]
        let ns = label as NSString
        let size = ns.size(withAttributes: attrs)
        ns.draw(
            at: CGPoint(
                x: (pageRect.width - size.width) / 2,
                y: pageRect.height - 30
            ),
            withAttributes: attrs
        )
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
                String(localized: "🚨 隐患 / HAZARD", locale: AppLanguageManager.currentLocale),
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
        if let addr = note.locationAddress { metaLines.append(String(localized: "位置: \(addr)", locale: AppLanguageManager.currentLocale)) }
        if let weather = note.weatherSummary { metaLines.append(String(localized: "天气: \(weather)", locale: AppLanguageManager.currentLocale)) }
        if let tag = note.siteTag { metaLines.append(String(localized: "工地: \(tag)", locale: AppLanguageManager.currentLocale)) }
        if let assignee = note.assignedTo { metaLines.append(String(localized: "分派给: \(assignee)", locale: AppLanguageManager.currentLocale)) }
        if let clauseRef = note.contractClauseRef { metaLines.append(String(localized: "合同条款: \(clauseRef)", locale: AppLanguageManager.currentLocale)) }
        for line in metaLines {
            drawText(line, at: CGPoint(x: leftMargin, y: y), fontSize: 12, color: .darkGray)
            y += 18
        }

        // Deadline + 状态
        let dueStr = note.dueDate.formatted(date: .abbreviated, time: .omitted)
        let deadlineName = note.deadline.displayName
        let deadlineStr = String(localized: "到期: \(deadlineName) (\(dueStr))", locale: AppLanguageManager.currentLocale)
        let statusStr = note.isDone
            ? String(localized: "状态: ✓ 已完成", locale: AppLanguageManager.currentLocale)
            : String(localized: "状态: 待处理", locale: AppLanguageManager.currentLocale)
        drawText("\(deadlineStr)    \(statusStr)", at: CGPoint(x: leftMargin, y: y), fontSize: 12)
        y += 24

        // 分隔线
        drawLine(
            from: CGPoint(x: leftMargin, y: y),
            to: CGPoint(x: leftMargin + contentWidth, y: y)
        )
        y += 15

        // 内容
        drawText(String(localized: "内容", locale: AppLanguageManager.currentLocale), at: CGPoint(x: leftMargin, y: y), fontSize: 14, bold: true)
        y += 22

        let bodyText = note.transcription.isEmpty ? String(localized: "(无转写,仅录音)", locale: AppLanguageManager.currentLocale) : note.transcription
        let bodyHeight = drawWrappedText(
            bodyText,
            in: CGRect(x: leftMargin, y: y, width: contentWidth, height: 250),
            fontSize: 14
        )
        y += bodyHeight + 15

        // 平面图(若有)+ 图钉位置
        if let planName = note.floorPlanRef,
           let x = note.floorPlanX,
           let yNorm = note.floorPlanY,
           let plan = FloorPlansStorage.find(name: planName),
           let planURL = FloorPlansStorage.absoluteURL(forRelative: plan.imageRelativePath),
           let planImage = UIImage(contentsOfFile: planURL.path) {
            drawText(String(localized: "平面图位置: \(planName)", locale: AppLanguageManager.currentLocale),
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
            let photoCount = note.photoPaths.count
            drawText(String(localized: "照片 (\(photoCount) 张,最多显示 4)", locale: AppLanguageManager.currentLocale),
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
