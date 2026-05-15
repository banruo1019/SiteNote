//
//  NarrativeService.swift
//  SiteNote
//
//  Phase 10b:叙事和正式文书生成。通过 AIService.runTextStrict 走引擎路由(GPT 优先、本地备选)。
//

import Foundation

@MainActor
enum NarrativeService {

    /// 生成某一天的施工日志(中文,可读可发)。
    static func generateDailyNarrative(notes: [Note], date: Date) async throws -> String {
        guard !notes.isEmpty else {
            return String(localized: "当日无记录。", locale: AppLanguageManager.currentLocale)
        }

        let sorted = notes.sorted { $0.createdAt < $1.createdAt }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let formatted = sorted.map { n -> String in
            let t = timeFormatter.string(from: n.createdAt)
            let loc = n.locationAddress.map { " @ \($0)" } ?? ""
            let weather = n.weatherSummary.map { " (\($0))" } ?? ""
            let hazard = n.isHazard ? " [隐患]" : ""
            let body = n.transcription.isEmpty ? "(仅录音/照片)" : n.transcription
            return "\(t)\(loc)\(weather)\(hazard): \(body)"
        }.joined(separator: "\n")

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.locale = Locale(identifier: "zh-CN")

        let prompt = """
        你是一位澳洲建筑工地的项目经理。以下是 \(dateFormatter.string(from: date)) 当天\
        在工地上按时间顺序记录的 notes。请把它们拼成一段**连贯可读的中文施工日志**,\
        交给业主或监理。遵循:
        1. 保留所有事实和时间,不要虚构
        2. 体现进度/问题/隐患
        3. 不超过 400 字
        4. 用第三人称书面语,不要口语化

        Notes:
        \(formatted)

        施工日志:
        """

        return try await AIService.shared.runTextStrict(prompt: prompt)
    }

    /// 根据 EOT 报告数据生成一封正式的工期延长主张信(英文,澳洲 AS4000 风格)。
    static func generateEOTClaimLetter(report: EOTAnalysisService.Report) async throws -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.locale = Locale(identifier: "en_AU")

        let adverseSummary = report.adverseDays.map { day in
            "- \(df.string(from: day.date)): \(day.reason) (WMO \(day.weatherCode), \(day.sourceNotes.count) field records)"
        }.joined(separator: "\n")

        let prompt = """
        You are a senior construction contract administrator in Australia. Draft a formal\
         Extension of Time (EOT) claim letter based on the data below. The letter should:
        1. Be in formal business English, suitable for submission to the Principal/Superintendent
        2. Reference AS4000 Clause 34 (Extension of Time) as the contractual basis
        3. Summarise the adverse weather events with dates
        4. State the total days claimed: \(report.claimableDays)
        5. Keep under 500 words
        6. Include placeholders like [Project Name], [Principal], [Contractor] that the user fills

        Claim period: \(df.string(from: report.startDate)) to \(df.string(from: report.endDate))
        Total calendar days: \(report.totalCalendarDays)
        Adverse weather days (\(report.claimableDays)):
        \(adverseSummary)

        Letter:
        """

        return try await AIService.shared.runTextStrict(prompt: prompt)
    }
}
