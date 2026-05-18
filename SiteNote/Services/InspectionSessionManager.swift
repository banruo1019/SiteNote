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

        let trimmedSiteTag = siteTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        // project 空时用 address/siteTag 兜底,避免「未填项目」占位
        let trimmedProject = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedProject = trimmedProject.isEmpty ? (trimmedAddress.isEmpty ? trimmedSiteTag : address) : projectName
        // **R6 关键修**:siteTag 独立字段,location 维持 address 语义。
        // 之前用 location 兜 siteTag → PDF 把 "Sydney" 当 address 渲染。改:报告专门加 siteTag 字段。
        let report = InspectionReport()
        report.siteTag = trimmedSiteTag.isEmpty ? nil : trimmedSiteTag
        report.projectNo = projectNo
        report.project = resolvedProject
        report.client = clientName
        report.location = address  // 严格按用户输入,不再用 siteTag 兜
        report.inspectionType = inspectionType
        report.attn = defaultAttn
        report.reportNo = generateReportNo(projectNo: projectNo, in: modelContext)
        report.statusRaw = InspectionStatus.draft.rawValue
        report.reportDate = Date()
        // 团队协作:记录创建者 CloudKit 用户 ID,Owner 视角下用来区分谁创建的报告。
        // 本地未启用 iCloud → currentUserRecordName 为 nil → 写空字符串(视为"我"/单机)。
        report.createdByUserID = ICloudSyncConfig.shared.currentUserRecordName ?? ""
        // 工程师签字默认 = 设置里「我的名字」(InspectionFormView 里仍可手动改)。
        let signatureName = UserProfileManager.shared.userDisplayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !signatureName.isEmpty {
            report.engineerName = signatureName
        }

        modelContext.insert(report)
        try? modelContext.save()
        // 团队场景:把新 report 镜像到 share zone,owner 能看到 member 创建的,反之亦然
        Task { await TeamDataMirrorService.shared.mirrorReport(report, in: modelContext) }

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
        // 双向关联:schedule.linkedReportID = report.id,完成后 schedule 状态也 mark
        schedule.linkedReportID = report.id
        try? modelContext.save()
        // **R3#7**:`start()` 里已 fire-and-forget mirrorReport;这里再 fire-and-forget mirrorSchedule。
        // 两个 Task 都 enqueue 到 @MainActor TeamDataMirrorService,串行执行,但 Task 队列顺序由
        // Swift 决定,可能 schedule 先于 report 到 cloud → Member 拉到 dangling linkedReportID。
        // 改:把 schedule mirror 放进一个 Task,内部 await 先确保 report mirror 完成再 mirror schedule。
        let captured = (schedule: schedule, report: report, ctx: modelContext)
        Task {
            await TeamDataMirrorService.shared.mirrorReport(captured.report, in: captured.ctx)
            await TeamDataMirrorService.shared.mirrorSchedule(captured.schedule, in: captured.ctx)
        }
        return report
    }

    // MARK: - Attach Note

    /// 录音/拍照保存 note 后,如果有 active session,把 note 绑过去。
    /// 同时追加到 report.noteIDs。
    /// **R3#4**:把 active session 的 siteTag 写到 note,否则 inspection 中录的 note 没工地标签,
    /// PDF / noteSnapshot / 列表分组全错位。Engineer 心智:录音时已经在某个工地 session 里,
    /// note 默认就该绑这个工地。
    func attachIfNeeded(noteID: UUID, in modelContext: ModelContext) {
        guard let sid = currentSessionID else { return }
        // 拉 report 先(为了 sessionSiteTag 推导)
        let reportDesc = FetchDescriptor<InspectionReport>(
            predicate: #Predicate<InspectionReport> { $0.id == sid }
        )
        let report = try? modelContext.fetch(reportDesc).first
        // **R6 关键修**:用 report.siteTag(R6 新加字段)。
        // **不要**用 projectNo(项目号如"25159"不是工地名)/ location(PDF 当 address 渲染)
        // 当 fallback。老 record 没 siteTag → nil → 不回填(用户后续可手选)。
        let sessionSiteTag: String? = {
            if let s = report?.siteTag,
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s
            }
            return nil
        }()

        // 把 note 的 sessionID + siteTag 写上(siteTag 只在 note 当前没绑时回填,避免覆盖用户手选)
        let noteDesc = FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == noteID })
        if let note = try? modelContext.fetch(noteDesc).first {
            note.inspectionSessionID = sid
            if (note.siteTag ?? "").isEmpty, let tag = sessionSiteTag {
                note.siteTag = tag
            }
        }
        // 同步 report.noteIDs(去重)
        if let report,
           !report.noteIDs.contains(noteID) {
            report.noteIDs.append(noteID)
            report.updatedAt = Date()
            try? modelContext.save()
            Task { await TeamDataMirrorService.shared.mirrorReport(report, in: modelContext) }
            return
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
            var changedSchedule: SiteVisitSchedule? = nil
            if let scheduleID = report.id as UUID? {
                let sDesc = FetchDescriptor<SiteVisitSchedule>(
                    predicate: #Predicate<SiteVisitSchedule> { $0.linkedReportID == scheduleID }
                )
                if let sch = try? modelContext.fetch(sDesc).first {
                    sch.statusRaw = ScheduleStatus.completed.rawValue
                    sch.completedAt = Date()
                    changedSchedule = sch
                }
            }
            try modelContext.save()
            Task { await TeamDataMirrorService.shared.mirrorReport(report, in: modelContext) }
            if let sch = changedSchedule {
                Task { await TeamDataMirrorService.shared.mirrorSchedule(sch, in: modelContext) }
            }
        }
        currentSessionID = nil
        return report
    }

    /// 取消 session,但**不删** report(可能用户已经录了 notes 想保留为草稿)。
    /// 只是把 manager 状态机 detach。
    func cancel() {
        currentSessionID = nil
    }

    /// "暂存为草稿" — 把 session 从 manager 上 detach,但 report 保持 .draft 状态
    /// (没 mark .submitted),用户之后可以从「报告」Tab 草稿段点进去用 resume(...)
    /// 继续巡检。和 cancel() 行为相同,只是语义上区分:这是用户主动选了"先不发"。
    func suspendAsDraft() {
        currentSessionID = nil
    }

    // MARK: - Resume

    /// 把指定的 .draft report 重新挂回当前 session,让 banner 重新出现、
    /// 后续录制的 notes 自动 attach。用户从「报告」Tab 草稿点「继续巡检」时调用。
    ///
    /// 行为:
    /// - 如果当前已有别的 active session,先 cancel(防止两份冲突)。
    /// - 若 report 状态不是 .draft,强制改回 .draft(用户明确说要继续录)。
    /// - currentSessionID = report.id,持久化 UserDefaults 由 didSet 自动完成。
    func resume(report: InspectionReport, in modelContext: ModelContext) {
        if currentSessionID != nil, currentSessionID != report.id {
            cancel()
        }
        if report.statusRaw != InspectionStatus.draft.rawValue {
            report.statusRaw = InspectionStatus.draft.rawValue
            report.submittedAt = nil
            report.updatedAt = Date()
            try? modelContext.save()
            Task { await TeamDataMirrorService.shared.mirrorReport(report, in: modelContext) }
        }
        currentSessionID = report.id
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

    /// 启动时自愈:currentSessionID 持久化在 UserDefaults,但对应的 InspectionReport
    /// 可能在 SwiftData 里查不到(被「清空所有内容」删了 / 数据迁移丢了 / 用户从备份还原后 mismatch)。
    /// 这种 ghost session 会让主屏卡在 active 态但 Banner 不渲染 → 用户出不去。
    /// 在 RecordView/EngineerScheduleView 的 .task 调一下,清掉孤儿 ID。
    @discardableResult
    func validateOrCancel(in modelContext: ModelContext) -> Bool {
        guard currentSessionID != nil else { return true }
        if currentReport(in: modelContext) != nil { return true }
        // 孤儿:UserDefaults 有 ID,SwiftData 没 report → 自动清。
        currentSessionID = nil
        return false
    }

    // MARK: - 报告号生成

    /// 自动报告号 — 团队场景下要避免 owner 和 member 各自从 1 开始撞号。
    ///
    /// 策略(优先级):
    /// 1. 有 projectNo → 走 `ReportNumbering.nextNumber(projectNo:existingNumbers:)`
    ///    基于本机 SwiftData 里所有(包含 mirror 进来的别人创建的)同 projectNo 的 reportNo
    ///    取 max visitIndex + 1,格式 `SVR{projectNo}.{NN}A`。
    /// 2. 没 projectNo → 退化到 `SVR-YYYY-NNN`,NNN 基于本机 SwiftData 里所有同 prefix
    ///    `SVR-YYYY-` 的最大 NNN + 1(同样会把 mirror 进来的算进去)。
    ///
    /// 因为 reportNo 在 EndInspectionSheet 和 InspectionFormView 都可编辑,撞号时
    /// 用户能改,这里只保证大概率不撞。
    private func generateReportNo(projectNo: String, in modelContext: ModelContext) -> String {
        let trimmedProj = projectNo.trimmingCharacters(in: .whitespacesAndNewlines)
        let allReports = (try? modelContext.fetch(FetchDescriptor<InspectionReport>())) ?? []
        let existingNumbers = allReports
            .map { $0.reportNo.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !trimmedProj.isEmpty {
            return ReportNumbering.nextNumber(projectNo: trimmedProj, existingNumbers: existingNumbers)
        }

        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        let prefix = String(format: "SVR-%04d-", year)
        let nextSeq = existingNumbers
            .filter { $0.hasPrefix(prefix) }
            .compactMap { Int($0.dropFirst(prefix.count)) }
            .max()
            .map { $0 + 1 } ?? 1
        return String(format: "%@%03d", prefix, nextSeq)
    }
}
