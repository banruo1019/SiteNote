//
//  InspectionExportSheet.swift
//  SiteNote
//
//  Engineer 工作流终点:导出 Inspection PDF 后弹这个 sheet,让用户一键发邮件 / 退而求其次分享。
//
//  调用方(InspectionFormView,R3):
//      .sheet(item: $exportContext) { ctx in
//          InspectionExportSheet(report: report, pdfURL: ctx.pdfURL)
//      }
//
//  本 sheet 不重新生成 PDF,只负责"已有 PDF + 已有 builderID → 邮件/分享"。
//

import SwiftUI
import SwiftData
import PDFKit
import MessageUI

struct InspectionExportSheet: View {

    let report: InspectionReport
    let pdfURL: URL

    // MARK: - 收件人 / 内容(可编辑)

    /// 当前选中的 builder。初值从 report.builderID 反查。
    @State private var selectedBuilder: Builder?

    /// 可编辑主题。预填 EmailService.subjectFor(report:)。
    @State private var subject: String = ""

    /// 可编辑正文。预填 EmailService.bodyFor(report:)。
    @State private var emailBody: String = ""

    // MARK: - Sheet / Alert 控制

    @State private var showsBuilderPicker: Bool = false
    @State private var showsMailCompose: Bool = false
    @State private var showsShareSheet: Bool = false
    @State private var showsCannotMailAlert: Bool = false
    @State private var showsMailFailedAlert: Bool = false
    @State private var showsAttachmentFailedAlert: Bool = false

    /// 缓存附件数据。点"发送邮件"时构造一次,失败立刻提示;成功传给 MailComposeView。
    @State private var pendingAttachment: MailComposeView.Attachment?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                recipientSection
                subjectSection
                bodySection
                actionSection
            }
            .industrialForm()
            .navigationTitle(Text("发送报告"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: prefill)
        .sheet(isPresented: $showsBuilderPicker) {
            BuilderPickerSheet(
                selectedID: selectedBuilder?.id,
                onPick: { picked in
                    selectedBuilder = picked
                    showsBuilderPicker = false
                }
            )
        }
        .sheet(isPresented: $showsMailCompose) {
            if let attachment = pendingAttachment {
                MailComposeView(
                    recipients: currentRecipients,
                    subject: subject,
                    body: emailBody,
                    attachments: [attachment]
                ) { result, _ in
                    showsMailCompose = false
                    if result == .failed {
                        showsMailFailedAlert = true
                    } else if result == .sent {
                        // 邮件发送成功 → 归档:report 状态切到 submitted,
                        // EngineerReportsView 自动把它挪到"已提交"段。
                        // submittedAt 用于显示和将来审计。
                        archiveReport()
                        // 成功就把整个 sheet 也关掉,让用户回到 form。
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            ShareSheet(items: [pdfURL])
        }
        .alert("当前设备未配置邮箱", isPresented: $showsCannotMailAlert) {
            Button("分享 PDF") {
                showsCannotMailAlert = false
                showsShareSheet = true
            }
            Button("知道了", role: .cancel) {
                showsCannotMailAlert = false
            }
        } message: {
            Text("请到 iOS 设置 → 邮件 添加邮箱账号后再试,或先分享 PDF 通过其他方式发送。")
        }
        .alert("邮件发送失败", isPresented: $showsMailFailedAlert) {
            Button("知道了", role: .cancel) { showsMailFailedAlert = false }
        } message: {
            Text("邮件发送失败,请检查邮箱设置或网络后重试。")
        }
        .alert("无法读取 PDF", isPresented: $showsAttachmentFailedAlert) {
            Button("知道了", role: .cancel) { showsAttachmentFailedAlert = false }
        } message: {
            Text("PDF 文件无法读取,请回到上一步重新导出。")
        }
    }

    // MARK: - Sections

    /// 顶部 PDF 缩略图 + Report No。
    private var previewSection: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                PDFThumbnailImage(url: pdfURL)
                    .frame(width: 64, height: 84)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(reportNoDisplay)
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    if !report.location.isEmpty {
                        Text(report.location)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(pdfURL.lastPathComponent)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    /// "发给"段。
    @ViewBuilder
    private var recipientSection: some View {
        Section("发给") {
            if BuildersStorage.load().isEmpty {
                // 联系簿为空——引导去 Settings。
                VStack(alignment: .leading, spacing: 6) {
                    Text("联系人簿是空的")
                        .font(.system(size: DesignTokens.FontSize.body, weight: .medium))
                    Text("请先到 设置 → 联系人簿 添加 Builder/Foreman 后再使用一键发邮件。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if let builder = selectedBuilder {
                Button {
                    showsBuilderPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(builder.name.isEmpty ? builder.email : builder.name)
                                    .font(.system(size: DesignTokens.FontSize.body, weight: .medium))
                                    .foregroundStyle(.primary)
                                if !builder.company.isEmpty {
                                    Text(builder.company)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(builder.email.isEmpty ? String(localized: "(无邮箱)", locale: AppLanguageManager.currentLocale) : builder.email)
                                .font(.system(size: 12))
                                .foregroundStyle(builder.email.isEmpty ? .red : .secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showsBuilderPicker = true
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundStyle(.tint)
                        Text("选择收件人")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var subjectSection: some View {
        Section("主题") {
            TextField("主题", text: $subject, axis: .vertical)
                .lineLimit(1...3)
                .font(.system(size: DesignTokens.FontSize.body))
        }
    }

    private var bodySection: some View {
        Section("正文") {
            TextField("正文", text: $emailBody, axis: .vertical)
                .lineLimit(6...20)
                .font(.system(size: DesignTokens.FontSize.body))
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                handleSendMail()
            } label: {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text("发送邮件")
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(!canSendMail)

            Button {
                showsShareSheet = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("分享 PDF")
                    Spacer()
                }
            }
        } footer: {
            if !MailComposeView.canSendMail {
                Text("当前设备未配置邮箱账号。可以先用「分享 PDF」通过 AirDrop / WhatsApp / 其他邮件 app 发送。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Logic

    /// 标记报告为已提交。邮件 .sent 回调里调用。
    private func archiveReport() {
        report.status = .submitted
        report.submittedAt = Date()
        report.updatedAt = Date()
        try? modelContext.save()
    }

    /// 进入 sheet 时:用 EmailService 预填 subject / body,反查 builder。
    private func prefill() {
        subject = EmailService.subjectFor(report: report)
        emailBody = EmailService.bodyFor(report: report)
        if let idString = report.builderID,
           let builder = BuildersStorage.find(idString: idString) {
            selectedBuilder = builder
        } else {
            selectedBuilder = nil
        }
    }

    /// 点"发送邮件"。检查能不能发 + 有附件 + 有收件人,失败给降级路径。
    private func handleSendMail() {
        guard MailComposeView.canSendMail else {
            showsCannotMailAlert = true
            return
        }
        guard let raw = EmailService.loadPDFAttachment(at: pdfURL, reportNo: report.reportNo) else {
            showsAttachmentFailedAlert = true
            return
        }
        pendingAttachment = MailComposeView.Attachment(
            data: raw.data,
            mimeType: raw.mimeType,
            filename: raw.filename
        )
        showsMailCompose = true
    }

    /// 实际要传给 MailComposeView 的收件人。
    /// 优先用 selectedBuilder.email;次选 EmailService.defaultRecipientsFor(让用户在 compose 内手填)。
    private var currentRecipients: [String] {
        if let builder = selectedBuilder {
            let email = builder.email.trimmingCharacters(in: .whitespacesAndNewlines)
            if !email.isEmpty { return [email] }
        }
        return EmailService.defaultRecipientsFor(report: report)
    }

    /// 主按钮 enabled 条件。
    private var canSendMail: Bool {
        guard MailComposeView.canSendMail else { return false }
        guard !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // 收件人可以为空(让用户在 compose 里手填),但有 builder 又 email 空就拦一下。
        if let builder = selectedBuilder, builder.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    private var reportNoDisplay: String {
        let trimmed = report.reportNo.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(localized: "巡检报告(草稿)", locale: AppLanguageManager.currentLocale)
        }
        return String(
            localized: "报告编号:\(trimmed)",
            locale: AppLanguageManager.currentLocale
        )
    }
}

// MARK: - Builder picker

/// 切换收件人。显示 BuildersStorage 全部条目,点选返回。
private struct BuilderPickerSheet: View {
    let selectedID: UUID?
    let onPick: (Builder) -> Void

    @State private var builders: [Builder] = BuildersStorage.load()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(builders) { builder in
                Button {
                    onPick(builder)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(builder.name.isEmpty ? builder.email : builder.name)
                                    .font(.system(size: DesignTokens.FontSize.body, weight: .medium))
                                    .foregroundStyle(.primary)
                                if !builder.company.isEmpty {
                                    Text(builder.company)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(builder.email.isEmpty ? String(localized: "(无邮箱)", locale: AppLanguageManager.currentLocale) : builder.email)
                                .font(.system(size: 12))
                                .foregroundStyle(builder.email.isEmpty ? .red : .secondary)
                        }
                        Spacer()
                        if builder.id == selectedID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(Text("选择收件人"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - PDF thumbnail

/// PDF 第一页缩略图。读不到就显示占位 SF Symbol。
private struct PDFThumbnailImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) {
            image = await Self.renderThumbnail(url: url)
        }
    }

    /// 后台线程渲染。PDFKit 在主线程渲会卡 sheet 弹起动画。
    private static func renderThumbnail(url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let doc = PDFDocument(url: url),
                  let page = doc.page(at: 0) else { return nil }
            // 64x84 在 @3x 设备 = 192x252,留点余量到 256。
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(256 / bounds.width, 336 / bounds.height)
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
        }.value
    }
}
