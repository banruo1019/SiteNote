//
//  ChineseDateParser.swift
//  SiteNote
//
//  从录音转写里猜用户想要的 deadline 或识别"保存"命令。规则匹配,无 ML。
//  准确率低时回退到默认行为,不强加。
//

import Foundation

/// 解析中文/英文语音里的到期指示和命令。
enum ChineseDateParser {

    /// 从转写文本里推断 deadline。无法推断返回 nil。
    /// 优先级:archive > today > thisWeek > threeDays。
    static func parseDeadline(from text: String) -> Deadline? {
        let lower = text.lowercased()
        guard !lower.isEmpty else { return nil }

        // 归档关键词(不需要提醒)
        let archiveKeywords = ["记一下", "记下就行", "备忘", "以后再说", "不用提醒", "存一下", "just note", "fyi", "随便记", "先记下", "不重要", "note this"]
        if archiveKeywords.contains(where: { lower.contains($0) }) {
            return .archive
        }

        // 今天关键词
        let todayKeywords = [
            "今天", "今晚", "今天之内", "今天前", "今天内", "下班前", "下班之前",
            "eod", "end of day", "today", "tonight", "before 5", "before 6",
            "今儿", "今儿个", "马上", "立刻", "等会儿", "傍晚", "晚点", "asap"
        ]
        if todayKeywords.contains(where: { lower.contains($0) }) {
            return .today
        }

        // 本周关键词
        let weekKeywords = [
            "本周", "这周", "这星期", "周末前", "周五前", "this week", "by friday", "eow",
            "这礼拜", "礼拜前", "礼拜五前", "end of week", "eow"
        ]
        if weekKeywords.contains(where: { lower.contains($0) }) {
            return .thisWeek
        }

        // 3 天内关键词(含"明天""后天"也归到 threeDays 档)
        let threeDaysKeywords = [
            "3 天", "三天", "3天", "几天", "两三天", "2-3 天", "两天", "两天内",
            "明天", "后天", "大后天", "近几天", "in 3 days", "by tomorrow", "couple days",
            "明早", "明儿", "明儿个", "过两天", "过几天", "这两天", "这几天", "礼拜内", "day after tomorrow"
        ]
        if threeDaysKeywords.contains(where: { lower.contains($0) }) {
            return .threeDays
        }

        return nil
    }

    /// 识别"保存并走"的语音命令(任务 5)。
    static func hasSaveCommand(_ text: String) -> Bool {
        let lower = text.lowercased()
        let keys = ["保存并", "存并", "save and", "saveand"]
        return keys.contains { lower.contains($0) }
    }

    /// 判断转写质量是否差到应尝试另一种语言识别(任务 11)。
    /// 两种情况认为差:文本太短,或 ASCII 占比过高(说明可能把英文当中文识别了)。
    static func transcriptionLikelyWrongLanguage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 4 { return true }
        let total = trimmed.unicodeScalars.count
        guard total > 0 else { return true }
        let ascii = trimmed.unicodeScalars.filter { $0.isASCII && !$0.properties.isWhitespace }.count
        let ratio = Double(ascii) / Double(total)
        // 纯英文但把它当中文识别 → 可能全是奇怪的汉字;ratio 接近 0
        // 但也可能实际是英文在中文识别器下输出拉丁字母混乱。难分。
        // 保守:ratio 在 0.3-0.7 中间偏"混乱"时认为差
        return ratio > 0.7 && total < 20
    }
}
