//
//  InspectionReportPDFBuilder.swift
//  SiteNote
//
//  Engineer 模式专用 PDF 生成器。
//
//  数据架构(v1.3 重构后):
//    - 入参是 `InspectionReport`(聚合 Header + noteIDs + captionOverrides)
//      + `[Note]`(实际照片/图钉数据来源)。
//    - report.noteIDs 决定 PDF 里 Note 出现的顺序。每条 Note 的 photoPaths
//      **每张照片都展开成一个独立 grid cell**(多张照片 → 多格)。
//    - report.mainNoteID / mainCaption 字段在模型层保留(向后兼容),但在 PDF
//      渲染中已不再使用(封面主照片于 v1.x 移除)。
//    - 图钉缩略图:Note.floorPlanRef + floorPlanX/Y 三个字段都非空,在 caption
//      右侧渲染 48pt 圆形 mini floor plan + 红点。
//
//  参考 QDE Engineering 的 11 页 Site Visit Report 格式:
//    - 第 1 页(封面):公司 Logo + 标题 + Header 表 + 5 条 disclaimers + 签字栏
//      (注:主照片部分已在 v1.x 移除——封面纯文档化,所有照片走第 2+ 页网格)
//    - 第 2 页起:详细照片 2x2 网格(每页 4 cell),caption 在下方,
//      绑定 floor plan 的 cell 在 caption 右侧绘制 48pt 圆形缩略图 + 红点标位置。
//
//  入口:
//    `build(report:notes:)` 接收 InspectionReport 聚合 + 关联 Note 列表,
//    异步返回临时 PDF URL(供分享/邮件)。
//

import Foundation
import UIKit

enum InspectionReportPDFBuilder {

    enum BuildError: LocalizedError {
        case renderFailed(String)
        var errorDescription: String? {
            switch self {
            case .renderFailed(let s):
                return String(
                    localized: "巡检报告生成失败: \(s)",
                    locale: AppLanguageManager.currentLocale
                )
            }
        }
    }

    // MARK: - Public entry point

    /// 基于 InspectionReport 聚合 + 关联 Note 渲染 QDE 风格 SVR PDF。
    /// 返回的 URL 在 NSTemporaryDirectory 下,调用方负责分享后清理。
    @MainActor
    static func build(report: InspectionReport, notes: [Note]) async throws -> URL {
        try renderPDF(report: report, notes: notes)
    }

    // MARK: - Render

    @MainActor
    private static func renderPDF(report: InspectionReport, notes: [Note]) throws -> URL {
        // A4 595×842
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 40
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        // 文件名:SVR-{projectNo}-{date}-{reportNo}.pdf
        let projSlug = ASCIISlug.make(report.projectNo, fallback: "noproj")
        let dateSlug = yyyymmdd(report.reportDate)
        let reportSlug = ASCIISlug.make(report.reportNo, fallback: "SVR")
        let filename = "SVR-\(projSlug)-\(dateSlug)-\(reportSlug).pdf"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: outputURL)

        // ---- 按 report.noteIDs 顺序重排 [Note] ----
        let noteByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let orderedNotes = report.noteIDs.compactMap { noteByID[$0] }

        // 主照片已从封面移除(v1.x)。`report.mainNoteID` / `report.mainCaption`
        // 字段保留为数据兼容,但在 PDF 渲染中不再读取。

        let overrides = report.captionOverrides()

        do {
            try renderer.writePDF(to: outputURL) { ctx in
                // ---- 第 1 页:封面 ----
                var cursor = PDFCursor(pageRect: pageRect, margin: margin, context: ctx)
                cursor.beginPage()

                drawCoverHeader(cursor: &cursor, report: report)
                drawHeaderTable(cursor: &cursor, report: report)
                drawDisclaimers(cursor: &cursor, report: report)
                drawCoverSignature(cursor: &cursor, report: report)
                drawPageFooter(context: ctx, pageRect: pageRect, margin: margin, pageNumber: 1)

                // ---- 第 2 页起:每条 Note 独占连续页面 ----
                // Batch 规则(用户要求):
                //   - 有图纸的页面(首页且 Note 有 floorPlanRef):每页最多 2 张照片
                //     (图纸要占 ~365pt,描述+照片只剩半页,放 2 张 1x2 才不挤)
                //   - 无图纸的页面(Note 没图钉 / 续页):每页最多 4 张照片 2x2
                var pageNumber = 2
                for (idx, note) in orderedNotes.enumerated() {
                    let noteIndex = idx + 1
                    let rawCaption = overrides[note.id] ?? note.transcription
                    let caption = rawCaption.trimmingCharacters(in: .whitespacesAndNewlines)
                    let photos = note.photoPaths
                    let hasPin = (note.floorPlanRef ?? "").isEmpty == false
                        && note.floorPlanX != nil
                        && note.floorPlanY != nil

                    if photos.isEmpty {
                        cursor.beginPage()
                        drawNoteDetailPage(
                            cursor: &cursor,
                            noteIndex: noteIndex,
                            note: note,
                            caption: caption,
                            photos: [],
                            continuation: false
                        )
                        drawPageFooter(
                            context: ctx,
                            pageRect: pageRect,
                            margin: margin,
                            pageNumber: pageNumber
                        )
                        pageNumber += 1
                    } else {
                        var remaining = photos
                        var isFirst = true
                        while !remaining.isEmpty {
                            // 首页有图纸 → 2 张/页;首页无图纸 / 续页 → 4 张/页
                            let batchCap = (isFirst && hasPin) ? 2 : 4
                            let take = min(batchCap, remaining.count)
                            let batch = Array(remaining.prefix(take))
                            remaining = Array(remaining.dropFirst(take))

                            cursor.beginPage()
                            drawNoteDetailPage(
                                cursor: &cursor,
                                noteIndex: noteIndex,
                                note: note,
                                caption: caption,
                                photos: batch,
                                continuation: !isFirst
                            )
                            drawPageFooter(
                                context: ctx,
                                pageRect: pageRect,
                                margin: margin,
                                pageNumber: pageNumber
                            )
                            pageNumber += 1
                            isFirst = false
                        }
                    }
                }
            }
        } catch {
            throw BuildError.renderFailed(error.localizedDescription)
        }

        return outputURL
    }

    // MARK: - Cover: Logo + 公司 + 标题

    @MainActor
    private static func drawCoverHeader(cursor: inout PDFCursor, report: InspectionReport) {
        // Logo:右上,最大 60x60(UserDefaults 没设 → BrandingStorage 返回 nil,不画)
        if let logo = BrandingStorage.loadLogo() {
            let maxEdge: CGFloat = 60
            let scale = min(maxEdge / logo.size.width, maxEdge / logo.size.height, 1.0)
            let drawW = logo.size.width * scale
            let drawH = logo.size.height * scale
            let logoRect = CGRect(
                x: cursor.pageRect.width - cursor.margin - drawW,
                y: cursor.margin,
                width: drawW,
                height: drawH
            )
            logo.draw(in: logoRect)
        }

        // 公司名 + ABN(从 UserDefaults 读;两个都空就用 "SiteNote" 兜底当公司名)
        let rawCompanyName = (UserDefaults.standard.string(forKey: "settings.engineerCompanyName") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let abn = (UserDefaults.standard.string(forKey: "settings.engineerABN") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let companyName = rawCompanyName.isEmpty ? "SiteNote" : rawCompanyName

        cursor.drawText(
            companyName,
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: .black
        )
        if !abn.isEmpty {
            cursor.drawText(
                String(localized: "ABN: \(abn)", locale: AppLanguageManager.currentLocale),
                font: .systemFont(ofSize: 10),
                color: .darkGray
            )
        }
        cursor.skip(8)

        // 大标题(蓝色)
        let titleColor = UIColor(red: 0x1A / 255.0, green: 0x4F / 255.0, blue: 0xA0 / 255.0, alpha: 1)
        cursor.drawText(
            String(localized: "Site Visit Report / Site Instruction", locale: AppLanguageManager.currentLocale),
            font: .systemFont(ofSize: 24, weight: .semibold),
            color: titleColor
        )
        cursor.skip(12)
        cursor.drawDivider()
        cursor.skip(10)
    }

    // MARK: - Cover: Header 表(两列)

    @MainActor
    private static func drawHeaderTable(cursor: inout PDFCursor, report: InspectionReport) {
        let dateStr = isoYMD(report.reportDate)
        let leftRows: [(String, String)] = [
            (String(localized: "Project:", locale: AppLanguageManager.currentLocale), report.project),
            (String(localized: "Client:", locale: AppLanguageManager.currentLocale), report.client),
            (String(localized: "Location:", locale: AppLanguageManager.currentLocale), report.location),
            (String(localized: "Attn:", locale: AppLanguageManager.currentLocale), report.attn)
        ]
        let rightRows: [(String, String)] = [
            (String(localized: "Date:", locale: AppLanguageManager.currentLocale), dateStr),
            (String(localized: "Project No.:", locale: AppLanguageManager.currentLocale), report.projectNo),
            (String(localized: "Inspection:", locale: AppLanguageManager.currentLocale), report.inspectionType),
            (String(localized: "Report No.:", locale: AppLanguageManager.currentLocale), report.reportNo)
        ]

        let rowCount = max(leftRows.count, rightRows.count)
        let rowHeight: CGFloat = 18
        cursor.ensureRoom(CGFloat(rowCount) * rowHeight + 8)

        let labelColor = UIColor(red: 0x1A / 255.0, green: 0x4F / 255.0, blue: 0xA0 / 255.0, alpha: 1)
        let labelFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let valueFont = UIFont.systemFont(ofSize: 11)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont, .foregroundColor: labelColor
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont, .foregroundColor: UIColor.black
        ]

        let halfWidth = cursor.contentWidth / 2
        let leftX = cursor.margin
        let rightX = cursor.margin + halfWidth + 6

        for i in 0 ..< rowCount {
            let yLine = cursor.y
            if i < leftRows.count {
                let (lbl, val) = leftRows[i]
                let lblSize = (lbl as NSString).size(withAttributes: labelAttrs)
                (lbl as NSString).draw(at: CGPoint(x: leftX, y: yLine), withAttributes: labelAttrs)
                let valX = leftX + lblSize.width + 4
                let valRect = CGRect(
                    x: valX, y: yLine,
                    width: halfWidth - lblSize.width - 4 - 6,
                    height: rowHeight
                )
                (val as NSString).draw(in: valRect, withAttributes: valueAttrs)
            }
            if i < rightRows.count {
                let (lbl, val) = rightRows[i]
                let lblSize = (lbl as NSString).size(withAttributes: labelAttrs)
                (lbl as NSString).draw(at: CGPoint(x: rightX, y: yLine), withAttributes: labelAttrs)
                let valX = rightX + lblSize.width + 4
                let valRect = CGRect(
                    x: valX, y: yLine,
                    width: halfWidth - lblSize.width - 4 - 6,
                    height: rowHeight
                )
                (val as NSString).draw(in: valRect, withAttributes: valueAttrs)
            }
            cursor.y += rowHeight
        }
        cursor.skip(8)
    }

    // MARK: - Cover: Disclaimers

    @MainActor
    private static func drawDisclaimers(cursor: inout PDFCursor, report: InspectionReport) {
        let items: [String]
        if let custom = report.disclaimerText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            items = custom
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            items = defaultDisclaimers
        }
        guard !items.isEmpty else { return }

        cursor.drawText(
            String(localized: "DISCLAIMERS:", locale: AppLanguageManager.currentLocale),
            font: .systemFont(ofSize: 9.5, weight: .semibold),
            color: .darkGray
        )
        cursor.skip(2)

        for item in items {
            drawBulletLine(cursor: &cursor, text: item)
        }
        cursor.skip(8)
    }

    /// 单条 bullet:左缩进 + 圆点 + 自动换行。
    @MainActor
    private static func drawBulletLine(cursor: inout PDFCursor, text: String) {
        let bullet = "• "
        let font = UIFont.systemFont(ofSize: 8.5)
        let color = UIColor.darkGray
        let lineHeight: CGFloat = 11
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let bulletAttrs = attrs
        let bulletWidth = (bullet as NSString).size(withAttributes: bulletAttrs).width
        let textWidth = cursor.contentWidth - bulletWidth

        let ns = text as NSString
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight

        var textAttrs = attrs
        textAttrs[.paragraphStyle] = style

        let bounding = ns.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttrs,
            context: nil
        )
        let neededHeight = ceil(bounding.height)
        cursor.ensureRoom(neededHeight)

        (bullet as NSString).draw(
            at: CGPoint(x: cursor.margin, y: cursor.y),
            withAttributes: bulletAttrs
        )

        let textRect = CGRect(
            x: cursor.margin + bulletWidth,
            y: cursor.y,
            width: textWidth,
            height: neededHeight
        )
        ns.draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttrs,
            context: nil
        )
        cursor.y += neededHeight + 1
    }

    // MARK: - Cover: 签字栏

    @MainActor
    private static func drawCoverSignature(cursor: inout PDFCursor, report: InspectionReport) {
        cursor.ensureRoom(50)
        cursor.skip(8)
        cursor.drawDivider()
        cursor.skip(12)

        let labelFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let valueFont = UIFont.systemFont(ofSize: 11)

        let leftLabel = String(localized: "QDE Engineer:", locale: AppLanguageManager.currentLocale)
        let rightLabel = String(localized: "Site Rep:", locale: AppLanguageManager.currentLocale)
        let engineerVal = report.engineerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let siteRepVal = report.siteRepStatus.trimmingCharacters(in: .whitespacesAndNewlines)

        let ctx = cursor.context.cgContext
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont, .foregroundColor: UIColor.black
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont, .foregroundColor: UIColor.black
        ]

        let halfW = cursor.contentWidth / 2
        let leftLblSize = (leftLabel as NSString).size(withAttributes: labelAttrs)
        let rightLblSize = (rightLabel as NSString).size(withAttributes: labelAttrs)

        let yLabel = cursor.y
        (leftLabel as NSString).draw(at: CGPoint(x: cursor.margin, y: yLabel), withAttributes: labelAttrs)
        (rightLabel as NSString).draw(
            at: CGPoint(x: cursor.margin + halfW + 10, y: yLabel),
            withAttributes: labelAttrs
        )

        let leftValX = cursor.margin + leftLblSize.width + 6
        let leftLineEnd = cursor.margin + halfW - 10
        let rightValX = cursor.margin + halfW + 10 + rightLblSize.width + 6
        let rightLineEnd = cursor.margin + cursor.contentWidth

        let leftValRect = CGRect(
            x: leftValX, y: yLabel,
            width: max(leftLineEnd - leftValX, 0),
            height: 16
        )
        let rightValRect = CGRect(
            x: rightValX, y: yLabel,
            width: max(rightLineEnd - rightValX, 0),
            height: 16
        )
        (engineerVal as NSString).draw(in: leftValRect, withAttributes: valueAttrs)
        (siteRepVal as NSString).draw(in: rightValRect, withAttributes: valueAttrs)

        let lineY = yLabel + 16
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.darkGray.cgColor)
        ctx.setLineWidth(0.6)
        ctx.move(to: CGPoint(x: leftValX, y: lineY))
        ctx.addLine(to: CGPoint(x: leftLineEnd, y: lineY))
        ctx.move(to: CGPoint(x: rightValX, y: lineY))
        ctx.addLine(to: CGPoint(x: rightLineEnd, y: lineY))
        ctx.strokePath()
        ctx.restoreGState()

        cursor.y = lineY + 6
    }

    // MARK: - 第 2+ 页:每条 Note 一页(多照片可续页)
    //
    // 线性布局(用户选定方案 A):
    //   Header(#N + 时间 + 工地) → 分割线
    //   → A3 图纸(满宽,√2:1 比例,固定大尺寸)
    //   → 描述文字
    //   → 照片:1 张 hero / 2 张 1x2 / 3-4 张 2x2,占满剩余空间
    // 续页:Header(cont.) → 2x2 网格(不重复图纸描述)
    @MainActor
    private static func drawNoteDetailPage(
        cursor: inout PDFCursor,
        noteIndex: Int,
        note: Note,
        caption: String,
        photos: [String],
        continuation: Bool
    ) {
        drawNotePageHeader(
            cursor: &cursor,
            noteIndex: noteIndex,
            note: note,
            continuation: continuation
        )

        if continuation {
            drawPhotosForCount(cursor: &cursor, photos: photos)
            return
        }

        // 1. 大 A3 图纸(顶部,满宽,固定 √2:1 比例)
        drawFloorPlanFullWidth(cursor: &cursor, note: note)

        // 2. 描述
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            cursor.drawWrappedText(trimmed, font: .systemFont(ofSize: 11), lineHeight: 14)
            cursor.skip(10)
        }

        // 3. 照片占满剩余区域
        if !photos.isEmpty {
            drawPhotosForCount(cursor: &cursor, photos: photos)
        }
    }

    /// 顶部满宽 A3 图纸。宽 = contentWidth,高 = 宽 / √2 ≈ 0.707×宽。
    @MainActor
    private static func drawFloorPlanFullWidth(cursor: inout PDFCursor, note: Note) {
        let hasPin = (note.floorPlanRef ?? "").isEmpty == false
            && note.floorPlanX != nil
            && note.floorPlanY != nil
        guard hasPin else { return }

        let aspect: CGFloat = 420.0 / 297.0   // A3 横向
        let planW = cursor.contentWidth
        let planH = planW / aspect

        let planRect = CGRect(
            x: cursor.margin,
            y: cursor.y,
            width: planW,
            height: planH
        )
        drawFloorPlanPin(
            planID: note.floorPlanID,
            planName: note.floorPlanRef ?? "",
            normalizedX: note.floorPlanX ?? 0.5,
            normalizedY: note.floorPlanY ?? 0.5,
            in: planRect,
            siteTag: note.siteTag
        )
        cursor.y += planH + 12
    }

    /// 照片区:根据张数自适应。1=hero、2=1x2、3-4=2x2;占满剩余高度。
    @MainActor
    private static func drawPhotosForCount(cursor: inout PDFCursor, photos: [String]) {
        let availableH = cursor.pageRect.height - cursor.margin - cursor.y - 30
        guard availableH > 60 else { return }

        switch photos.count {
        case 0:
            return
        case 1:
            let rect = CGRect(
                x: cursor.margin,
                y: cursor.y,
                width: cursor.contentWidth,
                height: availableH
            )
            drawSinglePhoto(in: rect, path: photos[0])
        case 2:
            let gap: CGFloat = 8
            let cellW = (cursor.contentWidth - gap) / 2
            for (idx, path) in photos.enumerated() {
                let rect = CGRect(
                    x: cursor.margin + CGFloat(idx) * (cellW + gap),
                    y: cursor.y,
                    width: cellW,
                    height: availableH
                )
                drawSinglePhoto(in: rect, path: path)
            }
        default:
            // 3-4 张(>4 已经被外层 batch 切到 4)
            drawPhotos2x2Grid(cursor: &cursor, photos: photos)
        }
    }

    /// 页面顶部 header:左侧 #N 大字 + 右侧时间戳 + 下方分割线。
    /// 续页:#N (cont.) 紧凑 16pt,无时间戳。
    @MainActor
    private static func drawNotePageHeader(
        cursor: inout PDFCursor,
        noteIndex: Int,
        note: Note,
        continuation: Bool
    ) {
        let titleBlue = UIColor(red: 0x1A / 255.0, green: 0x4F / 255.0, blue: 0xA0 / 255.0, alpha: 1)
        let indexStr = continuation
            ? "#\(noteIndex) (cont.)"
            : "#\(noteIndex)"
        let indexFont = UIFont.monospacedDigitSystemFont(
            ofSize: continuation ? 16 : 26,
            weight: .bold
        )
        let indexAttrs: [NSAttributedString.Key: Any] = [
            .font: indexFont,
            .foregroundColor: titleBlue
        ]
        let indexSize = (indexStr as NSString).size(withAttributes: indexAttrs)
        (indexStr as NSString).draw(
            at: CGPoint(x: cursor.margin, y: cursor.y),
            withAttributes: indexAttrs
        )

        if !continuation {
            // 右上:时间戳 + 工地 tag
            let timeStr = headerRightText(for: note)
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.darkGray
            ]
            let timeSize = (timeStr as NSString).size(withAttributes: timeAttrs)
            (timeStr as NSString).draw(
                at: CGPoint(
                    x: cursor.margin + cursor.contentWidth - timeSize.width,
                    y: cursor.y + (indexSize.height - timeSize.height) - 2
                ),
                withAttributes: timeAttrs
            )
        }

        cursor.y += indexSize.height + (continuation ? 4 : 6)
        cursor.drawDivider()
        cursor.skip(8)
    }

    /// "10:42 · 工地 20"。
    private static func headerRightText(for note: Note) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let timeStr = f.string(from: note.createdAt)
        if let tag = note.siteTag, !tag.isEmpty {
            return "\(timeStr) · \(tag)"
        }
        return timeStr
    }

    // MARK: - Body helpers

    /// 2x2 网格,4 个 cell 占满剩余空间;少于 4 张时多余 cell 留空(对齐美观)。
    /// 也供续页直接调用(续页是纯 grid)。
    @MainActor
    private static func drawPhotos2x2Grid(cursor: inout PDFCursor, photos: [String]) {
        let gap: CGFloat = 8
        let availableW = cursor.contentWidth
        let cellW = (availableW - gap) / 2
        let availableH = cursor.pageRect.height - cursor.margin - cursor.y - 30
        let cellH = (availableH - gap) / 2

        let positions: [(col: Int, row: Int)] = [(0, 0), (1, 0), (0, 1), (1, 1)]
        for (idx, path) in photos.prefix(4).enumerated() {
            let pos = positions[idx]
            let rect = CGRect(
                x: cursor.margin + CGFloat(pos.col) * (cellW + gap),
                y: cursor.y + CGFloat(pos.row) * (cellH + gap),
                width: cellW,
                height: cellH
            )
            drawSinglePhoto(in: rect, path: path)
        }
    }

    /// 单张照片渲染:aspect-fit,无灰底框(用户要求)。找不到文件时画占位提示。
    private static func drawSinglePhoto(in rect: CGRect, path: String) {
        let loaded: UIImage? = {
            guard !path.isEmpty,
                  let url = PhotoStorage.absoluteURL(forRelative: path) else {
                return nil
            }
            return UIImage(contentsOfFile: url.path)
        }()
        if let image = loaded {
            let fit = fitRect(imageSize: image.size, in: rect)
            image.draw(in: fit)
        } else {
            drawMissingPhotoPlaceholder(in: rect)
        }
    }

    /// 图片缺失占位:灰底 + 居中"图片缺失"提示。
    private static func drawMissingPhotoPlaceholder(in rect: CGRect) {
        UIColor(white: 0.92, alpha: 1).setFill()
        UIBezierPath(rect: rect).fill()

        UIColor(white: 0.7, alpha: 1).setStroke()
        let stroke = UIBezierPath(rect: rect.insetBy(dx: 0.3, dy: 0.3))
        stroke.lineWidth = 0.6
        stroke.setLineDash([3, 3], count: 2, phase: 0)
        stroke.stroke()

        let label = String(localized: "图片缺失", locale: AppLanguageManager.currentLocale)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: UIColor.darkGray
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let origin = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        (label as NSString).draw(at: origin, withAttributes: attrs)
    }

    /// 矩形 mini floor plan 缩略图,大尺寸 aspect-fit + 红色十字 + 双环高亮。
    /// 之前是 48pt 圆形 + 3pt 红点,用户反馈"图钉看不出位置";现在改成 110pt 矩形,
    /// aspect-fit 完整显示图纸(不裁切),并以 12pt 红色十字 + 16pt/24pt 双圈高亮标记位置。
    /// **Codex#8**:优先按 planID(UUID)查找,改名后不丢图;无 ID 时 fallback name。
    private static func drawFloorPlanPin(
        planID: UUID?,
        planName: String,
        normalizedX: Double,
        normalizedY: Double,
        in rect: CGRect,
        siteTag: String?
    ) {
        guard let plan = FloorPlansStorage.resolve(id: planID, name: planName, siteTag: siteTag),
              let url = FloorPlansStorage.absoluteURL(forRelative: plan.imageRelativePath),
              let image = UIImage(contentsOfFile: url.path) else {
            return
        }

        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()

        // 白底 + 描边(矩形,不再 oval-clip)
        UIColor.white.setFill()
        UIBezierPath(rect: rect).fill()

        // aspect-fit:整张图纸都能看见,可能在四周留白(便于看墙体/网格)
        let fitRect = fitRect(imageSize: image.size, in: rect)
        ctx.saveGState()
        UIBezierPath(rect: rect).addClip()
        image.draw(in: fitRect)
        ctx.restoreGState()

        // 标记:外环 24pt(半透明红)+ 内环 16pt(实线红)+ 中心十字 12pt
        let cx = fitRect.minX + fitRect.width * CGFloat(normalizedX)
        let cy = fitRect.minY + fitRect.height * CGFloat(normalizedY)
        let outerR: CGFloat = 12
        let innerR: CGFloat = 8
        let crossLen: CGFloat = 12

        UIColor.systemRed.withAlphaComponent(0.25).setFill()
        UIBezierPath(ovalIn: CGRect(
            x: cx - outerR, y: cy - outerR,
            width: outerR * 2, height: outerR * 2
        )).fill()

        UIColor.systemRed.setStroke()
        let innerCircle = UIBezierPath(ovalIn: CGRect(
            x: cx - innerR, y: cy - innerR,
            width: innerR * 2, height: innerR * 2
        ))
        innerCircle.lineWidth = 1.5
        innerCircle.stroke()

        let cross = UIBezierPath()
        cross.move(to: CGPoint(x: cx - crossLen, y: cy))
        cross.addLine(to: CGPoint(x: cx + crossLen, y: cy))
        cross.move(to: CGPoint(x: cx, y: cy - crossLen))
        cross.addLine(to: CGPoint(x: cx, y: cy + crossLen))
        cross.lineWidth = 1.5
        cross.stroke()

        ctx.restoreGState()

        // 外描边
        UIColor.darkGray.setStroke()
        let border = UIBezierPath(rect: rect)
        border.lineWidth = 0.6
        border.stroke()
    }

    // MARK: - 页脚

    private static func drawPageFooter(
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        margin: CGFloat,
        pageNumber: Int
    ) {
        let ts = DateFormatter()
        ts.dateFormat = "yyyy-MM-dd HH:mm"
        let nowStr = ts.string(from: Date())
        let footer = String(
            localized: "由 SiteNote 生成于 \(nowStr)",
            locale: AppLanguageManager.currentLocale
        )
        let pageLabel = String(
            localized: "Page \(pageNumber)",
            locale: AppLanguageManager.currentLocale
        )
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.lightGray
        ]
        let footerY = pageRect.height - margin + 8

        // 居中"生成于"
        let centerStyle = NSMutableParagraphStyle()
        centerStyle.alignment = .center
        var centerAttrs = attrs
        centerAttrs[.paragraphStyle] = centerStyle
        let footerRect = CGRect(
            x: margin,
            y: footerY,
            width: pageRect.width - margin * 2,
            height: 14
        )
        (footer as NSString).draw(in: footerRect, withAttributes: centerAttrs)

        // 右下角页码(只显示当前页号;两 pass 渲染太重)
        let pageSize = (pageLabel as NSString).size(withAttributes: attrs)
        let pageOrigin = CGPoint(
            x: pageRect.width - margin - pageSize.width,
            y: footerY
        )
        (pageLabel as NSString).draw(at: pageOrigin, withAttributes: attrs)
    }

    // MARK: - 静态文案

    /// 默认 5 条 disclaimers(英文原文,沿用 QDE 模板)。
    /// 注:DisclaimerStorage 也有一份;这里保留一个独立 fallback,
    /// 避免 Storage 异常时封面变空。
    private static let defaultDisclaimers: [String] = [
        "This inspection does not include the foundation material and ground stability including: excavations, cuttings, batters and stabilizing elements such as soil nails, rock bolts and ground anchors etc. It is the builder's responsibility to have the Geotechnical engineer inspect and approve prior to placing concrete.",
        "This inspection does not include the formwork, formwork support and back-propping. It has not been inspected and should be separately certified by an experienced formwork engineer.",
        "This inspection does not include epoxy grouted bars, chemical or expansion anchors. The correct installation of these items is the responsibility of the builder.",
        "Reinforcement inspections are subject to final clean out of formwork or excavation and maintaining specified cover during placement of concrete.",
        "The builder must rectify the defects listed in this report as a contractual, Work Health and Safety, building certification requirement."
    ]

    // MARK: - Utilities

    private static func yyyymmdd(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: d)
    }

    private static func isoYMD(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_AU")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: d)
    }

    /// 截断到 max 个字符(按 Character 而非 UTF-16 单元,中英都安全),超长加 "..."。
    private static func truncate(_ raw: String, max maxChars: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxChars { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<end]) + "..."
    }

    /// aspect fit 居中矩形(整张图都在 frame 内,可能留白)。
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

    /// aspect fill 居中矩形(图撑满 frame,可能裁切)。
    private static func aspectFillRect(imageSize: CGSize, in frame: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return frame }
        let imgAspect = imageSize.width / imageSize.height
        let frameAspect = frame.width / frame.height
        if imgAspect > frameAspect {
            // 图更宽 → 按高度 fit,宽度溢出裁切
            let w = frame.height * imgAspect
            return CGRect(
                x: frame.minX - (w - frame.width) / 2,
                y: frame.minY,
                width: w,
                height: frame.height
            )
        } else {
            let h = frame.width / imgAspect
            return CGRect(
                x: frame.minX,
                y: frame.minY - (h - frame.height) / 2,
                width: frame.width,
                height: h
            )
        }
    }
}

// MARK: - PDF cursor(分页画笔,与原版同款,保留以兼容内部 helper)

/// 内部工具:追踪 y 坐标、自动换页、绘制文本/分割线等。
/// 不复用 SiteDiaryPDFBuilder 的私有 PDFCursor:Swift 私有类型作用域受限,
/// 各 builder 独立持有自己的 cursor 更直接,改 layout 不会牵动其他模块。
private struct PDFCursor {
    let pageRect: CGRect
    let margin: CGFloat
    let context: UIGraphicsPDFRendererContext

    var y: CGFloat = 0
    var contentWidth: CGFloat { pageRect.width - margin * 2 }
    var bottomLimit: CGFloat { pageRect.height - margin }

    init(pageRect: CGRect, margin: CGFloat, context: UIGraphicsPDFRendererContext) {
        self.pageRect = pageRect
        self.margin = margin
        self.context = context
        self.y = margin
    }

    mutating func beginPage() {
        context.beginPage()
        y = margin
    }

    mutating func skip(_ amount: CGFloat) {
        y += amount
        if y > bottomLimit { beginPage() }
    }

    mutating func ensureRoom(_ needed: CGFloat) {
        if y + needed > bottomLimit { beginPage() }
    }

    mutating func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor = .black,
        alignment: NSTextAlignment = .left
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        let height = ceil(font.lineHeight)
        ensureRoom(height)
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: height)
        (text as NSString).draw(in: rect, withAttributes: attrs)
        y += height
    }

    mutating func drawWrappedText(_ text: String, font: UIFont, lineHeight: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        let ns = text as NSString
        let bounding = ns.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        let neededHeight = ceil(bounding.height)

        if y + neededHeight > bottomLimit {
            beginPage()
        }
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: neededHeight)
        ns.draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        y += neededHeight
    }

    mutating func drawDivider() {
        let ctx = context.cgContext
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.lightGray.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: margin, y: y))
        ctx.addLine(to: CGPoint(x: margin + contentWidth, y: y))
        ctx.strokePath()
        ctx.restoreGState()
        y += 1
    }
}
