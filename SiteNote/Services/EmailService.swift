//
//  EmailService.swift
//  SiteNote
//
//  Engineer 工作流"一键发邮件":给 `InspectionReport` 生成预填的主题 / 正文 / 收件人 / 附件。
//
//  设计:
//    - 纯函数模块(Foundation 即可,不依赖 SwiftUI / UIKit / SwiftData),易单测。
//    - 邮件正文/主题 **走用户模板**(EmailTemplateStorage):用户在「设置 → 邮件
//      模板」自定义,中英都行。占位符 {project}/{projectNo}/{client}/{reportNo}/
//      {date}/{inspectionType} 渲染时按报告字段填充。
//    - 失败容忍:模板渲染为空 → 降级到老的硬编码英文 fallback。绝不抛,
//      保证给用户一个能 send 的草稿。
//

import Foundation

enum EmailService {

    /// 纯数据版本的邮件附件,Foundation-only。
    /// `MailComposeView.Attachment` 是 SwiftUI-side 的镜像类型——InspectionExportSheet 负责转换。
    /// 这样 EmailService 可以脱离 SwiftUI / MessageUI 单元测试。
    struct PDFAttachment {
        let data: Data
        let mimeType: String
        let filename: String
    }

    // MARK: - 主题

    /// 主题:走用户模板(`EmailTemplateStorage.load()`)+ 占位符渲染。
    /// 用户在「设置 → 邮件模板」自定义,没存过用 `EmailTemplateStorage.defaultTemplate()`。
    /// 渲染后若仍为空(例如用户清空了模板),降级到老的硬编码英文 fallback,
    /// 保证 compose 永远有个可发的主题。
    static func subjectFor(report: InspectionReport) -> String {
        let template = EmailTemplateStorage.load()
        let rendered = EmailTemplateStorage.render(template, report: report).subject
        let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return fallbackSubject(for: report)
    }

    // MARK: - 正文

    /// 正文:走用户模板 + 占位符渲染。
    /// 渲染后若整体空白则降级到老的英文 fallback(保证草稿不是空白)。
    static func bodyFor(report: InspectionReport) -> String {
        let template = EmailTemplateStorage.load()
        let rendered = EmailTemplateStorage.render(template, report: report).body
        let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return rendered }
        return fallbackBody(for: report)
    }

    // MARK: - Fallback(硬编码英文)

    /// 老的硬编码英文 subject。模板渲染为空时才走。
    private static func fallbackSubject(for report: InspectionReport) -> String {
        let reportNo = report.reportNo.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = report.location.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = ["Site Visit Report"]
        if !reportNo.isEmpty {
            parts.append(reportNo)
        } else {
            parts.append("Draft")
        }
        if !location.isEmpty {
            parts.append(location)
        }
        return parts.joined(separator: " - ")
    }

    /// 老的硬编码英文 body。模板渲染为空时才走。
    private static func fallbackBody(for report: InspectionReport) -> String {
        let attn = report.attn.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = report.project.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = report.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let engineer = report.engineerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let company = (UserDefaults.standard.string(forKey: "settings.engineerCompanyName") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let greeting: String = attn.isEmpty ? "Hi team," : "Hi \(attn),"

        let mainLine: String
        switch (project.isEmpty, location.isEmpty) {
        case (false, false):
            mainLine = "Please find attached the site visit report for \(project) at \(location)."
        case (false, true):
            mainLine = "Please find attached the site visit report for \(project)."
        case (true, false):
            mainLine = "Please find attached the site visit report for the works at \(location)."
        case (true, true):
            mainLine = "Please find attached the site visit report."
        }

        let actionLine = "Items requiring action are listed in the report. Please rectify and reply with confirmation when completed."

        var signoffLines: [String] = ["Regards,"]
        if !engineer.isEmpty { signoffLines.append(engineer) }
        if !company.isEmpty { signoffLines.append(company) }
        let signoff = signoffLines.joined(separator: "\n")

        return """
        \(greeting)

        \(mainLine)

        \(actionLine)

        \(signoff)
        """
    }

    // MARK: - 收件人

    /// 默认收件人:从 `report.builderID` 反查 ContactsStorage,拿 email。
    /// v1.5:Builder 拆成 Builder(公司)+ Contact(联系人)后,legacy `builderID` 字段值
    /// 经 ContactsStorage.migrateFromBuilderLegacyOnce 重映射为对应 Contact.id。
    /// builderID 为 nil / 找不到 / email 空白 → 返回 `[]`,调用方在 UI 上据此让用户手填。
    static func defaultRecipientsFor(report: InspectionReport) -> [String] {
        guard let idString = report.builderID,
              let contact = ContactsStorage.find(idString: idString) else {
            return []
        }
        let email = contact.email.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? [] : [email]
    }

    // MARK: - 附件

    /// 把磁盘上的 PDF 读成 `PDFAttachment`。
    /// filename 优先用 report.reportNo,缺失时用 URL 原 lastPathComponent,再缺失时用 "report.pdf"。
    /// 读取失败(文件不存在 / 权限)返回 nil——调用方应该降级走 ShareSheet。
    static func loadPDFAttachment(at url: URL, reportNo: String? = nil) -> PDFAttachment? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let filename: String = {
            let trimmed = reportNo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return "\(trimmed).pdf"
            }
            let last = url.lastPathComponent
            return last.isEmpty ? "report.pdf" : last
        }()
        return PDFAttachment(
            data: data,
            mimeType: "application/pdf",
            filename: filename
        )
    }
}
