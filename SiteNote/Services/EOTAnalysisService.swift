//
//  EOTAnalysisService.swift
//  SiteNote
//
//  工期延误主张(EOT)分析。根据每条速记里记录的天气,识别"无法正常施工"的日子,
//  聚合成一份可直接上交业主/律师的 PDF 证据。这是 SiteNote 的护城河(任务 4)。
//

import Foundation
import UIKit

enum EOTAnalysisService {

    /// 一份 EOT 分析报告。
    struct Report {
        let startDate: Date
        let endDate: Date
        let totalCalendarDays: Int
        let adverseDays: [AdverseDay]

        var claimableDays: Int { adverseDays.count }
    }

    /// 一个被判为不利天气的日子。
    struct AdverseDay {
        let date: Date
        /// 人类可读的天气原因,例如 "雨 + 高温 41°C"。
        let reason: String
        /// WMO 原始编码,留给将来更精细判定。
        let weatherCode: Int
        /// 当天在 SiteNote 里记录的 notes,用作证据链。
        let sourceNotes: [Note]
    }

    enum EOTError: LocalizedError {
        case renderFailed(String)
        var errorDescription: String? {
            switch self {
            case .renderFailed(let s): return "EOT PDF 生成失败: \(s)"
            }
        }
    }

    /// 分析在指定时间范围里的 notes,输出 EOT 报告。
    static func analyze(notes allNotes: [Note], startDate: Date, endDate: Date) -> Report {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: startDate)
        let endDay = cal.startOfDay(for: endDate)

        // 先按天分组 notes
        var notesPerDay: [Date: [Note]] = [:]
        for note in allNotes where note.createdAt >= startDay && note.createdAt <= endDate {
            let day = cal.startOfDay(for: note.createdAt)
            notesPerDay[day, default: []].append(note)
        }

        // 每一天里挑"最不利"的那条天气代表。若当天全是晴,跳过。
        var adverseDays: [AdverseDay] = []
        for (day, dayNotes) in notesPerDay {
            let adverseNote = dayNotes.first { note in
                guard let code = note.weatherCode else { return false }
                return WeeklySummaryService.isAdverseWeather(code: code, tempC: note.temperatureCelsius)
            }
            guard let note = adverseNote, let code = note.weatherCode else { continue }
            adverseDays.append(AdverseDay(
                date: day,
                reason: WeeklySummaryService.describeWeather(code: code, tempC: note.temperatureCelsius),
                weatherCode: code,
                sourceNotes: dayNotes
            ))
        }
        adverseDays.sort { $0.date < $1.date }

        let totalDays = (cal.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1

        return Report(
            startDate: startDate,
            endDate: endDate,
            totalCalendarDays: totalDays,
            adverseDays: adverseDays
        )
    }

    /// 用 UIGraphicsPDFRenderer 渲染报告为 PDF,返回临时文件 URL。
    static func generatePDF(report: Report) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let filename = "SiteNote-EOT-\(Int(Date().timeIntervalSince1970)).pdf"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: outputURL)

        do {
            try renderer.writePDF(to: outputURL) { ctx in
                drawCoverPage(context: ctx, report: report, in: pageRect)
                if !report.adverseDays.isEmpty {
                    ctx.beginPage()
                    drawAdverseDaysList(context: ctx, report: report, in: pageRect)
                }
            }
        } catch {
            throw EOTError.renderFailed(error.localizedDescription)
        }
        return outputURL
    }

    // MARK: - Pages

    private static func drawCoverPage(
        context: UIGraphicsPDFRendererContext,
        report: Report,
        in pageRect: CGRect
    ) {
        context.beginPage()
        let leftMargin: CGFloat = 50
        var y: CGFloat = 80

        drawText("EXTENSION OF TIME CLAIM",
                 at: CGPoint(x: leftMargin, y: y),
                 fontSize: 24, bold: true)
        y += 30
        drawText("工期延误主张证据报告",
                 at: CGPoint(x: leftMargin, y: y),
                 fontSize: 16, color: .darkGray)
        y += 50

        let df = DateFormatter()
        df.dateStyle = .long
        df.locale = Locale(identifier: "zh-CN")

        drawText("评估期间", at: CGPoint(x: leftMargin, y: y), fontSize: 14, bold: true)
        y += 22
        drawText(
            "\(df.string(from: report.startDate))  —  \(df.string(from: report.endDate))",
            at: CGPoint(x: leftMargin, y: y),
            fontSize: 14
        )
        y += 22
        drawText("共 \(report.totalCalendarDays) 个日历日", at: CGPoint(x: leftMargin, y: y), fontSize: 14)
        y += 50

        drawText("核心结论", at: CGPoint(x: leftMargin, y: y), fontSize: 14, bold: true)
        y += 22
        drawText(
            "根据 SiteNote 记录的现场天气观测,在上述期间内共有 \(report.claimableDays) 天因不利天气无法进行正常施工。",
            at: CGPoint(x: leftMargin, y: y),
            fontSize: 14
        )
        y += 24
        drawText(
            "建议基于合同条款(例如 AS4000 Clause 34 - Extension of Time)主张工期延长 \(report.claimableDays) 天。",
            at: CGPoint(x: leftMargin, y: y),
            fontSize: 14
        )
        y += 60

        drawText("不利天气认定标准", at: CGPoint(x: leftMargin, y: y), fontSize: 14, bold: true)
        y += 22
        let criteria = [
            "- 降雨(WMO 51-67, 80-82)",
            "- 降雪(WMO 71-77, 85-86)",
            "- 雷暴(WMO 95-99)",
            "- 雾(WMO 45, 48)",
            "- 极端气温(低于 -10°C 或高于 38°C)"
        ]
        for line in criteria {
            drawText(line, at: CGPoint(x: leftMargin, y: y), fontSize: 12, color: .darkGray)
            y += 18
        }

        y += 40
        drawLine(from: CGPoint(x: leftMargin, y: y),
                 to: CGPoint(x: leftMargin + 300, y: y))
        y += 15
        drawText("签署人 / Signed", at: CGPoint(x: leftMargin, y: y), fontSize: 12, color: .darkGray)
        y += 30
        drawLine(from: CGPoint(x: leftMargin, y: y),
                 to: CGPoint(x: leftMargin + 300, y: y))
        y += 15
        drawText("日期 / Date", at: CGPoint(x: leftMargin, y: y), fontSize: 12, color: .darkGray)

        y = pageRect.height - 60
        drawText("由 SiteNote 基于现场观测数据自动生成 · \(Date().formatted(date: .abbreviated, time: .shortened))",
                 at: CGPoint(x: leftMargin, y: y),
                 fontSize: 10, color: .gray)
    }

    private static func drawAdverseDaysList(
        context: UIGraphicsPDFRendererContext,
        report: Report,
        in pageRect: CGRect
    ) {
        let leftMargin: CGFloat = 40
        var y: CGFloat = 50

        drawText("不利天气日列表",
                 at: CGPoint(x: leftMargin, y: y),
                 fontSize: 18, bold: true)
        y += 32
        drawText(
            "共 \(report.adverseDays.count) 天(每天附现场记录作为证据)",
            at: CGPoint(x: leftMargin, y: y),
            fontSize: 12, color: .darkGray
        )
        y += 30

        let df = DateFormatter()
        df.dateStyle = .long
        df.locale = Locale(identifier: "zh-CN")

        for (index, day) in report.adverseDays.enumerated() {
            if y > pageRect.height - 80 {
                context.beginPage()
                y = 50
            }

            drawText("\(index + 1). \(df.string(from: day.date))",
                     at: CGPoint(x: leftMargin, y: y),
                     fontSize: 14, bold: true)
            y += 22
            drawText("天气: \(day.reason) (WMO \(day.weatherCode))",
                     at: CGPoint(x: leftMargin + 20, y: y),
                     fontSize: 12)
            y += 18
            drawText("当天现场记录 \(day.sourceNotes.count) 条:",
                     at: CGPoint(x: leftMargin + 20, y: y),
                     fontSize: 12, color: .darkGray)
            y += 18

            for note in day.sourceNotes.prefix(3) {
                let t = String(note.transcription.prefix(60))
                let preview = t.isEmpty ? "(仅录音)" : t
                drawText("• \(preview)",
                         at: CGPoint(x: leftMargin + 40, y: y),
                         fontSize: 11, color: .darkGray)
                y += 16
            }
            if day.sourceNotes.count > 3 {
                drawText("…(还有 \(day.sourceNotes.count - 3) 条)",
                         at: CGPoint(x: leftMargin + 40, y: y),
                         fontSize: 11, color: .gray)
                y += 16
            }
            y += 14
        }
    }

    // MARK: - Draw helpers

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

    private static func drawLine(from p1: CGPoint, to p2: CGPoint) {
        let path = UIBezierPath()
        path.move(to: p1)
        path.addLine(to: p2)
        UIColor.darkGray.setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }
}
