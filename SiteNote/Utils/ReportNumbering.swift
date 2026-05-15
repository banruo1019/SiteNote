//
//  ReportNumbering.swift
//  SiteNote
//
//  巡检报告编号生成 / 解析。
//
//  格式:SVR{projectNo}.{visitIndex:02d}{revision:A|B|C|...}
//  例:SVR25159.05A → 项目 25159 第 5 次访问 第 A 版
//
//  visitIndex 按项目内累计,从 01 开始;revision 用于同次访问的修订版本,A 初版。
//

import Foundation

/// 巡检报告编号工具。纯函数,无状态。
enum ReportNumbering {

    /// 通用正则:^SVR(项目号).(访问次数2位+)(单字母版本)$
    /// 项目号本身允许是数字或字母数字混合(预防客户编号带字母,例如 "AB25159")。
    /// visitIndex 是数字串(至少 1 位,实际写出来零填充到 2 位)。
    private static let pattern = #"^SVR([A-Z0-9]+)\.(\d+)([A-Z])$"#

    /// 生成一个新的报告编号。
    /// - Parameters:
    ///   - projectNo: 项目编号(从 InspectionDraft.projectNo 取)。会被去空格 + 转大写。
    ///   - existingNumbers: 同一项目已存在的报告编号列表(用于计算下一个 index)。
    /// - Returns: 新报告编号,默认 revision A。
    static func nextNumber(projectNo: String, existingNumbers: [String]) -> String {
        let proj = normalize(projectNo)
        // 找同 projectNo 的最大 visitIndex,+1。
        var maxIndex = 0
        for number in existingNumbers {
            guard let parsed = parse(number) else { continue }
            if parsed.projectNo == proj {
                maxIndex = max(maxIndex, parsed.visitIndex)
            }
        }
        let next = maxIndex + 1
        return format(projectNo: proj, visitIndex: next, revision: "A")
    }

    /// 升级一个已有 number 的 revision(A→B→C→...)。
    /// - 输入合法 number,返回下一个字母版本。
    /// - 输入 "...Z" 返回原样(到 Z 就封顶,工程上不会到 Z)。
    /// - 输入非法格式,原样返回。
    static func bumpRevision(_ number: String) -> String {
        guard let parsed = parse(number) else { return number }
        guard let scalar = parsed.revision.unicodeScalars.first else { return number }
        // 已经到 Z,封顶。
        if scalar.value >= Unicode.Scalar("Z").value { return number }
        let next = Unicode.Scalar(scalar.value + 1)!
        let nextLetter = String(Character(next))
        return format(projectNo: parsed.projectNo, visitIndex: parsed.visitIndex, revision: nextLetter)
    }

    /// 校验 number 格式合法。
    static func isValid(_ number: String) -> Bool {
        parse(number) != nil
    }

    // MARK: - 内部

    /// 解析后的字段。
    struct Parsed: Equatable {
        let projectNo: String
        let visitIndex: Int
        let revision: String   // 单字母 "A"..."Z"
    }

    /// 解析 number。不合法返回 nil。
    static func parse(_ number: String) -> Parsed? {
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              match.numberOfRanges == 4,
              let projRange = Range(match.range(at: 1), in: trimmed),
              let idxRange = Range(match.range(at: 2), in: trimmed),
              let revRange = Range(match.range(at: 3), in: trimmed),
              let visitIndex = Int(trimmed[idxRange])
        else { return nil }
        return Parsed(
            projectNo: String(trimmed[projRange]),
            visitIndex: visitIndex,
            revision: String(trimmed[revRange])
        )
    }

    /// 拼出标准 number。visitIndex 零填充 2 位(>=100 时按实际位数写,不再截断)。
    private static func format(projectNo: String, visitIndex: Int, revision: String) -> String {
        let idxString = String(format: "%02d", visitIndex)
        return "SVR\(projectNo).\(idxString)\(revision)"
    }

    /// 归一化项目号:去空格 + 大写。空字符串保留(让调用方上层校验)。
    private static func normalize(_ projectNo: String) -> String {
        projectNo.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
