//
//  EmailTemplateStorage.swift
//  SiteNote
//
//  Engineer 一键发邮件的主题/正文模板。原本 EmailService 里硬编码英文模板,
//  现在让用户在设置里自定义(中英都可),按占位符渲染。
//
//  设计:
//  - struct `EmailTemplate` Codable,存 UserDefaults JSON。
//  - 占位符 MVP 5 个:{project}/{projectNo}/{client}/{reportNo}/{date}/{inspectionType}
//  - 没存过时返回 `defaultTemplate()`(中文为主,带占位符)。
//  - render 时空字段降级为空串(不留 "{project}" 在最终邮件里)。
//

import Foundation

struct EmailTemplate: Codable, Equatable {
    var id: UUID
    var subject: String
    var body: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        subject: String,
        body: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.subject = subject
        self.body = body
        self.updatedAt = updatedAt
    }
}

enum EmailTemplateStorage {
    private static let key = "settings.emailTemplate.v1"

    /// 默认种子模板(英文,带占位符)。澳洲工程师场景,客户都是英文邮件。
    /// 工程师巡检完发给建造商常用文案,占位符覆盖 MVP 5 项报告头字段。
    /// 模板可在 设置 → 报告 → 邮件模板 自定义。
    static func defaultTemplate() -> EmailTemplate {
        let subject = "[SiteNote] {reportNo} - {project} {inspectionType}"
        let body = """
        Hi,

        Please find attached the inspection report for {date}:

        Project: {project} ({projectNo})
        Type: {inspectionType}
        Report No: {reportNo}

        Let me know if you have any questions.

        Best regards
        """
        return EmailTemplate(subject: subject, body: body)
    }

    /// 读取用户自定义模板;没存过返回默认。
    static func load() -> EmailTemplate {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let template = try? JSONDecoder().decode(EmailTemplate.self, from: data)
        else {
            return defaultTemplate()
        }
        return template
    }

    /// 保存(覆盖)。失败静默(UserDefaults 写不进通常是磁盘满,UI 不需要处理)。
    static func save(_ template: EmailTemplate) {
        var copy = template
        copy.updatedAt = Date()
        guard let data = try? JSONEncoder().encode(copy) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// 恢复默认(清自定义)。
    static func restoreDefaults() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// 按 InspectionReport 渲染主题 + 正文,替换占位符。
    /// 空字段替换成空串,避免在最终邮件里留 "{project}" 这种字面量。
    /// 日期用 Formatters.dayMonthShort(报告里常用的 "17 May" 格式)。
    static func render(
        _ template: EmailTemplate,
        report: InspectionReport
    ) -> (subject: String, body: String) {
        let dateString = Formatters.dayMonthShort.string(from: report.reportDate)

        let replacements: [(String, String)] = [
            ("{project}", report.project.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("{projectNo}", report.projectNo.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("{client}", report.client.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("{reportNo}", report.reportNo.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("{date}", dateString),
            ("{inspectionType}", report.inspectionType.trimmingCharacters(in: .whitespacesAndNewlines))
        ]

        var subject = template.subject
        var body = template.body
        for (token, value) in replacements {
            subject = subject.replacingOccurrences(of: token, with: value)
            body = body.replacingOccurrences(of: token, with: value)
        }

        // 清理:占位符为空时会留下双空格 / 残破括号,稍微 normalize 一下 subject。
        // body 保留原排版(用户自己写的格式),只 trim subject 两端 + 折叠多空格。
        let cleanedSubject = subject
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: " - -", with: " -")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (subject: cleanedSubject, body: body)
    }
}
