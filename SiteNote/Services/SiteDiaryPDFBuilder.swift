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
            case .renderFailed(let s): return "Site Diary 生成失败: \(s)"
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

        let siteSlug = (siteTag ?? "全部").replacingOccurrences(of: " ", with: "_")
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

    // MARK: - Header

    private static func drawHeader(
        cursor: inout PDFCursor,
        date: Date,
        siteTag: String?,
        weather: String?,
        stats: Stats
    ) {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy 年 M 月 d 日 EEEE"

        cursor.drawText("Daily Site Diary · 工地日志", font: .systemFont(ofSize: 11, weight: .medium), color: .gray)
        cursor.skip(6)
        cursor.drawText(df.string(from: date), font: .systemFont(ofSize: 22, weight: .semibold))
        cursor.skip(6)

        var metaParts: [String] = []
        if let s = siteTag, !s.isEmpty { metaParts.append("工地:\(s)") } else { metaParts.append("工地:全部") }
        if let w = weather, !w.isEmpty { metaParts.append("天气:\(w)") }
        cursor.drawText(metaParts.joined(separator: " · "), font: .systemFont(ofSize: 11), color: .darkGray)

        cursor.skip(10)
        cursor.drawDivider()
        cursor.skip(8)

        // 摘要行
        let summaryLine = "到场合计 \(stats.headcount) 人 · 机械 \(stats.plantClosed + stats.plantOpen) 条(未结束 \(stats.plantOpen)) · 原始速记 \(stats.noteCount) 条"
        cursor.drawText(summaryLine, font: .systemFont(ofSize: 11, weight: .medium), color: .darkGray)
        cursor.skip(14)
    }

    private static func drawNarrative(cursor: inout PDFCursor, text: String) {
        cursor.drawSectionHeader("AI 生成 · 日志叙述")
        cursor.skip(4)
        cursor.drawWrappedText(text, font: .systemFont(ofSize: 11), lineHeight: 15)
        cursor.skip(12)
    }

    // MARK: - Person table

    private static func drawPersonTable(cursor: inout PDFCursor, entries: [LogEntry]) {
        cursor.drawSectionHeader("人员到场")
        cursor.skip(4)

        // 列宽: 工种(180) | 数量(60) | 时间(70) | 备注(剩余)
        let cols: [CGFloat] = [180, 60, 70]
        let headers = ["工种 / 班组", "数量", "时间", "备注"]
        cursor.drawTableRow(values: headers, widths: cols, isHeader: true)

        for e in entries {
            let quantity: String
            if e.isAbsent { quantity = "缺席" }
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
        cursor.drawSectionHeader("机械进出场")
        cursor.skip(4)

        // 列宽: 设备(160) | 开始(65) | 结束(65) | 时长(60) | 备注(剩余)
        let cols: [CGFloat] = [160, 65, 65, 60]
        let headers = ["设备", "开始", "结束", "时长", "备注"]
        cursor.drawTableRow(values: headers, widths: cols, isHeader: true)

        for e in entries {
            let endStr: String
            let durStr: String
            var noteStr = e.note ?? ""

            if e.isOpenPlantSession {
                endStr = "—"
                durStr = "开启中"
                if noteStr.isEmpty { noteStr = "未结束,需关闭" }
            } else if e.startAt == e.endAt {
                endStr = "—"
                durStr = "孤儿"
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
        cursor.drawSectionHeader("送达 / 访客 / 事件")
        cursor.skip(4)

        // 列宽: 类型(60) | 时间(65) | 条目(剩余)
        let cols: [CGFloat] = [60, 65]
        let headers = ["类型", "时间", "内容"]
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
        cursor.drawSectionHeader("原始速记(按时间)")
        cursor.skip(4)

        for note in notes.sorted(by: { $0.createdAt < $1.createdAt }) {
            let time = hhmm(note.createdAt)
            var prefix = "[\(time)]"
            if note.isHazard { prefix += " 🚨" }
            let body = note.transcription.isEmpty ? "(仅录音/照片)" : note.transcription
            cursor.drawWrappedText("\(prefix) \(body)", font: .systemFont(ofSize: 10.5), lineHeight: 14)
            cursor.skip(6)
        }
    }

    private static func drawFooter(cursor: inout PDFCursor) {
        cursor.skip(14)
        cursor.drawDivider()
        cursor.skip(6)
        let ts = DateFormatter()
        ts.dateFormat = "yyyy-MM-dd HH:mm"
        cursor.drawText("由 SiteNote 生成于 \(ts.string(from: Date()))",
                        font: .systemFont(ofSize: 9), color: .lightGray)
    }

    // MARK: - Utilities

    /// 到场总人数。quantity=nil 按 1 人算(和 DiaryView 口径一致)。
    private static func personHeadcount(_ persons: [LogEntry]) -> Int {
        persons
            .filter { !$0.isAbsent }
            .map { $0.quantity ?? 1 }
            .reduce(0, +)
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
