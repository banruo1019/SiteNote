//
//  EmailService.swift
//  SiteNote
//
//  Engineer 工作流"一键发邮件":给 `InspectionReport` 生成预填的主题 / 正文 / 收件人 / 附件。
//
//  设计:
//    - 纯函数模块(Foundation 即可,不依赖 SwiftUI / UIKit / SwiftData),易单测。
//    - 邮件正文/主题 **强制英文**(不读 AppLanguageManager / Locale):
//      工程师 Inspection 报告通常发给 builder/客户(国际通用英文),不需要
//      中文邮件正文。app UI 仍可中英切换,但发件草稿统一英文模板。
//    - 失败容忍:字段空就降级,绝不抛——给用户一个能 send 的草稿就赢一半。
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

    /// 主题构造(英文固定):`"Site Visit Report - <reportNo> - <location>"`。
    /// 字段为空时降级:
    ///   - reportNo 空 → 用 "Draft"
    ///   - location 空 → 仅 "Site Visit Report - <reportNo>"
    ///   - 全空 → "Site Visit Report - Draft"
    static func subjectFor(report: InspectionReport) -> String {
        let reportNo = report.reportNo.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = report.location.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = ["Site Visit Report"]
        if !reportNo.isEmpty {
            parts.append(reportNo)
        } else {
            // 没编号也别给个奇怪 "Site Visit Report -  - 38 Forsyth"
            parts.append("Draft")
        }
        if !location.isEmpty {
            parts.append(location)
        }
        return parts.joined(separator: " - ")
    }

    // MARK: - 正文

    /// 正文(英文固定)。不读 AppLanguageManager / Locale。
    /// 空字段降级:
    ///   - attn 空 → 称呼 "Hi team,"
    ///   - project / location 空 → 句子里降级或整段省略
    ///   - engineerName 空 → 末尾只剩 "Regards,"
    ///   - companyName(从 UserDefaults 读)非空时附在签名第二行
    static func bodyFor(report: InspectionReport) -> String {
        let attn = report.attn.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = report.project.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = report.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let engineer = report.engineerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let company = (UserDefaults.standard.string(forKey: "settings.engineerCompanyName") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let greeting: String = attn.isEmpty ? "Hi team," : "Hi \(attn),"

        // 主句按 project / location 是否齐全选不同模板,避免 "for  at "。
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

        // 签名:Regards, / engineer / company(后两个都可空)
        var signoffLines: [String] = ["Regards,"]
        if !engineer.isEmpty {
            signoffLines.append(engineer)
        }
        if !company.isEmpty {
            signoffLines.append(company)
        }
        let signoff = signoffLines.joined(separator: "\n")

        return """
        \(greeting)

        \(mainLine)

        \(actionLine)

        \(signoff)
        """
    }

    // MARK: - 收件人

    /// 默认收件人:从 `report.builderID` 反查 BuildersStorage,拿 email。
    /// builderID 为 nil / 找不到 / email 空白 → 返回 `[]`。
    /// 调用方在 UI 上据此让用户手填或换 Builder。
    static func defaultRecipientsFor(report: InspectionReport) -> [String] {
        guard let idString = report.builderID,
              let builder = BuildersStorage.find(idString: idString) else {
            return []
        }
        let email = builder.email.trimmingCharacters(in: .whitespacesAndNewlines)
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
