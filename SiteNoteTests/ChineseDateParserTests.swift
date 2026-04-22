//
//  ChineseDateParserTests.swift
//  SiteNoteTests
//
//  测 ChineseDateParser 的关键词匹配:deadline 推断、保存命令识别、语言错配。
//

import XCTest
@testable import SiteNote

final class ChineseDateParserTests: XCTestCase {

    // MARK: - parseDeadline

    func test_parseDeadline_empty_returnsNil() {
        XCTAssertNil(ChineseDateParser.parseDeadline(from: ""))
        XCTAssertNil(ChineseDateParser.parseDeadline(from: "   "))
    }

    func test_parseDeadline_noKeyword_returnsNil() {
        XCTAssertNil(ChineseDateParser.parseDeadline(from: "钢筋没到货"))
        XCTAssertNil(ChineseDateParser.parseDeadline(from: "脚手架松了"))
    }

    // 归档(优先级最高)
    func test_parseDeadline_archiveKeywords() {
        let samples = [
            "这个记一下就行",
            "先备忘",
            "以后再说",
            "just note this",
            "FYI: supplier delayed"
        ]
        for s in samples {
            XCTAssertEqual(ChineseDateParser.parseDeadline(from: s), .archive, "failed: \(s)")
        }
    }

    // 今天
    func test_parseDeadline_todayKeywords() {
        let samples = [
            "今天必须处理",
            "今晚之前要做完",
            "下班前搞定",
            "today EOD",
            "tonight 必须"
        ]
        for s in samples {
            XCTAssertEqual(ChineseDateParser.parseDeadline(from: s), .today, "failed: \(s)")
        }
    }

    // 本周
    func test_parseDeadline_weekKeywords() {
        let samples = [
            "本周内完成",
            "这周安排",
            "周末前",
            "by friday",
            "this week"
        ]
        for s in samples {
            XCTAssertEqual(ChineseDateParser.parseDeadline(from: s), .thisWeek, "failed: \(s)")
        }
    }

    // 3 天
    func test_parseDeadline_threeDaysKeywords() {
        let samples = [
            "3 天内做完",
            "三天内解决",
            "两三天搞定",
            "明天开始",
            "后天交"
        ]
        for s in samples {
            XCTAssertEqual(ChineseDateParser.parseDeadline(from: s), .threeDays, "failed: \(s)")
        }
    }

    // 优先级:archive > today > thisWeek > threeDays
    func test_parseDeadline_archiveBeatsToday() {
        let s = "今天先备忘,以后再说"
        XCTAssertEqual(ChineseDateParser.parseDeadline(from: s), .archive)
    }

    func test_parseDeadline_todayBeatsWeek() {
        let s = "今天处理,不要等到本周"
        XCTAssertEqual(ChineseDateParser.parseDeadline(from: s), .today)
    }

    // MARK: - hasSaveCommand

    func test_hasSaveCommand_positive() {
        XCTAssertTrue(ChineseDateParser.hasSaveCommand("保存并今天处理"))
        XCTAssertTrue(ChineseDateParser.hasSaveCommand("存并归档"))
        XCTAssertTrue(ChineseDateParser.hasSaveCommand("save and remind tomorrow"))
    }

    func test_hasSaveCommand_negative() {
        XCTAssertFalse(ChineseDateParser.hasSaveCommand("钢筋没到货"))
        XCTAssertFalse(ChineseDateParser.hasSaveCommand("记录一下"))
        XCTAssertFalse(ChineseDateParser.hasSaveCommand(""))
    }

    // MARK: - transcriptionLikelyWrongLanguage

    func test_wrongLanguage_veryShort_returnsTrue() {
        XCTAssertTrue(ChineseDateParser.transcriptionLikelyWrongLanguage(""))
        XCTAssertTrue(ChineseDateParser.transcriptionLikelyWrongLanguage("ab"))
        XCTAssertTrue(ChineseDateParser.transcriptionLikelyWrongLanguage("好"))
    }

    func test_wrongLanguage_normalChinese_returnsFalse() {
        XCTAssertFalse(ChineseDateParser.transcriptionLikelyWrongLanguage("钢筋没有到货,下午要处理"))
    }

    func test_wrongLanguage_heavyASCII_returnsTrue() {
        // 17 字全 ASCII(wkd)应该被认为可能语言错
        XCTAssertTrue(ChineseDateParser.transcriptionLikelyWrongLanguage("hello world abc"))
    }
}
