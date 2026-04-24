//
//  NotificationScheduleTests.swift
//  SiteNoteTests
//
//  测 NotificationService.computeSchedule 的纯函数行为。不接触 UNUserNotificationCenter。
//

import XCTest
@testable import SiteNote

final class NotificationScheduleTests: XCTestCase {

    /// 固定配置,便于断言。
    private let cfg = NotificationService.ScheduleConfig.defaultForTests

    /// 构造一个测试用 now:2026-04-21 12:00。
    private func fixedNow() -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 4
        comps.day = 21
        comps.hour = 12
        return Calendar.current.date(from: comps)!
    }

    /// 构造一个相对 now 的 dueDate。
    private func dueDate(daysFromNow: Int, atHour hour: Int = 23) -> Date {
        let cal = Calendar.current
        let now = fixedNow()
        let shifted = cal.date(byAdding: .day, value: daysFromNow, to: now)!
        return cal.date(bySettingHour: hour, minute: 59, second: 59, of: shifted)!
    }

    private func input(
        daysFromNow: Int,
        isHazard: Bool = false,
        transcription: String = "测试 note"
    ) -> NotificationService.ScheduleInput {
        .init(
            noteID: UUID(),
            dueDate: dueDate(daysFromNow: daysFromNow),
            transcription: transcription,
            isHazard: isHazard
        )
    }

    // MARK: - 非隐患:每天 1 次,最多 7 天

    func test_normal_dueToday_hasOneSlotTomorrowMorning() {
        // due 今天 23:59,now 12:00,早 7:30 已过。Day 0 的 7:30 < now 跳过。
        // Day 1 的 7:30 开始算。
        let items = NotificationService.computeSchedule(
            for: input(daysFromNow: 0),
            now: fixedNow(),
            config: cfg
        )
        // 7 天(Day 1-7)每天 1 次 = 7 条
        XCTAssertEqual(items.count, cfg.normalMaxSlots)
    }

    func test_normal_dueInFuture_slotsAreAfterNow() {
        let now = fixedNow()
        let items = NotificationService.computeSchedule(
            for: input(daysFromNow: 3),
            now: now,
            config: cfg
        )
        XCTAssertFalse(items.isEmpty)
        for item in items {
            XCTAssertGreaterThan(item.fireDate, now, "fireDate should be strictly after now")
        }
    }

    func test_normal_respectsMaxSlots() {
        let items = NotificationService.computeSchedule(
            for: input(daysFromNow: 0),
            now: fixedNow(),
            config: cfg
        )
        XCTAssertLessThanOrEqual(items.count, cfg.normalMaxSlots)
    }

    // MARK: - 隐患:多时段 + 更长天数

    func test_hazard_hasMoreSlotsThanNormal() {
        let normal = NotificationService.computeSchedule(
            for: input(daysFromNow: 0, isHazard: false),
            now: fixedNow(),
            config: cfg
        )
        let hazard = NotificationService.computeSchedule(
            for: input(daysFromNow: 0, isHazard: true),
            now: fixedNow(),
            config: cfg
        )
        XCTAssertGreaterThan(hazard.count, normal.count)
    }

    func test_hazard_titleContainsHazardPrefix() {
        let items = NotificationService.computeSchedule(
            for: input(daysFromNow: 0, isHazard: true),
            now: fixedNow(),
            config: cfg
        )
        XCTAssertFalse(items.isEmpty)
        for item in items {
            XCTAssertTrue(item.title.contains("🚨"), "hazard item should have 🚨 in title: \(item.title)")
        }
    }

    func test_normal_titleHasNoHazardPrefix() {
        let items = NotificationService.computeSchedule(
            for: input(daysFromNow: 0, isHazard: false),
            now: fixedNow(),
            config: cfg
        )
        for item in items {
            XCTAssertFalse(item.title.contains("🚨"))
        }
    }

    // MARK: - Identifier 唯一性

    func test_allIdentifiersUnique() {
        let items = NotificationService.computeSchedule(
            for: input(daysFromNow: 0, isHazard: true),
            now: fixedNow(),
            config: cfg
        )
        let ids = items.map { $0.identifier }
        XCTAssertEqual(Set(ids).count, ids.count, "identifiers should all be unique")
    }

    // MARK: - body 回退

    func test_emptyTranscription_bodyFallsBackToGeneric() {
        let items = NotificationService.computeSchedule(
            for: input(daysFromNow: 2, transcription: ""),
            now: fixedNow(),
            config: cfg
        )
        XCTAssertFalse(items.isEmpty)
        for item in items {
            XCTAssertFalse(item.body.isEmpty)
        }
    }

    /// 隐私:推送 body 必须**不**含原始 transcription(锁屏脱敏)。
    func test_transcriptionNeverAppearsInBody() {
        let text = "钢筋质量抽查"
        let items = NotificationService.computeSchedule(
            for: input(daysFromNow: 2, transcription: text),
            now: fixedNow(),
            config: cfg
        )
        XCTAssertFalse(items.isEmpty)
        for item in items {
            XCTAssertFalse(
                item.body.contains(text),
                "推送 body 不应包含原始 transcription(锁屏脱敏)"
            )
        }
    }

    // MARK: - 过远的 dueDate 仍然有条目

    func test_farFuture_producesUpToMaxSlots() {
        let items = NotificationService.computeSchedule(
            for: input(daysFromNow: 30, isHazard: true),
            now: fixedNow(),
            config: cfg
        )
        XCTAssertLessThanOrEqual(items.count, cfg.hazardMaxSlots)
        XCTAssertGreaterThan(items.count, 0)
    }
}
