//
//  InspectionSessionManager.swift
//  SiteNote
//
//  v1.4 巡检 session 状态机(Engineer 视角核心)。
//
//  概念:
//  - 一次"巡检 session" = 一条 draft 状态的 InspectionReport
//  - session 期间录的每条 Note,自动绑 Note.inspectionSessionID = report.id
//  - 同时同步追加到 report.noteIDs(冗余索引,便于 PDF builder + 报告详情列出)
//  - 结束 session → report 状态变 submitted,生成 PDF 归档
//
//  并发 / 持久化:
//  - 同时只有 1 个 active session(物理事实:工程师一时间在一个工地)
//  - currentSessionID 持久化到 UserDefaults,app 重启不丢
//  - 午夜自动结束未结束 session — 主屏次日打开会显示"上次未结束"恢复 banner
//
//  集成点:
//  - HomeViewModel.commitDirectly() → 录音保存时调 attachIfNeeded
//  - StartInspectionSheet → 调 start(...)
//  - EndInspectionSheet → 调 end(...)
//  - EngineerScheduleView 的 [▶ 开始巡检] → 调 startFromSchedule(...)
//  - InspectionSessionBanner(顶部 sticky)→ 观察 currentSessionID
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class InspectionSessionManager {
    static let shared = InspectionSessionManager()

    /// 当前进行中 session 对应的 InspectionReport.id;nil = 没在巡检。
    private(set) var currentSessionID: UUID? {
        didSet {
            // 持久化:app 重启 / 切到后台再回 都能恢复
            if let id = currentSessionID {
                UserDefaults.standard.set(id.uuidString, forKey: Self.persistKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.persistKey)
            }
        }
    }

    private static let persistKey = "inspection.session.currentID.v1"

    private init() {
        // 从 UserDefaults 恢复
        if let str = UserDefaults.standard.string(forKey: Self.persistKey),
           let id = UUID(uuidString: str) {
            self.currentSessionID = id
        } else {
            self.currentSessionID = nil
        }
    }

    /// 当前 session 是否 active(currentSessionID 非空)。
    var isActive: Bool { currentSessionID != nil }

    // MARK: - Start

    /// 启动新 session。返回新建的 InspectionReport(draft 态)。
    /// caller 负责把 modelContext 传进来(view 层 @Environment 获取)。
    /// 报告号自动生成 — caller 可以接受默认或改 report.reportNo 后再 save。
    @discardableResult
    func start(
        siteTag: String,
        projectNo: String,
        projectName: String,
        clientName: String,
        address: String,
        inspectionType: String,
        defaultAttn: String,
        in modelContext: ModelContext
    ) -> InspectionReport {
        // 防呆:已有 session → 先 cancel 旧的
        if currentSessionID != nil {
            cancel()
        }

        let report = InspectionReport()
        report.projectNo = projectNo
        report.project = projectName
        report.client = clientName
        report.location = address
        report.inspectionType = inspectionType
        report.attn = defaultAttn
        report.reportNo = generateReportNo()
        report.statusRaw = InspectionStatus.draft.rawValue
        report.reportDate = Date()

        modelContext.insert(report)
        try? modelContext.save()

        currentSessionID = report.id
        return report
    }

    /// 从 SiteVisitSchedule 启动 session — 一键开巡检,字段从 schedule 关联的工地预设带过来。
    @discardableResult
    func startFromSchedule(
        _ schedule: SiteVisitSchedule,
        siteTag: String,
        preset: SitePreset?,
        defaultAttn: String,
        in modelContext: ModelContext
    ) -> InspectionReport {
        let report = start(
            siteTag: siteTag,
            projectNo: preset?.projectNo ?? "",
            projectName: preset?.projectName ?? schedule.title,
            clientName: preset?.clientName ?? "",
            address: preset?.address ?? "",
            inspectionType: preset?.defaultInspectionType ?? "",
            defaultAttn: defaultAttn,
            in: modelContext
        )
        _ = siteTag  // 暂未存 siteTag 到 report,字段名待对齐;先 silence warning
        // 双向关联:schedule.linkedReportID = report.id,完成后 schedule 状态也 mark
        schedule.linkedReportID = report.id
        try? modelContext.save()
        return report
    }

    // MARK: - Attach Note

    /// 录音/拍照保存 note 后,如果有 active session,把 note 绑过去。
    /// 同时追加到 report.noteIDs。
    func attachIfNeeded(noteID: UUID, in modelContext: ModelContext) {
        guard let sid = currentSessionID else { return }
        // 把 note 的 sessionID 写上
        let noteDesc = FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == noteID })
        if let note = try? modelContext.fetch(noteDesc).first {
            note.inspectionSessionID = sid
        }
        // 同步 report.noteIDs(去重)
        let reportDesc = FetchDescriptor<InspectionReport>(
            predicate: #Predicate<InspectionReport> { $0.id == sid }
        )
        if let report = try? modelContext.fetch(reportDesc).first,
           !report.noteIDs.contains(noteID) {
            report.noteIDs.append(noteID)
        }
        try? modelContext.save()
    }

    // MARK: - End

    /// 结束 session — mark report 为 submitted,清 currentSessionID。
    /// PDF 生成 + 邮件发送在 caller(EndInspectionSheet)里做,这里只管状态机。
    /// 返回结束的 report(给 caller 用于跳报告详情)。
    @discardableResult
    func end(in modelContext: ModelContext) throws -> InspectionReport? {
        guard let sid = currentSessionID else { return nil }
        let desc = FetchDescriptor<InspectionReport>(
            predicate: #Predicate<InspectionReport> { $0.id == sid }
        )
        let report = try modelContext.fetch(desc).first
        if let report {
            report.statusRaw = InspectionStatus.submitted.rawValue
            report.updatedAt = Date()
            // 关联的 schedule 也 mark completed
            if let scheduleID = report.id as UUID? {
                let sDesc = FetchDescriptor<SiteVisitSchedule>(
                    predicate: #Predicate<SiteVisitSchedule> { $0.linkedReportID == scheduleID }
                )
                if let sch = try? modelContext.fetch(sDesc).first {
                    sch.statusRaw = ScheduleStatus.completed.rawValue
                    sch.completedAt = Date()
                }
            }
            try modelContext.save()
        }
        currentSessionID = nil
        return report
    }

    /// 取消 session,但**不删** report(可能用户已经录了 notes 想保留为草稿)。
    /// 只是把 manager 状态机 detach。
    func cancel() {
        currentSessionID = nil
    }

    // MARK: - Current report 查询

    /// 获取当前 session 对应的 InspectionReport(若有)。
    func currentReport(in modelContext: ModelContext) -> InspectionReport? {
        guard let sid = currentSessionID else { return nil }
        let desc = FetchDescriptor<InspectionReport>(
            predicate: #Predicate<InspectionReport> { $0.id == sid }
        )
        return try? modelContext.fetch(desc).first
    }

    // MARK: - 报告号生成

    /// 自动报告号 — `SVR-yyyy-NNN`,NNN 是本年序号。
    /// 简单实现:用 UserDefaults 计数器 + 年份重置。生产环境同步可能撞号,Phase 2+ 改 CloudKit。
    private func generateReportNo() -> String {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        let yearKey = "inspection.session.lastYear"
        let counterKey = "inspection.session.counter"

        let lastYear = UserDefaults.standard.integer(forKey: yearKey)
        var counter = UserDefaults.standard.integer(forKey: counterKey)
        if lastYear != year {
            counter = 0
            UserDefaults.standard.set(year, forKey: yearKey)
        }
        counter += 1
        UserDefaults.standard.set(counter, forKey: counterKey)

        return String(format: "SVR-%04d-%03d", year, counter)
    }
}
