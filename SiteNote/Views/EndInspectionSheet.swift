//
//  EndInspectionSheet.swift
//  SiteNote
//
//  巡检 session 终点。Engineer 在顶部 banner 点 "✓ 完成巡检" → 弹本 sheet:
//    1. onAppear 后台异步生成 PDF(`InspectionReportPDFBuilder.build(report:notes:)`)
//    2. 展示缩略图 + 报告基本信息(报告号、工地、note/photo 数)
//    3. 选收件人:多选 BuildersStorage(默认勾 report.builderID 对应那位) + 临时邮箱手输
//    4. 两个主操作:
//         - "仅存档,不发邮件" → InspectionSessionManager.shared.end(in:) + 归档 PDF
//         - "发邮件并存档"     → 弹 MailComposer 发出后再 end + 归档
//
//  设计纪律:
//    - large detent,M1 极简白 + Ink.* tokens,白底纯黑字 + 1px 灰线
//    - 字符串走 String(localized:..., locale: AppLanguageManager.currentLocale)
//    - 绝不替用户发邮件——只填好草稿,用户在系统 MFMail 界面手动点 Send
//    - 邮件发送失败 / 用户取消 → 不 end session(给重试的机会)
//      但 "仅存档" 永远 end —— 那是用户的明确意图
//

import SwiftUI
import SwiftData
import PDFKit
import QuickLook
import MessageUI
import os

struct EndInspectionSheet: View {
    private static let logger = Logger(subsystem: "com.banruo.sitenote", category: "EndInspectionSheet")

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 当前 active session 对应的 InspectionReport(caller 取好传进来)。
    let report: InspectionReport

    /// 完成回调:(已归档/已 end 的 report, 归档后的本地 PDF URL — 可能 nil 表示生成失败但 session 仍然结束)
    var onCompleted: (InspectionReport, URL?) -> Void

    // MARK: - 状态

    /// v1.5:可选的 Contact 列表(ContactsStorage),onAppear 时一次性 load。
    /// Builder 列表用于反查公司名(显示在 row 上)。
    @State private var availableContacts: [Contact] = []
    @State private var availableBuilders: [Builder] = []

    /// 多选勾上的 Contact ID。默认匹配 report.builderID(legacy 字段名)
    /// 已被迁移到 Contact.id,不匹配就空集。
    @State private var selectedBuilderIDs: Set<UUID> = []

    /// 临时手输的邮箱(可选,不存到联系簿)。
    @State private var extraEmail: String = ""

    /// 后台生成出来的 PDF 临时 URL。
    @State private var generatedPDFURL: URL?

    /// 报告中纳入的 Notes(按 report.noteIDs 顺序排好,用于统计 + 传给 PDF builder)。
    @State private var sessionNotes: [Note] = []

    /// 缩略图(PDF 第一页 render 出来)。
    @State private var pdfThumbnail: UIImage?

    /// 生成中标记。控制按钮 disabled 和 ProgressView。
    @State private var isGenerating: Bool = false

    /// QuickLook 预览开关。
    @State private var showsPreview: Bool = false

    /// MFMail 撰写器开关。
    @State private var showsMailComposer: Bool = false

    /// 占位 attachment(为了让 MailComposeView 拿到 data,在弹起前 prepare 一次)。
    @State private var pendingAttachment: MailComposeView.Attachment?

    /// 顶部统一错误提示文本(nil 即不显示)。
    @State private var errorMessage: String?

    /// "仅存档" 按钮 in-flight,防止重入。
    @State private var isArchiving: Bool = false

    // MARK: - 可编辑的报告信息(用户确认时可改)
    /// onAppear 时从 report 拷过来,确认时写回 report 并重新生成 PDF。
    @State private var editedReportNo: String = ""
    @State private var editedProject: String = ""
    @State private var editedProjectNo: String = ""
    @State private var editedClient: String = ""
    @State private var editedLocation: String = ""
    @State private var editedInspectionType: String = ""
    @State private var editedAttn: String = ""

    // MARK: - 选项开关
    /// 是否发邮件给收件人。默认 on。
    @State private var sendMail: Bool = true

    /// 用户改过任何字段时设 true,确认时触发 PDF 重新生成。
    @State private var infoDirty: Bool = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        infoConfirmSection
                        Divider().background(Ink.line)
                        previewSection
                        Divider().background(Ink.line)
                        recipientsSection
                        Divider().background(Ink.line)
                        optionsSection
                        confirmActionSection
                        if let errorMessage {
                            errorBanner(errorMessage)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(Text(String(localized: "完成巡检", locale: AppLanguageManager.currentLocale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭", locale: AppLanguageManager.currentLocale)) {
                        dismiss()
                    }
                    .foregroundStyle(Ink.fg2)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: bootstrap)
        .sheet(isPresented: $showsPreview) {
            if let url = generatedPDFURL {
                QuickLookPreview(url: url)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showsMailComposer) {
            if let attachment = pendingAttachment {
                MailComposeView(
                    recipients: collectedRecipients,
                    subject: EmailService.subjectFor(report: report),
                    body: EmailService.bodyFor(report: report),
                    attachments: [attachment]
                ) { result, _ in
                    showsMailComposer = false
                    handleMailResult(result)
                }
            }
        }
    }

    // MARK: - Preview section(PDF 缩略图 + 报告基本信息)

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(String(localized: "PDF 预览", locale: AppLanguageManager.currentLocale))

            HStack(alignment: .top, spacing: 14) {
                pdfThumbCard
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "PDF 巡检报告", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Ink.fgDim)
                    Text(reportNoDisplay)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                        .lineLimit(1)
                    if !report.location.isEmpty {
                        Text(report.location)
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.fg2)
                            .lineLimit(2)
                    }
                    if !report.project.isEmpty {
                        Text(report.project)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.fgDim)
                            .lineLimit(1)
                    }
                    Text(statsLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.fgDim)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }

            previewLinkButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    /// PDF 缩略卡片 — 优先用渲染好的 PDF 首页;还没好就显 M1 占位线条(同 ReportsView.pdfThumb)。
    @ViewBuilder
    private var pdfThumbCard: some View {
        if let img = pdfThumbnail {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 96)
                .background(Ink.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Ink.line, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        } else {
            // 占位 — 跟 ReportsView 同款 M1 灰线条
            ZStack {
                placeholderThumb
                if isGenerating {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
    }

    /// M1 灰线条占位 — 跟 ReportsView 的 pdfThumb 视觉一致。
    private var placeholderThumb: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Ink.fg).frame(height: 6)
                .clipShape(RoundedRectangle(cornerRadius: 1))
            Rectangle().fill(Ink.line2).frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
            Rectangle().fill(Ink.line2).frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1))
            Rectangle().fill(Ink.line2).frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 18)
            Rectangle().fill(Ink.card2).frame(height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            Rectangle().fill(Ink.line2).frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1))
            Rectangle().fill(Ink.line2).frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 24)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 72, height: 96)
        .background(Ink.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Ink.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    /// "预览完整 PDF >" — 没生成完就 disable。
    private var previewLinkButton: some View {
        Button {
            guard generatedPDFURL != nil else { return }
            showsPreview = true
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "预览完整 PDF", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 14, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(generatedPDFURL == nil ? Ink.fgDim : Ink.fg)
        }
        .buttonStyle(.plain)
        .disabled(generatedPDFURL == nil)
    }

    // MARK: - Recipients section(builder 多选 + 临时邮箱)

    private var recipientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(String(localized: "发送给", locale: AppLanguageManager.currentLocale))

            if siteContacts.isEmpty {
                // 本工地没绑联系人(或 SitePreset 反查匹配不到且 builders 簿也空)。
                Text(String(localized: "本工地没绑联系人,可在下方临时填邮箱;或到 设置 → 工地预设 给本工地绑联系人。",
                            locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.fgDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(siteContacts) { builder in
                        builderRow(builder)
                        if builder.id != siteContacts.last?.id {
                            Divider().background(Ink.line)
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Ink.line, lineWidth: 1)
                )
            }

            extraEmailField
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    /// 单条 Contact row — 复选框 + 名/公司/邮箱。
    private func builderRow(_ contact: Contact) -> some View {
        let isChecked = selectedBuilderIDs.contains(contact.id)
        let emailEmpty = contact.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let company = companyName(for: contact)
        return Button {
            toggleBuilder(contact.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(isChecked ? Ink.fg : Ink.dim)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(contact.name.isEmpty ? contact.email : contact.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Ink.fg)
                        if !company.isEmpty {
                            Text("(\(company))")
                                .font(.system(size: 12))
                                .foregroundStyle(Ink.fgDim)
                        }
                    }
                    Text(emailEmpty
                         ? String(localized: "(无邮箱)", locale: AppLanguageManager.currentLocale)
                         : contact.email)
                        .font(.system(size: 12))
                        .foregroundStyle(emailEmpty ? Ink.red : Ink.fgDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(emailEmpty)
    }

    /// 通过 Contact.builderID 反查公司名(显示用)。
    private func companyName(for contact: Contact) -> String {
        availableBuilders.first(where: { $0.id == contact.builderID })?.name ?? ""
    }

    /// "+ 临时邮箱" 手输行。
    private var extraEmailField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.system(size: 16))
                .foregroundStyle(Ink.fgDim)
            Text(String(localized: "临时邮箱:", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 13))
                .foregroundStyle(Ink.fg2)
            TextField(
                String(localized: "example@email.com", locale: AppLanguageManager.currentLocale),
                text: $extraEmail
            )
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .autocorrectionDisabled(true)
            .font(.system(size: 14))
            .foregroundStyle(Ink.fg)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Ink.line, lineWidth: 1)
        )
    }

    // MARK: - Actions section(仅存档 / 发邮件并存档)

    // MARK: - 报告信息确认(可改)

    /// 让用户确认 / 修正报告 header 字段。提交时写回 report 并重新生成 PDF。
    private var infoConfirmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(String(localized: "报告信息(可改后确认)", locale: AppLanguageManager.currentLocale))
            VStack(spacing: 0) {
                infoEditableRow(label: String(localized: "报告号", locale: AppLanguageManager.currentLocale),
                                text: $editedReportNo,
                                placeholder: report.reportNo)
                rowDivider
                infoEditableRow(label: String(localized: "项目名", locale: AppLanguageManager.currentLocale),
                                text: $editedProject)
                rowDivider
                infoEditableRow(label: String(localized: "项目编号", locale: AppLanguageManager.currentLocale),
                                text: $editedProjectNo)
                rowDivider
                infoEditableRow(label: String(localized: "客户", locale: AppLanguageManager.currentLocale),
                                text: $editedClient)
                rowDivider
                infoEditableRow(label: String(localized: "地址", locale: AppLanguageManager.currentLocale),
                                text: $editedLocation)
                rowDivider
                infoEditableRow(label: String(localized: "巡检类型", locale: AppLanguageManager.currentLocale),
                                text: $editedInspectionType)
                rowDivider
                infoEditableRow(label: String(localized: "默认收件人", locale: AppLanguageManager.currentLocale),
                                text: $editedAttn)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Ink.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    /// 单行 label + TextField 编辑器。
    /// placeholder:留空时 TextField 不显示占位文字;传 auto-generated reportNo 之类的可以
    /// 让用户清空字段后还能看到默认值预览。
    private func infoEditableRow(label: String, text: Binding<String>, placeholder: String = "") -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Ink.fgDim)
                .frame(width: 84, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.system(size: 14))
                .foregroundStyle(Ink.fg)
                .tint(Ink.fg)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .onChange(of: text.wrappedValue) { _, _ in infoDirty = true }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var rowDivider: some View {
        Rectangle().fill(Ink.line).frame(height: 1).padding(.leading, 14)
    }

    // MARK: - 选项 toggle(发邮件 / 团队共享)

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(String(localized: "选项", locale: AppLanguageManager.currentLocale))
            VStack(spacing: 0) {
                // 发送邮件
                Toggle(isOn: $sendMail) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "确认后发送邮件给收件人", locale: AppLanguageManager.currentLocale))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Ink.fg)
                        if sendMail, !collectedRecipients.isEmpty {
                            Text(collectedRecipients.joined(separator: ", "))
                                .font(.system(size: 11))
                                .foregroundStyle(Ink.fgDim)
                                .lineLimit(2)
                        } else if sendMail {
                            Text(String(localized: "下方勾选收件人或填临时邮箱", locale: AppLanguageManager.currentLocale))
                                .font(.system(size: 11))
                                .foregroundStyle(Ink.fgDim)
                        } else {
                            Text(String(localized: "保存为草稿,稍后从「报告」Tab 继续巡检或补发邮件",
                                        locale: AppLanguageManager.currentLocale))
                                .font(.system(size: 11))
                                .foregroundStyle(Ink.fgDim)
                        }
                    }
                }
                .tint(Ink.fg)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                rowDivider

                // v1.6:团队共享已经接通(由 TeamDataMirrorService 自动 mirror 到 share zone)
                // 这里不再需要 toggle,改为信息行告知用户。
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.fgDim)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "已自动共享给团队", locale: AppLanguageManager.currentLocale))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Ink.fg)
                        Text(String(localized: "团队成员在「报告 → 团队全部」段能看到此报告。无团队时此条不影响。",
                                    locale: AppLanguageManager.currentLocale))
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Ink.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - 单一确认按钮

    /// 取代原 [仅存档] [发邮件并存档] 两个按钮 — 用单一"确认完成巡检"按钮 + 上方 toggle 决定行为。
    private var confirmActionSection: some View {
        VStack(spacing: 8) {
            Button {
                handleConfirm()
            } label: {
                HStack(spacing: 8) {
                    Spacer()
                    if isGenerating || isArchiving {
                        ProgressView().tint(Ink.bg)
                        Text(String(localized: "处理中...", locale: AppLanguageManager.currentLocale))
                            .font(.system(size: 15, weight: .semibold))
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(confirmButtonLabel)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
                .foregroundStyle(Ink.bg)
                .background(canConfirm ? Ink.fg : Ink.dim)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!canConfirm)

            // 提示:如果 sendMail 开但没收件人,按钮会变灰 — 解释为什么
            if sendMail && collectedRecipients.isEmpty {
                Text(String(localized: "请先勾选收件人或填临时邮箱;或关掉「发送邮件」选项仅存档。",
                            locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    /// 按钮文案根据 toggle 状态动态变。
    /// 不发邮件时:报告**保持 .draft**,所以叫"暂存为草稿"更准确,
    /// 跟用户原话对齐:"未发邮件的巡检状态也不能叫已提交"。
    private var confirmButtonLabel: String {
        if sendMail {
            return String(localized: "确认完成巡检并发邮件", locale: AppLanguageManager.currentLocale)
        }
        return String(localized: "暂存为草稿(稍后再发)", locale: AppLanguageManager.currentLocale)
    }

    /// 是否能按"确认":PDF 没在生成 + 没在归档 + (不发邮件 OR 至少有 1 个有效收件人)
    private var canConfirm: Bool {
        guard !isGenerating, !isArchiving else { return false }
        if sendMail {
            return !collectedRecipients.isEmpty && MFMailComposeViewController.canSendMail()
        }
        return true
    }

    /// 顶部错误提示条(灰底红字一行,不抢戏)。
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Ink.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - 小工具:section label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Ink.fgDim)
    }

    // MARK: - Computed helpers

    /// 报告号显示文本(空时给"巡检报告(草稿)")。
    private var reportNoDisplay: String {
        let trimmed = report.reportNo.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(localized: "巡检报告(草稿)", locale: AppLanguageManager.currentLocale)
        }
        return trimmed
    }

    /// "3 条 notes · 5 张照片" 这种统计行。
    private var statsLine: String {
        let noteCount = sessionNotes.count
        let photoCount = sessionNotes.reduce(0) { $0 + $1.photoPaths.count }
        return String(
            localized: "\(noteCount) 条 notes · \(photoCount) 张照片",
            locale: AppLanguageManager.currentLocale
        )
    }

    /// 当前 report 对应 site 的联系人(v1.5 起从 ContactsStorage 拉,id 指 Contact)。
    /// 报告刚生成时 report.projectNo 已写入 — 用它 match SitePreset.projectNo。
    /// match 不到(老 report / 项目编号空 / 没绑联系人)→ 退回显示所有 contacts(降级)。
    private var siteContacts: [Contact] {
        let trimmed = report.projectNo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let preset = SitePresetStorage.load().first(where: { $0.projectNo == trimmed }),
              !preset.linkedContactIDs.isEmpty else {
            return availableContacts  // 降级:全列
        }
        let ids = Set(preset.linkedContactIDs)
        return availableContacts.filter { ids.contains($0.id) }
    }

    /// 当前要发的收件人邮箱列表(Contact 勾选 + 临时邮箱手输,合并去重)。
    /// **R11 修**:先 iterate siteContacts(UI 顺序优先),再补 selectedBuilderIDs 中**不在
    /// siteContacts 但在 availableContacts** 的 frozen 收件人(eg. report.builderID 指向的
    /// contact 已从 preset.linkedContactIDs 里移除,但 report 历史仍引用)。否则用户在 EndSheet
    /// 看到收件人勾选但实际邮件少了。
    private var collectedRecipients: [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for contact in siteContacts where selectedBuilderIDs.contains(contact.id) {
            let email = contact.email.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = email.lowercased()
            if !email.isEmpty, !seen.contains(lower) {
                out.append(email)
                seen.insert(lower)
            }
        }
        // R11 补:frozen builderID 不在 preset.linkedContactIDs 时,从 availableContacts 找
        let siteContactIDs = Set(siteContacts.map { $0.id })
        for id in selectedBuilderIDs where !siteContactIDs.contains(id) {
            if let c = availableContacts.first(where: { $0.id == id }) {
                let email = c.email.trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = email.lowercased()
                if !email.isEmpty, !seen.contains(lower) {
                    out.append(email)
                    seen.insert(lower)
                }
            }
        }
        let extra = extraEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidEmail(extra), !seen.contains(extra.lowercased()) {
            out.append(extra)
            seen.insert(extra.lowercased())
        }
        return out
    }

    /// "发邮件并存档" 是否可点。
    /// 条件:PDF 已生成 + 设备能发邮件 + 至少 1 个收件人。
    private var canSendMail: Bool {
        guard !isGenerating, generatedPDFURL != nil else { return false }
        guard MailComposeView.canSendMail else { return false }
        return !collectedRecipients.isEmpty
    }

    /// 最朴素邮箱格式判定:含 @ 且 @ 后有点。够拦绝大多数手滑,不假装是 RFC parser。
    private func isValidEmail(_ raw: String) -> Bool {
        guard let atIdx = raw.firstIndex(of: "@") else { return false }
        let after = raw[raw.index(after: atIdx)...]
        return after.contains(".")
    }

    // MARK: - Lifecycle bootstrap

    /// onAppear 触发:加载 contacts + fetch notes + 后台生成 PDF。
    private func bootstrap() {
        availableContacts = ContactsStorage.load()
        availableBuilders = BuildersStorage.load()

        // **R10 + R12 修(并集策略)**:
        // 单纯用 `report.builderID` 会丢 Start 时多选(report 只存第一个)。
        // 单纯用 `preset.defaultRecipientIDs` 会无视 Start 时用户的 explicit choice。
        // 取并集:preset.defaultRecipientIDs ∪ {report.builderID},然后过滤到本工地可见 contacts。
        // 用户在 EndSheet 仍能取消勾选。
        let trimmedProjectNo = report.projectNo.trimmingCharacters(in: .whitespacesAndNewlines)
        var initialIDs: Set<UUID> = []
        if !trimmedProjectNo.isEmpty,
           let preset = SitePresetStorage.load().first(where: { $0.projectNo == trimmedProjectNo }) {
            initialIDs.formUnion(preset.defaultRecipientIDs)
        }
        if let idString = report.builderID, let uuid = UUID(uuidString: idString) {
            initialIDs.insert(uuid)
        }
        // 过滤到 availableContacts 实际存在的(防引用已删除的 contact)
        let availableSet = Set(availableContacts.map { $0.id })
        selectedBuilderIDs = initialIDs.intersection(availableSet)

        // 初始化可编辑字段 — 用户改了 → infoDirty = true → 确认时重新生成 PDF
        editedReportNo = report.reportNo
        editedProject = report.project
        editedProjectNo = report.projectNo
        editedClient = report.client
        editedLocation = report.location
        editedInspectionType = report.inspectionType
        editedAttn = report.attn
        infoDirty = false

        // fetch 当前 session 的 notes(按 report.noteIDs 顺序排)
        sessionNotes = fetchSessionNotes()

        // 后台 task 生成 PDF + 缩略图
        guard generatedPDFURL == nil, !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        Task {
            await generatePDF()
        }
    }

    /// 把可编辑字段写回 report 实例(modelContext 自动跟踪保存)。
    /// reportNo 特殊:空字符串就保留原 auto-generated 值不动,避免用户误清空导致文件名丢失。
    private func applyEditsToReport() {
        let trimmedReportNo = editedReportNo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedReportNo.isEmpty {
            report.reportNo = trimmedReportNo
        }
        report.project = editedProject.trimmingCharacters(in: .whitespacesAndNewlines)
        report.projectNo = editedProjectNo.trimmingCharacters(in: .whitespacesAndNewlines)
        report.client = editedClient.trimmingCharacters(in: .whitespacesAndNewlines)
        report.location = editedLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        report.inspectionType = editedInspectionType.trimmingCharacters(in: .whitespacesAndNewlines)
        report.attn = editedAttn.trimmingCharacters(in: .whitespacesAndNewlines)
        report.updatedAt = Date()
        try? modelContext.save()
    }

    /// 单"确认完成巡检"入口 — 根据 toggle 状态决定行为路径:
    /// 1. 保存可编辑字段
    /// 2. 如有 dirty → 重新生成 PDF
    /// 3. 归档 PDF
    /// 4. sendMail on → 弹邮件撰写器,.sent 回调里 end session(状态 = .submitted)
    /// 5. sendMail off → 不 end,session 暂存为草稿(状态保持 .draft),让用户之后从
    ///    「报告」Tab 草稿段点「继续巡检」回来。用户原话:"未发邮件的也不能叫已提交"
    /// 6. teamShare 已通过 TeamDataMirrorService 自动 mirror,UI 只展示信息行
    private func handleConfirm() {
        guard !isGenerating, !isArchiving else { return }
        applyEditsToReport()

        // P2 #199:**同步**设 isGenerating=true,防用户在 Task 启动前狂按再次进 handleConfirm
        // (之前 isGenerating=true 在 Task 内,guard 检查时还是 false → 双重 generatePDF 竞态,
        //  临时 PDF 文件互相覆盖)。
        let needRegen = infoDirty || generatedPDFURL == nil
        if needRegen {
            isGenerating = true
            generatedPDFURL = nil
            pdfThumbnail = nil
        }

        Task { @MainActor in
            if needRegen {
                await generatePDF()
                infoDirty = false
            }

            // sendMail 路径:走原 handleSendMail 流程(准备 attachment + 弹 MailComposeView)
            if sendMail {
                handleSendMail()
                return
            }

            // 不发邮件:仅归档 PDF,把 session 暂存为草稿(不 mark .submitted)。
            // session manager detach → banner 收起;报告进「报告」Tab 草稿段。
            isArchiving = true
            let archived = archiveGeneratedPDFIfPresent()
            suspendSessionAsDraftAndCallback(archivedPDFURL: archived)
            isArchiving = false
        }
    }

    /// 拉本 session 关联的 Notes。按 report.noteIDs 给定顺序重排。
    /// 实现:fetch 全部 Note(SwiftData `#Predicate` 内对捕获 Set/Array 的 .contains
    /// 兼容性不稳),再用 idSet 做 in-memory 过滤——session 通常 < 50 条,代价可忽略。
    private func fetchSessionNotes() -> [Note] {
        let ids = report.noteIDs
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<Note>()
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        let matched = fetched.filter { idSet.contains($0.id) }
        // 还原 noteIDs 的顺序(fetch 出来的顺序不保证)
        let byID = Dictionary(uniqueKeysWithValues: matched.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    /// 后台异步生成 PDF + 渲染缩略图。
    @MainActor
    private func generatePDF() async {
        do {
            let url = try await InspectionReportPDFBuilder.build(
                report: report,
                notes: sessionNotes
            )
            generatedPDFURL = url
            // 缩略图脱主线程渲染,主线程只更新 @State。
            let thumb = await Task.detached(priority: .userInitiated) {
                Self.renderPDFThumbnail(url: url)
            }.value
            pdfThumbnail = thumb
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isGenerating = false
    }

    /// PDF 首页 → UIImage 缩略图。Detached 后台跑。
    private nonisolated static func renderPDFThumbnail(url: URL) -> UIImage? {
        guard let doc = PDFDocument(url: url),
              let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        // 72×96 在 @3x 设备约 216×288,渲到 256 长边足够清晰。
        let scale = min(256 / bounds.width, 340 / bounds.height)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }
    }

    // MARK: - Actions

    /// Toggle Builder 勾选(用空邮箱的就直接 noop,builderRow 已 disable 但双保险)。
    private func toggleBuilder(_ id: UUID) {
        if selectedBuilderIDs.contains(id) {
            selectedBuilderIDs.remove(id)
        } else {
            selectedBuilderIDs.insert(id)
        }
    }

    /// "仅存档,不发邮件":end session + 归档 PDF(若已生成),不弹邮件。
    private func handleArchiveOnly() {
        guard !isArchiving else { return }
        isArchiving = true
        errorMessage = nil

        let archivedURL = archiveGeneratedPDFIfPresent()
        endSessionAndCallback(archivedPDFURL: archivedURL)
    }

    /// "发邮件并存档":准备 attachment → 弹 MailCompose。
    /// .sent 回调里再做归档 + end session。.cancelled / .failed 不结束 session,留给用户重试。
    private func handleSendMail() {
        guard let url = generatedPDFURL else {
            errorMessage = String(localized: "PDF 还在生成,请稍候。",
                                  locale: AppLanguageManager.currentLocale)
            return
        }
        guard MailComposeView.canSendMail else {
            errorMessage = String(localized: "当前设备未配置邮箱账号。请到 iOS 设置 → 邮件 添加账号后重试。",
                                  locale: AppLanguageManager.currentLocale)
            return
        }
        guard let raw = EmailService.loadPDFAttachment(at: url, reportNo: report.reportNo) else {
            errorMessage = String(localized: "PDF 文件无法读取,请重试生成。",
                                  locale: AppLanguageManager.currentLocale)
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

    /// MFMail 回调:发送成功 → end + archive + 关 sheet;否则提示错并保持 sheet。
    private func handleMailResult(_ result: MFMailComposeResult) {
        switch result {
        case .sent:
            let archivedURL = archiveGeneratedPDFIfPresent()
            endSessionAndCallback(archivedPDFURL: archivedURL)
        case .failed:
            errorMessage = String(localized: "邮件发送失败,请检查邮箱设置或网络后重试。",
                                  locale: AppLanguageManager.currentLocale)
        case .saved, .cancelled:
            // 用户改主意 / 存草稿了 — 不算完成,保留 session 给重试。
            break
        @unknown default:
            break
        }
    }

    /// 把临时 PDF 归档到 Reports/<projectFolder>。失败静默(返回 nil)。
    private func archiveGeneratedPDFIfPresent() -> URL? {
        guard let src = generatedPDFURL else { return nil }
        let folder = report.projectNo.isEmpty ? nil : report.projectNo
        do {
            let dest = try ReportArchiveService.archive(
                sourceURL: src,
                projectFolder: folder
            )
            report.lastPDFPath = dest.path
            return dest
        } catch {
            // 归档失败别拦用户结束 session — 起码邮件已经发了 / 用户已经明确要结束。
            return nil
        }
    }

    /// end session + 触发 callback + 关 sheet。
    private func endSessionAndCallback(archivedPDFURL: URL?) {
        do {
            _ = try InspectionSessionManager.shared.end(in: modelContext)
        } catch {
            // end 失败不阻断 UI 跳转(状态机层的异常少见且无可挽回);记下提示。
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        onCompleted(report, archivedPDFURL)
        dismiss()
    }

    /// "暂存为草稿" + 触发 callback + 关 sheet。
    /// session manager detach 但 report 状态保持 .draft、submittedAt 不写。
    /// 报告进「报告」Tab 的草稿段,用户之后可点「继续巡检」回到 session。
    private func suspendSessionAsDraftAndCallback(archivedPDFURL: URL?) {
        InspectionSessionManager.shared.suspendAsDraft()
        // 写一次 updatedAt 让列表行的"最近编辑"信号更新,
        // 但 statusRaw / submittedAt 都不动。
        report.updatedAt = Date()
        // P1 #194:save 失败写日志 — 之前 try? 静默,失败时 updatedAt 不持久化 → 列表行旧
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("suspendAsDraft save failed: \(error.localizedDescription)")
        }
        // 团队同步:applyEditsToReport 把用户改的 reportNo/project/location/attn 等
        // 写进 report,但草稿路径不走 end(in:)(没 mirror),不补这条 mirror 的话
        // Member 端永远看不到这些编辑。
        let ctx = modelContext
        let r = report
        Task { await TeamDataMirrorService.shared.mirrorReport(r, in: ctx) }
        onCompleted(report, archivedPDFURL)
        dismiss()
    }
}

// MARK: - QuickLook 包装

/// QuickLook 单 PDF 预览。比起自己写 PDFKit + zoom 控件,系统 QL 一行搞定。
private struct QuickLookPreview: UIViewControllerRepresentable {
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
