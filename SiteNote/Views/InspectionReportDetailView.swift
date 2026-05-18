//
//  InspectionReportDetailView.swift
//  SiteNote
//
//  Engineer 报告资源库的 detail 页 — 从 EngineerReportsView 的列表行点进来。
//
//  只读 + 4 个操作:重新预览 PDF / 再发一次邮件 / 复制成新巡检 / 删除。
//  v1.4 之前用户从邮箱回头查报告时只看到 PDF,没有"在 app 里看包含哪些 notes"
//  的入口。这个页填上这个缺口:
//    - 顶部"报告信息"段:键值对显示 project / projectNo / type / date / 状态
//      (草稿 vs 已提交)+ 邮件状态(report.attn 非空近似为"已发"——和列表行
//      用同一近似口径,不重新查 ShareLog 表,保持便宜)
//    - 中段"包含的 Notes"段:按 noteIDs 过滤全部 notes,复用 NoteTimelineRow,
//      和"记" Tab 视觉一致(避免设计漂移)
//    - 底部"操作"段:4 个 1px Ink.line 描边白底胶囊按钮
//
//  设计纪律:
//    - 跟 EngineerSettingsRoot 同款 cardContainer + section header(灰小段头)
//    - 白底 Ink.bg + 1px Ink.line 描边,字号 11/14/11 三档
//    - 字符串走 String(localized:..., locale: AppLanguageManager.currentLocale)
//    - "复制成新巡检"先弹 confirmation alert,确认后才 start session,绝不静默跳
//    - 删除走 soft delete(deletedAt = Date()),lastPDFPath 不删 — 用户可能想保留
//      归档的 PDF(ReportArchiveService 单独管理)
//

import SwiftUI
import SwiftData
import PDFKit
import QuickLook
import MessageUI
import os

struct InspectionReportDetailView: View {
    private static let logger = Logger(subsystem: "com.banruo.sitenote", category: "InspectionReportDetail")
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 入参:从列表行传进来的 report。SwiftData 引用,字段变化会自动反映。
    let report: InspectionReport

    /// 拉全部 note 再过滤 — SwiftData `#Predicate` 内对捕获 `Set<UUID>.contains`
    /// 兼容性不稳(参考 EndInspectionSheet.fetchSessionNotes 的注释)。Session 通常
    /// < 50 条,in-memory 过滤代价可忽略。
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.createdAt,
        order: .reverse
    ) private var allNotes: [Note]

    // MARK: - State

    /// 异步生成的 PDF 临时 URL(预览或再发邮件时复用)。
    @State private var pdfURL: URL?
    /// 正在生成 PDF 中,按钮 disabled。
    @State private var isBuildingPDF: Bool = false
    /// QuickLook 预览开关。
    @State private var showsPreview: Bool = false
    /// MFMail 撰写开关。
    @State private var showsMailComposer: Bool = false
    /// "复制成新巡检" 确认弹窗开关。
    @State private var showsDuplicateConfirm: Bool = false
    /// "删除"确认弹窗开关。
    @State private var showsDeleteConfirm: Bool = false
    /// "标记为已发送"确认弹窗开关。
    @State private var showsMarkSubmittedConfirm: Bool = false
    /// MFMail 用的附件占位(弹起前 prepare 一次)。
    @State private var pendingAttachment: MailComposeView.Attachment?
    /// 顶部错误提示(nil = 隐藏)。
    @State private var errorMessage: String?
    /// 设备无邮箱时给降级提示。
    @State private var showsCannotMailAlert: Bool = false

    private var locale: Locale { AppLanguageManager.currentLocale }

    /// 按 noteIDs 过滤 + 按 createdAt 倒序(同"记"Tab 的视觉默认)。
    private var noteList: [Note] {
        let ids = Set(report.noteIDs)
        return allNotes
            .filter { ids.contains($0.id) && $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                // 草稿 + 当前没有别的 active session → 显示主 CTA「继续巡检」。
                // 已经在巡检中(另一份 session)就藏起,避免用户误操作覆盖。
                if report.status == .draft {
                    continueInspectionCTA
                }
                reportInfoGroup
                notesGroup
                actionsGroup
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle(reportTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsPreview) {
            if let url = pdfURL {
                QuickLookPDFPreview(url: url)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showsMailComposer) {
            if let attachment = pendingAttachment {
                MailComposeView(
                    recipients: defaultRecipients,
                    subject: EmailService.subjectFor(report: report),
                    body: EmailService.bodyFor(report: report),
                    attachments: [attachment]
                ) { result, _ in
                    showsMailComposer = false
                    handleMailResult(result)
                }
            }
        }
        .alert(
            String(localized: "确定开始新巡检?", locale: locale),
            isPresented: $showsDuplicateConfirm
        ) {
            Button(String(localized: "取消", locale: locale), role: .cancel) { }
            Button(String(localized: "开始", locale: locale)) {
                duplicateAsNewSession()
            }
        } message: {
            // 用本报告的项目信息建一份新的 draft session;不复制 notes(那是新一次巡检了)。
            Text(String(
                localized: "会用 \(report.project) 的信息开一个新巡检 session,不复制原报告里的 notes。",
                locale: locale
            ))
        }
        .alert(
            String(localized: "删除这份报告?", locale: locale),
            isPresented: $showsDeleteConfirm
        ) {
            Button(String(localized: "取消", locale: locale), role: .cancel) { }
            Button(String(localized: "删除", locale: locale), role: .destructive) {
                performDelete()
            }
        } message: {
            Text(String(
                localized: "报告本身会移入垃圾桶。关联的 notes 不会删,已归档的 PDF 也会保留在「我的报告」。",
                locale: locale
            ))
        }
        .alert(
            String(localized: "当前设备未配置邮箱", locale: locale),
            isPresented: $showsCannotMailAlert
        ) {
            Button(String(localized: "知道了", locale: locale), role: .cancel) { }
        } message: {
            Text(String(
                localized: "请到 iOS 设置 → 邮件 添加账号后再试。",
                locale: locale
            ))
        }
        .alert(
            String(localized: "标记为已提交?", locale: locale),
            isPresented: $showsMarkSubmittedConfirm
        ) {
            Button(String(localized: "取消", locale: locale), role: .cancel) { }
            Button(String(localized: "标记", locale: locale)) {
                markAsSubmitted()
            }
        } message: {
            Text(String(
                localized: "确认你已经发过邮件了。报告会从草稿切换为已提交,团队成员能看到这次更新。",
                locale: locale
            ))
        }
    }

    // MARK: - 报告信息 section

    private var reportInfoGroup: some View {
        groupBlock(header: String(localized: "报告信息", locale: locale)) {
            cardContainer {
                kvRow(
                    label: String(localized: "项目", locale: locale),
                    value: nonEmpty(report.project)
                )
                cardDivider
                kvRow(
                    label: String(localized: "编号", locale: locale),
                    value: nonEmpty(report.projectNo)
                )
                cardDivider
                kvRow(
                    label: String(localized: "巡检类型", locale: locale),
                    value: nonEmpty(report.inspectionType)
                )
                cardDivider
                kvRow(
                    label: String(localized: "日期", locale: locale),
                    value: dateTimeString(for: report.reportDate)
                )
                // 团队场景:显示巡检员(report 创建人)。自己的 report / 老数据(空 owner)不显示这一行。
                if let creator = creatorDisplayName {
                    cardDivider
                    kvRow(
                        label: String(localized: "巡检员", locale: locale),
                        value: creator
                    )
                }
                cardDivider
                statusRow
                if let mailDetail = mailStatusDetail {
                    cardDivider
                    mailRow(detail: mailDetail)
                }
            }
        }
    }

    /// 反查 report 创建人显示名(TeamMember 表 by userID)。
    /// 自己的 / 老数据(空 owner) → nil(UI 不显示这一行)。
    private var creatorDisplayName: String? {
        let owner = report.createdByUserID
        let me = ICloudSyncConfig.shared.currentUserRecordName ?? ""
        guard !owner.isEmpty, owner != me else { return nil }
        // fetch TeamMember by userID
        let desc = FetchDescriptor<TeamMember>(
            predicate: #Predicate<TeamMember> { $0.userID == owner }
        )
        if let member = try? modelContext.fetch(desc).first,
           !member.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return member.displayName
        }
        return String(owner.prefix(6))
    }

    /// "状态"行:草稿/已提交 + 提交时间(submitted 才有)。
    private var statusRow: some View {
        HStack(spacing: 12) {
            Text(String(localized: "状态", locale: locale))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ink.fgDim)
                .frame(width: 84, alignment: .leading)
            HStack(spacing: 6) {
                Image(systemName: report.status == .submitted ? "checkmark.seal.fill" : "doc.badge.ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(report.status == .submitted ? Ink.fg2 : Ink.accentBlue)
                Text(report.status == .submitted
                     ? String(localized: "已提交", locale: locale)
                     : String(localized: "草稿", locale: locale))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.fg)
                if let submittedAt = report.submittedAt {
                    Text(submittedTimeString(submittedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// "发给"行:envelope + 收件人/公司 + 已发时间。
    /// 邮件状态目前没专门字段(parent 列表的 TODO 注释里有说明),用 report.attn
    /// 非空 + report.submittedAt 两个信号当近似;builder 信息有就显示公司。
    private func mailRow(detail: MailStatusDetail) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(localized: "发给", locale: locale))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ink.fgDim)
                .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "envelope")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.fg2)
                    Text(detail.recipientLine)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.fg)
                        .lineLimit(2)
                }
                if let timeLine = detail.timeLine {
                    Text(timeLine)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// 单条键值对行 — 灰键左、黑值右,值为空给"—"。
    private func kvRow(label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ink.fgDim)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Ink.fg)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Notes section

    /// Notes 段。本地有 Note 实体 → 走 NoteTimelineRow + 详情链接;
    /// 本地缺(团队场景:Owner 拉到 Foreman 的 report 但 Note 表跨账号不可见)→ 走
    /// `teamSnapshots` 显示文字证据(transcription / siteTag / 照片计数)。
    private var notesGroup: some View {
        let snapshots = report.noteSnapshots()
        let useSnapshots = noteList.isEmpty && !snapshots.isEmpty
        return groupBlock(
            header: String(
                localized: useSnapshots
                    ? "团队成员的现场记录(\(snapshots.count))"
                    : "包含的 Notes(\(noteList.count))",
                locale: locale
            )
        ) {
            cardContainer {
                if useSnapshots {
                    VStack(spacing: 0) {
                        ForEach(Array(snapshots.enumerated()), id: \.element.noteID) { idx, s in
                            snapshotRow(s, isLast: idx == snapshots.count - 1)
                        }
                    }
                } else if noteList.isEmpty {
                    emptyNotesHint
                } else {
                    VStack(spacing: 0) {
                        ForEach(noteList) { note in
                            // 用 destination-trailing-closure 而不是 NavigationLink(value:),
                            // 后者走 value-based navigation,SwiftData @Model 重建 destination 时
                            // note.modelContext 短暂为 nil → NoteDetailView 顶部 guard 立即 dismiss
                            // → 看起来"跳进去又跳回来"。直接持有 note reference 不走 value 系统。
                            NavigationLink {
                                NoteDetailView(note: note)
                            } label: {
                                NoteTimelineRow(note: note)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var emptyNotesHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "没有关联的 notes", locale: locale))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.fg)
            Text(String(
                localized: "可能是 notes 已被删除,或本报告就是空的草稿。",
                locale: locale
            ))
            .font(.system(size: 11))
            .foregroundStyle(Ink.fgDim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 团队 snapshot 行 — 跨账号 Owner 看到 Foreman 的文字证据。
    /// 不可点(没本地 Note 实体可跳)— 文案明示"完整照片需要 Foreman 设备 / 联系 Foreman"。
    @ViewBuilder
    private func snapshotRow(_ s: NoteSnapshot, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(timeStringHourMinute(s.createdAt))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.fgDim)
                    .monospacedDigit()
                if let tag = s.siteTag, !tag.isEmpty {
                    Text(tag)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Ink.card)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer(minLength: 0)
                if s.photoCount > 0 {
                    Label("\(s.photoCount)", systemImage: "photo")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Ink.fgDim)
                }
            }
            Text(s.transcription.isEmpty
                 ? String(localized: "(空记录)", locale: locale)
                 : s.transcription)
                .font(.system(size: 13))
                .foregroundStyle(Ink.fg)
                .multilineTextAlignment(.leading)
            if s.photoCount > 0 {
                Text(String(localized: "照片在 Foreman 设备,需要看请联系对方导出 PDF。", locale: locale))
                    .font(.system(size: 10))
                    .foregroundStyle(Ink.fgDim)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Ink.line).frame(height: 1).padding(.leading, 14)
            }
        }
    }

    // MARK: - 继续巡检 CTA(草稿态独占)

    /// 草稿 → 一键回到 session,继续录 notes。
    /// 黑底白字大号按钮,跟 EndInspectionSheet 的"确认完成"主按钮视觉一致。
    /// 当前另有 active session 时给灰色 hint(避免覆盖别的 in-progress 巡检)。
    private var continueInspectionCTA: some View {
        VStack(spacing: 8) {
            Button {
                resumeInspection()
            } label: {
                HStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(String(localized: "继续巡检", locale: locale))
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 16)
                .foregroundStyle(Ink.bg)
                .background(Ink.fg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // 次按钮:已经在 app 外发过邮件的用户,可以手动把草稿标为已提交。
            Button {
                showsMarkSubmittedConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 13, weight: .semibold))
                    Text(String(localized: "已发完邮件 · 标为已提交", locale: locale))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 12)
                .foregroundStyle(Ink.fg)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Ink.fg, lineWidth: 1)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Ink.bg))
                )
            }
            .buttonStyle(.plain)

            Text(String(
                localized: "回到「记」Tab 接着录,session 顶部 banner 会重新出现。完成后再点「完成巡检」决定是否发邮件。",
                locale: locale
            ))
            .font(.system(size: 11))
            .foregroundStyle(Ink.fgDim)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 继续巡检:重新挂 session → 跳「记」Tab → 关详情页。
    /// session manager.resume(...) 会把 currentSessionID 设回 report.id,
    /// banner 重新出现,RecordView.task 的 validateOrCancel 一查 currentReport 在
    /// 就不会被当 ghost 清掉。
    private func resumeInspection() {
        InspectionSessionManager.shared.resume(report: report, in: modelContext)
        AppRouter.shared.requestTab(.record)
        dismiss()
    }

    /// 手动把草稿标记为已提交 — 用户在 app 外发了邮件(直接 Mail.app / 截图分享 / 等)
    /// 之后想把状态从草稿改为已提交。同 handleMailResult .sent 分支:
    /// statusRaw → submitted,submittedAt = now,触发 mirror 让团队成员也看到。
    private func markAsSubmitted() {
        report.statusRaw = InspectionStatus.submitted.rawValue
        report.submittedAt = Date()
        report.updatedAt = Date()
        try? modelContext.save()
        let ctx = modelContext
        let r = report
        Task { await TeamDataMirrorService.shared.mirrorReport(r, in: ctx) }
    }

    // MARK: - 操作 section

    private var actionsGroup: some View {
        groupBlock(header: String(localized: "操作", locale: locale)) {
            VStack(spacing: 8) {
                actionRow(
                    icon: "doc.text.magnifyingglass",
                    title: String(localized: "重新预览 PDF", locale: locale),
                    isProcessing: isBuildingPDF && !showsMailComposer,
                    disabled: isBuildingPDF
                ) {
                    handlePreviewPDF()
                }
                actionRow(
                    // 草稿 = 首发(发完 status → .submitted);已提交 = 再发一次(status 不变)。
                    icon: "paperplane",
                    title: report.status == .draft
                        ? String(localized: "发送邮件", locale: locale)
                        : String(localized: "再发一次邮件", locale: locale),
                    isProcessing: isBuildingPDF && showsMailComposer == false && pendingAttachment != nil,
                    disabled: isBuildingPDF
                ) {
                    handleResendEmail()
                }
                actionRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: String(localized: "复制成新巡检", locale: locale),
                    isProcessing: false,
                    disabled: false
                ) {
                    showsDuplicateConfirm = true
                }
                actionRow(
                    icon: "trash",
                    title: String(localized: "删除(本地+iCloud)", locale: locale),
                    isProcessing: false,
                    disabled: false,
                    isDestructive: true
                ) {
                    showsDeleteConfirm = true
                }
            }
        }
    }

    /// 单条操作按钮 — 白底 1px Ink.line 描边,圆角 10。
    /// `isDestructive` 时 icon + 标题用 Ink.red。
    private func actionRow(
        icon: String,
        title: String,
        isProcessing: Bool,
        disabled: Bool,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 18)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isDestructive ? Ink.red : Ink.fg)
                        .frame(width: 18)
                }
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDestructive ? Ink.red : Ink.fg)
                Spacer()
                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.dim)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Ink.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Ink.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }

    // MARK: - 错误条 / building blocks

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Ink.red)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Ink.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Ink.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func groupBlock<Content: View>(
        header: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Ink.fgDim)
                .padding(.horizontal, 4)
            content()
        }
    }

    @ViewBuilder
    private func cardContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Ink.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Ink.line, lineWidth: 1)
        )
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(Ink.line)
            .frame(height: 1)
            .padding(.leading, 14)
    }

    // MARK: - 计算属性

    private var reportTitle: String {
        let trimmed = report.reportNo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return String(localized: "巡检报告", locale: locale)
    }

    /// 邮件状态详情。nil 表示"未发"——不显示这一行,避免误导用户。
    /// "已发"判定:report.attn 非空 + report.submittedAt 存在(submitted)。
    /// 同 EngineerReportsView.reportRow 的近似口径,等真正有 sent 字段后统一替换。
    private var mailStatusDetail: MailStatusDetail? {
        let attn = report.attn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attn.isEmpty, report.status == .submitted else { return nil }

        // 拼"姓名 (公司)"风格;v1.5:builderID 字段值经迁移后实际指向 Contact.id,
        // 通过 Contact.builderID 反查到 Builder 拿公司名。
        var recipient = attn
        if let id = report.builderID,
           let contact = ContactsStorage.find(idString: id),
           let builder = BuildersStorage.find(id: contact.builderID),
           !builder.name.isEmpty {
            recipient = "\(attn) (\(builder.name))"
        }

        // 时间用 submittedAt(近似认为提交时间 ≈ 邮件发送时间)
        let timeLine: String?
        if let submittedAt = report.submittedAt {
            timeLine = String(
                localized: "已发 \(timeStringHourMinute(submittedAt))",
                locale: locale
            )
        } else {
            timeLine = nil
        }
        return MailStatusDetail(recipientLine: recipient, timeLine: timeLine)
    }

    /// 拼默认收件人(再发邮件时用)。builderID 反查 BuildersStorage,空 → 空列表
    /// 让用户在 compose 内手填。
    private var defaultRecipients: [String] {
        EmailService.defaultRecipientsFor(report: report)
    }

    private func nonEmpty(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private func dateTimeString(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    private func timeStringHourMinute(_ date: Date) -> String {
        Formatters.hourMinute.string(from: date)
    }

    private func submittedTimeString(_ date: Date) -> String {
        // 同一天 → 只显示时间;跨天 → 带短日期
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return Formatters.hourMinute.string(from: date)
        }
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    // MARK: - Actions

    /// 预览 PDF:复用已有,缺则后台生成。
    private func handlePreviewPDF() {
        if pdfURL != nil {
            showsPreview = true
            return
        }
        errorMessage = nil
        isBuildingPDF = true
        Task {
            await buildPDF()
            if pdfURL != nil {
                showsPreview = true
            }
        }
    }

    /// 再发一次邮件:确保 PDF 存在 + 设备能发邮件 + 准备 attachment → 弹 MailCompose。
    private func handleResendEmail() {
        guard MailComposeView.canSendMail else {
            showsCannotMailAlert = true
            return
        }
        if let url = pdfURL {
            presentMailComposer(with: url)
            return
        }
        errorMessage = nil
        isBuildingPDF = true
        Task {
            await buildPDF()
            if let url = pdfURL {
                presentMailComposer(with: url)
            }
        }
    }

    /// 后台生成 PDF — 拉本报告 noteIDs 对应 notes,调 InspectionReportPDFBuilder。
    /// 失败设 errorMessage,成功写 pdfURL,主线程更新。
    @MainActor
    private func buildPDF() async {
        defer { isBuildingPDF = false }
        let notesForBuild = fetchNotesForBuild()
        do {
            let url = try await InspectionReportPDFBuilder.build(
                report: report,
                notes: notesForBuild
            )
            pdfURL = url
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 拉本报告 noteIDs 对应的 notes(包含已 soft-delete 的——历史 PDF 应该和当时一致)。
    /// 注:`allNotes` query 排除了 deletedAt,所以这里直接 fetch 全集兜底。
    private func fetchNotesForBuild() -> [Note] {
        let ids = report.noteIDs
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<Note>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { idSet.contains($0.id) }
    }

    /// 准备 attachment + 弹 MailCompose。
    private func presentMailComposer(with url: URL) {
        guard let raw = EmailService.loadPDFAttachment(at: url, reportNo: report.reportNo) else {
            errorMessage = String(
                localized: "PDF 文件无法读取,请稍后重试。",
                locale: locale
            )
            return
        }
        pendingAttachment = MailComposeView.Attachment(
            data: raw.data,
            mimeType: raw.mimeType,
            filename: raw.filename
        )
        errorMessage = nil
        showsMailComposer = true
    }

    /// MFMail 回调。.sent → 刷新 submittedAt;若当前是 .draft 则同步切到 .submitted
    /// (用户原话:发了邮件就不能叫草稿了)。其他不变。
    private func handleMailResult(_ result: MFMailComposeResult) {
        switch result {
        case .sent:
            report.submittedAt = Date()
            report.updatedAt = Date()
            if report.status == .draft {
                report.statusRaw = InspectionStatus.submitted.rawValue
            }
            // P1 #194:save 失败写日志 — 之前 try? 静默 → 发了邮件 UI 显示已提交但磁盘还是草稿
            do {
                try modelContext.save()
                // **Codex#7**:save 成功后 mirror report,团队成员视图才能看到状态变化。
                // 之前只 save 不 mirror → Member 端永远显示 draft。
                let ctx = modelContext
                let r = report
                Task { await TeamDataMirrorService.shared.mirrorReport(r, in: ctx) }
            } catch {
                Self.logger.error("handleMailResult sent save failed: \(error.localizedDescription)")
                errorMessage = String(
                    localized: "保存提交状态失败,请稍后手动改为已提交。",
                    locale: locale
                )
            }
        case .failed:
            errorMessage = String(
                localized: "邮件发送失败,请检查邮箱设置或网络后重试。",
                locale: locale
            )
        case .saved, .cancelled:
            break
        @unknown default:
            break
        }
    }

    /// 复制成新巡检:用当前 report 的元数据 start 一个新 draft session,然后:
    /// 1) 关掉本页(dismiss)
    /// 2) 通知 MainTabView 切到"记" Tab(用户去那里录新 notes)
    /// 注意 — 不复制 noteIDs(新巡检是新一次现场来的)。
    private func duplicateAsNewSession() {
        _ = InspectionSessionManager.shared.start(
            siteTag: report.projectNo,
            projectNo: report.projectNo,
            projectName: report.project,
            clientName: report.client,
            address: report.location,
            inspectionType: report.inspectionType,
            defaultAttn: report.attn,
            in: modelContext
        )
        // 跳回主屏录新 notes
        AppRouter.shared.requestTab(.record)
        dismiss()
    }

    /// 软删 — 移入垃圾桶,关联 notes / 归档 PDF 都不动。
    /// 团队场景:删 = 把 deletedAt 推 share zone,让团队其他成员看到该 report 被移走。
    /// 不 mirror 的话本地软删但 share zone 还在,下次 fetchAndSyncAll 又拉回本地。
    private func performDelete() {
        report.deletedAt = Date()
        report.updatedAt = Date()
        try? modelContext.save()
        let ctx = modelContext
        let r = report
        Task { await TeamDataMirrorService.shared.mirrorReport(r, in: ctx) }
        dismiss()
    }
}

// MARK: - 邮件状态描述

/// "发给"行的展示数据。recipientLine 必填(姓名/公司),timeLine 可选(没 submittedAt 时不显示)。
private struct MailStatusDetail {
    let recipientLine: String
    let timeLine: String?
}

// MARK: - QuickLook 包装

/// QuickLook 单 PDF 预览。和 EndInspectionSheet 里的 QuickLookPreview 是同款,
/// 但那个是 fileprivate,这里独立放一份避免跨文件可见性扩散。
/// 命名加 PDF 后缀防 type 冲突。
private struct QuickLookPDFPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}
