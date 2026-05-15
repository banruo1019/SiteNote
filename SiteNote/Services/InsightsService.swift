//
//  InsightsService.swift
//  SiteNote
//
//  Phase 10c:主动洞察。扫描 notes 的历史数据,找出模式、风险、机会,主动告诉用户。
//  纯规则匹配,不依赖 AI,任何机型都工作。
//

import Foundation

enum InsightsService {

    enum Severity {
        case info, warning, critical

        var iconSystemName: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .critical: return "exclamationmark.triangle.fill"
            }
        }
    }

    struct Insight: Identifiable {
        let id: UUID = UUID()
        let icon: String
        let severity: Severity
        let title: String
        let detail: String
    }

    /// 分析全部 notes,返回按严重程度排的洞察列表。
    static func analyze(notes allNotes: [Note], now: Date = Date()) -> [Insight] {
        var insights: [Insight] = []
        let cal = Calendar.current

        // 1. 超期 7 天未处理
        if let weekAgo = cal.date(byAdding: .day, value: -7, to: now) {
            let longOverdue = allNotes.filter {
                !$0.isDone && $0.deadline != .archive && $0.dueDate < weekAgo
            }
            if !longOverdue.isEmpty {
                let sample = longOverdue
                    .prefix(3)
                    .map { String($0.transcription.prefix(20)) }
                    .joined(separator: " · ")
                let count = longOverdue.count
                insights.append(Insight(
                    icon: "clock.badge.exclamationmark.fill",
                    severity: .critical,
                    title: String(localized: "\(count) 条已延期超过 7 天", locale: AppLanguageManager.currentLocale),
                    detail: String(localized: "这些风险在累积,建议今天就处理:\(sample)", locale: AppLanguageManager.currentLocale)
                ))
            }
        }

        // 2. 隐患未处理
        let pendingHazards = allNotes.filter { $0.isHazard && !$0.isDone }
        if pendingHazards.count >= 2 {
            let count = pendingHazards.count
            insights.append(Insight(
                icon: "exclamationmark.triangle.fill",
                severity: .warning,
                title: String(localized: "有 \(count) 条隐患未处理", locale: AppLanguageManager.currentLocale),
                detail: String(localized: "OHS 合规要求,请尽快解决或上报上级。", locale: AppLanguageManager.currentLocale)
            ))
        }

        // 3. 某个 Subbie 积压
        var assigneeOverdue: [String: Int] = [:]
        for note in allNotes where !note.isDone && note.deadline != .archive && note.dueDate < now {
            if let a = note.assignedTo {
                assigneeOverdue[a, default: 0] += 1
            }
        }
        if let worst = assigneeOverdue.max(by: { $0.value < $1.value }), worst.value >= 3 {
            let name = worst.key
            let cnt = worst.value
            insights.append(Insight(
                icon: "person.fill.questionmark",
                severity: .warning,
                title: String(localized: "\(name) 有 \(cnt) 条未处理", locale: AppLanguageManager.currentLocale),
                detail: String(localized: "指派给他/她的任务积压,建议当面追一下。", locale: AppLanguageManager.currentLocale)
            ))
        }

        // 4. 工地静默(3 天没记录)
        let sites = Set(allNotes.compactMap { $0.siteTag })
        var silentSites: [(String, Int)] = []
        for site in sites {
            let siteNotes = allNotes.filter { $0.siteTag == site }
            guard let latest = siteNotes.map({ $0.createdAt }).max() else { continue }
            let daysSince = cal.dateComponents([.day], from: latest, to: now).day ?? 0
            if daysSince >= 3 {
                silentSites.append((site, daysSince))
            }
        }
        silentSites.sort { $0.1 > $1.1 }
        for (site, days) in silentSites.prefix(3) {
            insights.append(Insight(
                icon: "clock.badge.questionmark",
                severity: .info,
                title: String(localized: "\(site) 已 \(days) 天无记录", locale: AppLanguageManager.currentLocale),
                detail: String(localized: "如果工地仍在施工,建议回访或补记,避免记录断层影响 EOT 证据。", locale: AppLanguageManager.currentLocale)
            ))
        }

        // 5. 本周不利天气 → EOT 机会
        if let weekAgo = cal.date(byAdding: .day, value: -7, to: now) {
            let adverseDays = Set(allNotes.filter {
                guard $0.createdAt > weekAgo, let code = $0.weatherCode else { return false }
                return WeeklySummaryService.isAdverseWeather(code: code, tempC: $0.temperatureCelsius)
            }.map { cal.startOfDay(for: $0.createdAt) })

            if adverseDays.count >= 2 {
                let count = adverseDays.count
                insights.append(Insight(
                    icon: "cloud.rain.fill",
                    severity: .info,
                    title: String(localized: "本周有 \(count) 天天气异常", locale: AppLanguageManager.currentLocale),
                    detail: String(localized: "可到「报告 → EOT 工期延误」生成正式证据报告。", locale: AppLanguageManager.currentLocale)
                ))
            }
        }

        // 6. 本周高效
        if let weekAgo = cal.date(byAdding: .day, value: -7, to: now) {
            let doneThisWeek = allNotes.filter { $0.isDone && $0.createdAt > weekAgo }
            if doneThisWeek.count >= 5 {
                let count = doneThisWeek.count
                insights.append(Insight(
                    icon: "checkmark.seal.fill",
                    severity: .info,
                    title: String(localized: "本周完成 \(count) 项", locale: AppLanguageManager.currentLocale),
                    detail: String(localized: "不错的节奏!可考虑生成周报分享给团队。", locale: AppLanguageManager.currentLocale)
                ))
            }
        }

        // 按严重度排
        return insights.sorted { lhs, rhs in
            severityRank(lhs.severity) < severityRank(rhs.severity)
        }
    }

    private static func severityRank(_ s: Severity) -> Int {
        switch s {
        case .critical: return 0
        case .warning: return 1
        case .info: return 2
        }
    }
}
