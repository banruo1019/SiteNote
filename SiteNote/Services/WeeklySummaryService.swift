//
//  WeeklySummaryService.swift
//  SiteNote
//
//  本周总结:按 date range 统计 notes,输出结构化 Summary。纯逻辑,便于测试。
//  当前不使用 AI 文本生成,用模板拼接(任务 10 的 MVP 实现)。
//

import Foundation

/// 本周结构化总结(任务 10)。
enum WeeklySummaryService {

    struct Summary {
        let weekStart: Date
        let weekEnd: Date
        let totalNotes: Int
        let doneCount: Int
        let overdueCount: Int
        let hazardCount: Int
        let topSiteTags: [(String, Int)]
        let topAssignees: [(String, Int)]
        let pending: [Note]
        /// 日期 + 原因,例如 (2026-04-15, "降雨")。
        let adverseWeather: [(Date, String)]
    }

    static func summarize(
        notes allNotes: [Note],
        weekStart: Date,
        weekEnd: Date,
        now: Date = Date()
    ) -> Summary {
        let cal = Calendar.current
        let inRange = allNotes.filter { $0.createdAt >= weekStart && $0.createdAt <= weekEnd }

        let doneCount = inRange.filter { $0.isDone }.count
        let overdueCount = inRange.filter {
            !$0.isDone && $0.deadline != .archive && $0.dueDate < now
        }.count
        let hazardCount = inRange.filter { $0.isHazard }.count

        var tagCounts: [String: Int] = [:]
        for n in inRange {
            if let tag = n.siteTag { tagCounts[tag, default: 0] += 1 }
        }
        let topSiteTags = tagCounts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }

        var assigneeCounts: [String: Int] = [:]
        for n in inRange {
            if let a = n.assignedTo { assigneeCounts[a, default: 0] += 1 }
        }
        let topAssignees = assigneeCounts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }

        let pending = inRange
            .filter { !$0.isDone && $0.deadline != .archive }
            .sorted { $0.dueDate < $1.dueDate }

        var adverseByDay: [Date: String] = [:]
        for n in inRange {
            guard let code = n.weatherCode else { continue }
            if isAdverseWeather(code: code, tempC: n.temperatureCelsius) {
                let day = cal.startOfDay(for: n.createdAt)
                if adverseByDay[day] == nil {
                    adverseByDay[day] = describeWeather(code: code, tempC: n.temperatureCelsius)
                }
            }
        }
        let adverse = adverseByDay
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }

        return Summary(
            weekStart: weekStart,
            weekEnd: weekEnd,
            totalNotes: inRange.count,
            doneCount: doneCount,
            overdueCount: overdueCount,
            hazardCount: hazardCount,
            topSiteTags: Array(topSiteTags),
            topAssignees: Array(topAssignees),
            pending: pending,
            adverseWeather: adverse
        )
    }

    /// WMO 码或极端气温是否算"不利天气"。EOT 也复用此判断。
    static func isAdverseWeather(code: Int, tempC: Double?) -> Bool {
        let adverseCodes: Set<Int> = [
            45, 48,                // fog
            51, 53, 55, 56, 57,    // drizzle
            61, 63, 65, 66, 67,    // rain
            71, 73, 75, 77,        // snow
            80, 81, 82,            // rain showers
            85, 86,                // snow showers
            95, 96, 99             // thunderstorm
        ]
        if adverseCodes.contains(code) { return true }
        if let t = tempC, t > 38 || t < -10 { return true }
        return false
    }

    static func describeWeather(code: Int, tempC: Double?) -> String {
        var desc = WeatherService.description(code: code)
        if let t = tempC {
            let tInt = Int(t)
            if t > 38 { desc += String(localized: " + 高温 \(tInt)°C", locale: AppLanguageManager.currentLocale) }
            if t < -10 { desc += String(localized: " + 极寒 \(tInt)°C", locale: AppLanguageManager.currentLocale) }
        }
        return desc
    }

    /// 把 Summary 拼成一段可复制/分享的文本。
    static func formatAsText(_ s: Summary) -> String {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("Md")
        df.locale = Locale.current

        var lines: [String] = []
        lines.append(String(localized: "📊 本周总结", locale: AppLanguageManager.currentLocale))
        lines.append("\(df.string(from: s.weekStart)) - \(df.string(from: s.weekEnd))")
        lines.append("")
        lines.append(String(localized: "• 总共 \(s.totalNotes) 条速记", locale: AppLanguageManager.currentLocale))
        lines.append(String(localized: "• 已完成 \(s.doneCount) 条", locale: AppLanguageManager.currentLocale))
        if s.overdueCount > 0 {
            lines.append(String(localized: "• ⚠️ 逾期未处理 \(s.overdueCount) 条", locale: AppLanguageManager.currentLocale))
        }
        if s.hazardCount > 0 {
            lines.append(String(localized: "• 🚨 隐患 \(s.hazardCount) 条", locale: AppLanguageManager.currentLocale))
        }

        if !s.topSiteTags.isEmpty {
            lines.append("")
            lines.append(String(localized: "📍 工地分布:", locale: AppLanguageManager.currentLocale))
            for (tag, count) in s.topSiteTags {
                lines.append(String(localized: "  - \(tag): \(count) 条", locale: AppLanguageManager.currentLocale))
            }
        }

        if !s.topAssignees.isEmpty {
            lines.append("")
            lines.append(String(localized: "👥 指派给:", locale: AppLanguageManager.currentLocale))
            for (name, count) in s.topAssignees {
                lines.append(String(localized: "  - \(name): \(count) 条", locale: AppLanguageManager.currentLocale))
            }
        }

        if !s.adverseWeather.isEmpty {
            lines.append("")
            lines.append(String(localized: "🌧 天气异常日(EOT 参考):", locale: AppLanguageManager.currentLocale))
            for (date, reason) in s.adverseWeather {
                lines.append("  - \(df.string(from: date)) \(reason)")
            }
        }

        if !s.pending.isEmpty {
            lines.append("")
            lines.append(String(localized: "📋 待处理(按紧迫度,前 5 条):", locale: AppLanguageManager.currentLocale))
            for note in s.pending.prefix(5) {
                let preview = String(note.transcription.prefix(40))
                let flag = note.isHazard ? "🚨 " : ""
                lines.append("  - \(flag)\(preview)")
            }
        }

        lines.append("")
        lines.append(String(localized: "—— 由 SiteNote 自动生成", locale: AppLanguageManager.currentLocale))

        return lines.joined(separator: "\n")
    }
}
