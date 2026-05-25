//
//  EmailTemplateEditorView.swift
//  SiteNote
//
//  邮件模板编辑器。Engineer 一键发邮件时的主题 / 正文预填模板,在这里改。
//  - subject TextField + body TextEditor
//  - 占位符说明(MVP 5 + date 共 6 个)
//  - "保存" / "恢复默认"
//

import SwiftUI

struct EmailTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var subject: String = ""
    @State private var bodyText: String = ""
    @State private var isDirty: Bool = false
    @State private var showRestoreConfirm: Bool = false
    @State private var topMessage: String?

    private var locale: Locale { AppLanguageManager.currentLocale }

    var body: some View {
        Form {
            if let msg = topMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                }
            }

            Section {
                TextField(
                    String(localized: "邮件主题", locale: locale),
                    text: Binding(
                        get: { subject },
                        set: { subject = $0; isDirty = true }
                    ),
                    axis: .vertical
                )
                .lineLimit(1...3)
                .font(.system(size: DesignTokens.FontSize.body))
            } header: {
                SectionHeader(String(localized: "主题", locale: locale))
            }

            Section {
                TextEditor(text: Binding(
                    get: { bodyText },
                    set: { bodyText = $0; isDirty = true }
                ))
                .font(.system(size: DesignTokens.FontSize.body))
                .frame(minHeight: 220)
            } header: {
                SectionHeader(String(localized: "正文", locale: locale))
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "可用占位符(会被替换为报告对应字段)", locale: locale))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.fg2)
                    placeholderRow("{project}", String(localized: "项目名", locale: locale))
                    placeholderRow("{projectNo}", String(localized: "项目编号", locale: locale))
                    placeholderRow("{client}", String(localized: "客户", locale: locale))
                    placeholderRow("{reportNo}", String(localized: "报告号", locale: locale))
                    placeholderRow("{date}", String(localized: "报告日期", locale: locale))
                    placeholderRow("{inspectionType}", String(localized: "巡检类型", locale: locale))
                }
                .padding(.vertical, 4)
            } header: {
                SectionHeader(String(localized: "占位符", locale: locale))
            } footer: {
                SectionFooter(String(
                    localized: "字段为空时占位符会替换为空字符串。",
                    locale: locale
                ))
            }

            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        Image(systemName: "tray.and.arrow.down")
                        Text(String(localized: "保存", locale: locale))
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    }
                }
                .disabled(!isDirty)

                Button(role: .destructive) {
                    showRestoreConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text(String(localized: "恢复默认", locale: locale))
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    }
                }
            }
        }
        .industrialForm()
        .navigationTitle(String(localized: "邮件模板", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .alert(String(localized: "恢复默认?", locale: locale),
               isPresented: $showRestoreConfirm) {
            Button(String(localized: "恢复", locale: locale), role: .destructive) {
                restoreDefaults()
            }
            Button(String(localized: "取消", locale: locale), role: .cancel) {}
        } message: {
            Text(String(localized: "会清除自定义内容,恢复到内置模板。", locale: locale))
        }
    }

    // MARK: - Rows

    private func placeholderRow(_ token: String, _ desc: String) -> some View {
        HStack(spacing: 8) {
            Text(token)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Ink.fg)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Ink.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Ink.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(desc)
                .font(.system(size: 12))
                .foregroundStyle(Ink.fgDim)
            Spacer()
        }
    }

    // MARK: - Actions

    private func reload() {
        let t = EmailTemplateStorage.load()
        subject = t.subject
        bodyText = t.body
        isDirty = false
    }

    private func save() {
        let t = EmailTemplate(subject: subject, body: bodyText)
        EmailTemplateStorage.save(t)
        isDirty = false
        showTopMessage(String(localized: "已保存。", locale: locale))
    }

    private func restoreDefaults() {
        EmailTemplateStorage.restoreDefaults()
        let t = EmailTemplateStorage.defaultTemplate()
        subject = t.subject
        bodyText = t.body
        isDirty = false
        showTopMessage(String(localized: "已恢复默认。", locale: locale))
    }

    private func showTopMessage(_ msg: String) {
        topMessage = msg
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            topMessage = nil
        }
    }
}
