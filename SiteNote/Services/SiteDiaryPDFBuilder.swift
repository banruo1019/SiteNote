//
//  SiteDiaryPDFBuilder.swift
//  SiteNote
//
//  Daily Site Diary PDF 生成器。结构化的一天工地日志,交业主/监理/法律存档。
//
//  设计原则:
//  - **表格 + 时间线来自 LogEntry / Note 硬数据**,不让 AI 编造。这是法律证据层,必须可追溯。
//  - AI narrative 作为**顶部摘要**,可选。AI 失败 narrative 留空,表格照出。
//  - 单文件自包含,不依赖 PDFExportService 的封面/分页逻辑——两者服务不同场景。
//

import Foundation
import UIKit

enum SiteDiaryPDFBuilder {

    enum DiaryError: LocalizedError {
        case renderFailed(String)
        var errorDescription: String? {
            switch self {
            case .renderFailed(let s): return String(localized: "Site Diary 生成失败: \(s)", locale: AppLanguageManager.currentLocale)
            }
        }
    }

    /// 生成 Site Diary PDF,返回临时目录 URL。
    /// `entries` 和 `notes` 应是已经过滤好(当日 + 指定工地)的集合。
    @MainActor
    static func build(
        date: Date,
        siteTag: String?,
        entries: [LogEntry],
        notes: [Note],
        weatherSummary: String?
    ) async throws -> URL {
        // AI narrative 异步生成(best-effort,失败不阻断 PDF)。
        var narrative: String? = nil
        if AIService.isLanguageModelAvailable {
            narrative = try? await NarrativeService.generateDailyNarrative(
                notes: notes.sorted { $0.createdAt < $1.createdAt },
                date: date
            )
        }

        // 渲染 PDF(不在 await 后面的 Task 里,避免 UIGraphicsPDFRenderer 跨线程)。
        return try renderPDF(
            date: date,
            siteTag: siteTag,
            entries: entries,
            notes: notes,
            weatherSummary: weatherSummary,
            narrative: narrative
        )
    }

    // MARK: - Render

    @MainActor
    private static func renderPDF(
        date: Date,
        siteTag: String?,
        entries: [LogEntry],
        notes: [Note],
        weatherSummary: String?,
        narrative: String?
    ) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 42
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        // ASCII slug:中文 siteTag 在 Windows / 邮件客户端会乱码,统一 ASCII (E2.11)。
        let siteSlug = ASCIISlug.make(siteTag, fallback: "all")
        let dateSlug = yyyymmdd(date)
        let filename = "SiteDiary-\(siteSlug)-\(dateSlug).pdf"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: outputURL)

        let persons = entries.filter { $0.kind == .person }
        let plants = entries.filter { $0.kind == .plant }
        let others = entries.filter {
            $0.kind == .delivery || $0.kind == .visitor || $0.kind == .event
        }

        do {
            try renderer.writePDF(to: outputURL) { ctx in
                var cursor = PDFCursor(pageRect: pageRect, margin: margin, context: ctx)
                cursor.beginPage()

                // 公司 Logo(可选)— 画在首页左上角,不挤压 header 文本。
                // 顶部内容整体右移,留出 logo 区域。
                drawCompanyLogo(cursor: &cursor)

                drawHeader(
                    cursor: &cursor,
                    date: date,
                    siteTag: siteTag,
                    weather: weatherSummary,
                    stats: Stats(
                        headcount: personHeadcount(persons),
                        plantOpen: plants.filter { $0.isOpenPlantSession }.count,
                        plantClosed: plants.filter { !$0.isOpenPlantSession && $0.endAt != $0.startAt }.count,
                        noteCount: notes.count
                    )
                )

                if let narrative, !narrative.isEmpty {
                    drawNarrative(cursor: &cursor, text: narrative)
                }

                if !persons.isEmpty {
                    drawPersonTable(cursor: &cursor, entries: persons)
                }

                if !plants.isEmpty {
                    drawPlantTable(cursor: &cursor, entries: plants)
                }

                if !others.isEmpty {
                    drawOtherList(cursor: &cursor, entries: others)
                }

                if !notes.isEmpty {
                    drawNoteTimeline(cursor: &cursor, notes: notes)
                }

                drawFooter(cursor: &cursor)
            }
        } catch {
            throw DiaryError.renderFailed(error.localizedDescription)
        }

        return outputURL
    }

    // MARK: - Logo

    /// 画首页左上角的公司 Logo(用户在「设置 → 报告与导出」上传)。
    /// 没设 logo 直接 no-op,header 照常画。设了 logo,按比例缩到 80×60 内,
    /// cursor.y 推到 logo 底部,确保后续 header 文本不与 logo 重叠。
    private static func drawCompanyLogo(cursor: inout PDFCursor) {
        guard BrandingStorage.hasLogo, let logo = BrandingStorage.loadLogo() else { return }

        let maxW: CGFloat = 80
        let maxH: CGFloat = 60
        let imgSize = logo.size
        guard imgSize.width > 0, imgSize.height > 0 else { return }

        // 等比缩放
        let scale = min(maxW / imgSize.width, maxH / imgSize.height, 1.0)
        let drawW = imgSize.width * scale
        let drawH = imgSize.height * scale

        // 画在 (margin, margin) 处。cursor 当前 y 也是 margin,所以画完后把 y 推到 logo 底部 + 间距。
        let originX = cursor.margin
        let originY = cursor.margin
        let rect = CGRect(x: originX, y: originY, width: drawW, height: drawH)
        logo.draw(in: rect)

        // 把 cursor 下推,避免 header 第一行字盖在 logo 上。
        let bottom = originY + drawH + 8
        if bottom > cursor.y {
            cursor.y = bottom
        }
    }

    // MARK: - Header

    private static func drawHeader(
        cursor: inout PDFCursor,
        date: Date,
        siteTag: String?,
        weather: String?,
        stats: Stats
    ) {
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateStyle = .full

        cursor.drawText(String(localized: "Daily Site Diary · 工地日志", locale: AppLanguageManager.currentLocale), font: .systemFont(ofSize: 11, weight: .medium), color: .gray)
        cursor.skip(6)
        cursor.drawText(df.string(from: date), font: .systemFont(ofSize: 22, weight: .semibold))
        cursor.skip(6)

        var metaParts: [String] = []
        if let s = siteTag, !s.isEmpty {
            metaParts.append(String(localized: "工地:\(s)", locale: AppLanguageManager.currentLocale))
        } else {
            metaParts.append(String(localized: "工地:全部", locale: AppLanguageManager.currentLocale))
        }
        if let w = weather, !w.isEmpty {
            metaParts.append(String(localized: "天气:\(w)", locale: AppLanguageManager.currentLocale))
        }
        cursor.drawText(metaParts.joined(separator: " · "), font: .systemFont(ofSize: 11), color: .darkGray)

        cursor.skip(10)
        cursor.drawDivider()
        cursor.skip(8)

        // 摘要行
        let plantTotal = stats.plantClosed + stats.plantOpen
        let summaryLine = String(localized: "到场合计 \(stats.headcount) 人 · 机械 \(plantTotal) 条(未结束 \(stats.plantOpen)) · 原始速记 \(stats.noteCount) 条", locale: AppLanguageManager.currentLocale)
        cursor.drawText(summaryLine, font: .systemFont(ofSize: 11, weight: .medium), color: .darkGray)
        cursor.skip(14)
    }

    private static func drawNarrative(cursor: inout PDFCursor, text: String) {
        cursor.drawSectionHeader(String(localized: "AI 生成 · 日志叙述", locale: AppLanguageManager.currentLocale))
        cursor.skip(4)
        cursor.drawWrappedText(text, font: .systemFont(ofSize: 11), lineHeight: 15)
        cursor.skip(12)
    }

    // MARK: - Person table

    private static func drawPersonTable(cursor: inout PDFCursor, entries: [LogEntry]) {
        cursor.drawSectionHeader(String(localized: "人员到场", locale: AppLanguageManager.currentLocale))
        cursor.skip(4)

        // 列宽: 工种 | 数量 | 时间 | 备注(剩余)
        // 英文环境下"Trade / Crew" "Quantity" "Time" 比中文宽,需要更宽的非备注列(E2.12)。
        let cols: [CGFloat] = isEnglishLocale
            ? [170, 70, 90]
            : [180, 60, 70]
        let headers = [
            String(localized: "工种 / 班组", locale: AppLanguageManager.currentLocale),
            String(localized: "数量", locale: AppLanguageManager.currentLocale),
            String(localized: "时间", locale: AppLanguageManager.currentLocale),
            String(localized: "备注", locale: AppLanguageManager.currentLocale)
        ]
        cursor.drawTableRow(values: headers, widths: cols, isHeader: true)

        for e in entries {
            let quantity: String
            if e.isAbsent { quantity = String(localized: "缺席", locale: AppLanguageManager.currentLocale) }
            else if let q = e.quantity, q > 0 { quantity = "×\(q)" }
            else { quantity = "—" }

            cursor.drawTableRow(
                values: [
                    e.subject,
                    quantity,
                    e.startAtExplicit ? hhmm(e.startAt) : "—",
                    e.note ?? ""
                ],
                widths: cols,
                isHeader: false
            )
        }
        cursor.skip(10)
    }

    // MARK: - Plant table

    private static func drawPlantTable(cursor: inout PDFCursor, entries: [LogEntry]) {
        cursor.drawSectionHeader(String(localized: "机械进出场", locale: AppLanguageManager.currentLocale))
        cursor.skip(4)

        // 列宽: 设备 | 开始 | 结束 | 时长 | 备注(剩余)
        // 英文 "Plant / Equipment" "Start" "End" "Duration" 比中文宽,且 Open / Orphan
        // 这些状态文本要塞进时长列(E2.12)。
        let cols: [CGFloat] = isEnglishLocale
            ? [150, 70, 70, 80]
            : [160, 65, 65, 60]
        let headers = [
            String(localized: "设备", locale: AppLanguageManager.currentLocale),
            String(localized: "开始", locale: AppLanguageManager.currentLocale),
            String(localized: "结束", locale: AppLanguageManager.currentLocale),
            String(localized: "时长", locale: AppLanguageManager.currentLocale),
            String(localized: "备注", locale: AppLanguageManager.currentLocale)
        ]
        cursor.drawTableRow(values: headers, widths: cols, isHeader: true)

        for e in entries {
            let endStr: String
            let durStr: String
            var noteStr = e.note ?? ""

            if e.isOpenPlantSession {
                endStr = "—"
                durStr = String(localized: "开启中", locale: AppLanguageManager.currentLocale)
                if noteStr.isEmpty { noteStr = String(localized: "未结束,需关闭", locale: AppLanguageManager.currentLocale) }
            } else if e.startAt == e.endAt {
                endStr = "—"
                durStr = String(localized: "孤儿", locale: AppLanguageManager.currentLocale)
            } else if let end = e.endAt {
                endStr = hhmm(end)
                let totalMin = Int(end.timeIntervalSince(e.startAt) / 60)
                let h = totalMin / 60, m = totalMin % 60
                durStr = h > 0 ? "\(h)h \(m)m" : "\(m)m"
            } else {
                endStr = "—"
                durStr = "—"
            }

            let startStr = e.startAtExplicit ? hhmm(e.startAt) : "—"
            cursor.drawTableRow(
                values: [e.subject, startStr, endStr, durStr, noteStr],
                widths: cols,
                isHeader: false
            )
        }
        cursor.skip(10)
    }

    // MARK: - Delivery / visitor / event

    private static func drawOtherList(cursor: inout PDFCursor, entries: [LogEntry]) {
        cursor.drawSectionHeader(String(localized: "送达 / 访客 / 事件", locale: AppLanguageManager.currentLocale))
        cursor.skip(4)

        // 列宽: 类型(60) | 时间(65) | 条目(剩余)
        let cols: [CGFloat] = [60, 65]
        let headers = [
            String(localized: "类型", locale: AppLanguageManager.currentLocale),
            String(localized: "时间", locale: AppLanguageManager.currentLocale),
            String(localized: "内容", locale: AppLanguageManager.currentLocale)
        ]
        cursor.drawTableRow(values: headers, widths: cols, isHeader: true)

        for e in entries {
            let kindLabel = e.kind.displayName
            let content: String
            if let n = e.note, !n.isEmpty {
                content = "\(e.subject) · \(n)"
            } else {
                content = e.subject
            }
            cursor.drawTableRow(
                values: [
                    kindLabel,
                    e.startAtExplicit ? hhmm(e.startAt) : "—",
                    content
                ],
                widths: cols,
                isHeader: false
            )
        }
        cursor.skip(10)
    }

    // MARK: - Note timeline

    private static func drawNoteTimeline(cursor: inout PDFCursor, notes: [Note]) {
        cursor.drawSectionHeader(String(localized: "原始速记(按时间)", locale: AppLanguageManager.currentLocale))
        cursor.skip(4)

        for note in notes.sorted(by: { $0.createdAt < $1.createdAt }) {
            let time = hhmm(note.createdAt)
            var prefix = "[\(time)]"
            if note.isHazard { prefix += " 🚨" }
            let body = note.transcription.isEmpty ? String(localized: "(仅录音/照片)", locale: AppLanguageManager.currentLocale) : note.transcription
            cursor.drawWrappedText("\(prefix) \(body)", font: .systemFont(ofSize: 10.5), lineHeight: 14)
            cursor.skip(6)
        }
    }

    private static func drawFooter(cursor: inout PDFCursor) {
        // 签字栏:Site Manager / Foreman 各一行 + 见证。Site Diary 是法律证据级文档。
        drawSignatureFooter(cursor: &cursor)

        cursor.skip(14)
        cursor.drawDivider()
        cursor.skip(6)
        let ts = DateFormatter()
        ts.dateFormat = "yyyy-MM-dd HH:mm"
        let nowStr = ts.string(from: Date())
        cursor.drawText(String(localized: "由 SiteNote 生成于 \(nowStr)", locale: AppLanguageManager.currentLocale),
                        font: .systemFont(ofSize: 9), color: .lightGray)
    }

    @MainActor
    private static func drawSignatureFooter(cursor: inout PDFCursor) {
        cursor.ensureRoom(140)
        cursor.skip(20)
        cursor.drawDivider()
        cursor.skip(20)

        drawSignatureRow(
            cursor: &cursor,
            leftLabel: String(localized: "现场负责人签字:", locale: AppLanguageManager.currentLocale),
            rightLabel: String(localized: "日期:", locale: AppLanguageManager.currentLocale)
        )
        cursor.y += 32
        drawSignatureRow(
            cursor: &cursor,
            leftLabel: String(localized: "见证人签字:", locale: AppLanguageManager.currentLocale),
            rightLabel: String(localized: "日期:", locale: AppLanguageManager.currentLocale)
        )
        cursor.y += 30
    }

    /// 通用两栏签字行:左/右 label + 下划线,下划线起点用实际 label 宽度计算。
    @MainActor
    private static func drawSignatureRow(
        cursor: inout PDFCursor,
        leftLabel: String,
        rightLabel: String
    ) {
        let ctx = cursor.context.cgContext
        let lineY = cursor.y + 16
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor.black
        ]
        let leftWidth = (leftLabel as NSString).size(withAttributes: labelAttrs).width
        let rightWidth = (rightLabel as NSString).size(withAttributes: labelAttrs).width
        let gap: CGFloat = 6

        let leftLineStart = cursor.margin + leftWidth + gap
        let leftLineEnd = cursor.margin + cursor.contentWidth * 0.5 - 20
        let rightLabelX = cursor.margin + cursor.contentWidth * 0.5 + 20
        let rightLineStart = rightLabelX + rightWidth + gap
        let rightLineEnd = cursor.margin + cursor.contentWidth

        (leftLabel as NSString).draw(at: CGPoint(x: cursor.margin, y: cursor.y), withAttributes: labelAttrs)
        (rightLabel as NSString).draw(at: CGPoint(x: rightLabelX, y: cursor.y), withAttributes: labelAttrs)

        ctx.saveGState()
        ctx.setStrokeColor(UIColor.darkGray.cgColor)
        ctx.setLineWidth(0.6)
        ctx.move(to: CGPoint(x: leftLineStart, y: lineY))
        ctx.addLine(to: CGPoint(x: leftLineEnd, y: lineY))
        ctx.move(to: CGPoint(x: rightLineStart, y: lineY))
        ctx.addLine(to: CGPoint(x: rightLineEnd, y: lineY))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Utilities

    /// 到场总人数。quantity=nil 按 1 人算(和 LogTabView 台账模式口径一致)。
    private static func personHeadcount(_ persons: [LogEntry]) -> Int {
        persons
            .filter { !$0.isAbsent }
            .map { $0.quantity ?? 1 }
            .reduce(0, +)
    }

    /// 当前 App 语言是否英文。表格列宽要给英文标题留出空间(E2.12)。
    /// 用 AppLanguageManager.locale.identifier 前缀判断,跟随系统时也能拿到 "en" / "zh"。
    private static var isEnglishLocale: Bool {
        AppLanguageManager.currentLocale.identifier.lowercased().hasPrefix("en")
    }

    private static func hhmm(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private static func yyyymmdd(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: d)
    }

    private struct Stats {
        let headcount: Int
        let plantOpen: Int
        let plantClosed: Int
        let noteCount: Int
    }
}

// MARK: - PDF cursor(简易分页画笔)

/// 内部工具:追踪当前 y 坐标、自动换页、绘制文本/表格/分割线。
/// 不抽到 PDFExportService 共用,是因为 Site Diary 的 layout 比巡检日志稀疏得多,
/// 封装在一起反而会让两边都复杂。
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

    mutating func drawSectionHeader(_ text: String) {
        skip(4)
        drawText(text.uppercased(), font: .systemFont(ofSize: 10, weight: .semibold), color: .gray)
        skip(2)
        drawDivider()
        skip(4)
    }

    /// 用 `NSString.draw` 让 UIKit 处理换行——坐标系一致,不用手动翻转 Core Text。
    /// 如果整块文本比一页剩余空间还高,换页再画;极端超长文本会从新页顶部画,可能裁尾(MVP 接受)。
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

    /// 画一行 table。前 `widths.count` 列用固定宽度,最后一列用剩余宽度。
    mutating func drawTableRow(values: [String], widths: [CGFloat], isHeader: Bool) {
        let font: UIFont = isHeader
            ? .systemFont(ofSize: 10, weight: .semibold)
            : .systemFont(ofSize: 10.5, weight: .regular)
        let textColor: UIColor = isHeader ? .darkGray : .black

        // 预估行高(最后一列可能换行,简单按固定 lineHeight 算)
        let baseHeight: CGFloat = 16
        let lastColText = values.count > widths.count ? values[widths.count] : ""
        let lastColWidth = contentWidth - widths.reduce(0, +) - CGFloat(widths.count) * 4
        let wrappedLines = estimatedLines(text: lastColText, font: font, maxWidth: lastColWidth)
        let rowHeight = max(baseHeight, CGFloat(wrappedLines) * 13 + 4)

        ensureRoom(rowHeight)

        // 背景(header)
        if isHeader {
            let bgRect = CGRect(x: margin, y: y, width: contentWidth, height: rowHeight)
            let ctx = context.cgContext
            ctx.saveGState()
            ctx.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor)
            ctx.fill(bgRect)
            ctx.restoreGState()
        }

        var x = margin
        for (i, value) in values.enumerated() {
            let colWidth: CGFloat
            if i < widths.count {
                colWidth = widths[i]
            } else {
                colWidth = lastColWidth
            }
            let rect = CGRect(x: x + 2, y: y + 2, width: colWidth - 4, height: rowHeight - 4)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            (value as NSString).draw(in: rect, withAttributes: attrs)
            x += colWidth + 4
        }

        // 底线
        let ctx = context.cgContext
        ctx.saveGState()
        ctx.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
        ctx.setLineWidth(0.3)
        ctx.move(to: CGPoint(x: margin, y: y + rowHeight))
        ctx.addLine(to: CGPoint(x: margin + contentWidth, y: y + rowHeight))
        ctx.strokePath()
        ctx.restoreGState()

        y += rowHeight
    }

    private func estimatedLines(text: String, font: UIFont, maxWidth: CGFloat) -> Int {
        guard !text.isEmpty, maxWidth > 0 else { return 1 }
        let size = (text as NSString).size(withAttributes: [.font: font])
        let lines = Int(ceil(size.width / maxWidth))
        return max(1, lines)
    }
}
