//
//  ASCIISlug.swift
//  SiteNote
//
//  把任意字符串转成 ASCII 安全的文件名 slug(用于 PDF 文件命名)。
//  从已删除的 TradieReportPDFBuilder 抢救出来,InspectionReportPDFBuilder + SiteDiaryPDFBuilder 都用。
//

import Foundation

enum ASCIISlug {
    /// 把任意字符串转成 [A-Za-z0-9_-] 的 slug,长度上限 32。
    /// 中文/非 ASCII 整体会被替换为 fallback(否则中文文件名在某些邮件客户端会乱码)。
    static func make(_ raw: String?, fallback: String = "untitled", maxLength: Int = 32) -> String {
        guard let raw else { return fallback }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        var out = ""
        for scalar in trimmed.unicodeScalars {
            if scalar.isASCII {
                let c = Character(scalar)
                if c.isLetter || c.isNumber {
                    out.append(c)
                } else if c == " " || c == "-" || c == "_" || c == "." {
                    out.append("-")
                }
                // 其他 ASCII 标点丢弃
            }
            // 非 ASCII 直接跳过(中文等)
        }
        // 折叠连续 "-"
        while out.contains("--") {
            out = out.replacingOccurrences(of: "--", with: "-")
        }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))

        if out.isEmpty { return fallback }
        if out.count > maxLength {
            out = String(out.prefix(maxLength))
        }
        return out
    }
}
