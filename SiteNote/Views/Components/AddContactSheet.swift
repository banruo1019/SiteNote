//
//  AddContactSheet.swift
//  SiteNote
//
//  在 SitePresetEditor 里 inline 添加新联系人的 bottom sheet。
//
//  设计动机:
//  - 用户填工地预设时常发现"这个工头还没存进通讯录",原本要退出去 Settings
//    页加完再回来,容易丢上下文。这个 sheet 把"加联系人 + 自动 link 到本工地"
//    合并成一步,公司字段直接锁死为当前 site 的 clientName,避免输错。
//  - 保存后调用方负责把 builder.id 写到 SitePreset.builderID(若 markAsDefault),
//    本 sheet 只管"创建 Builder + 持久化 + 回调"。
//
//  保存逻辑:
//  1. 校验 name 非空,email 含 @ 且 . 在 @ 后(本地轻量校验,不连网)。
//  2. 用 Builder(name:company:email:phone:) 构造,company 强制取传入的
//     `company` 参数(锁定,不可改)。
//  3. BuildersStorage.add(builder) 写入 UserDefaults。
//     注意:存储层会自动 trim name/email,空 name/email 拒绝;
//     超出 maxItems 也会拒绝并返回 nil。
//  4. 调 onAdded(builder, markAsDefault),调用方决定是否设为本工地默认收件人。
//  5. dismiss。
//

import SwiftUI

struct AddContactSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 当前 site 的 clientName,作为新 builder 的公司名(锁定,read-only 显示)。
    /// 传空字符串也允许,UI 会显示"未指定"灰字。
    let company: String

    /// 完成回调。把新建好的 Builder 和"是否设为本工地默认收件人"开关传回。
    /// 调用方负责把 builder.id 写到 SitePreset.builderID(若 markAsDefault=true)。
    var onAdded: (Builder, _ markAsDefault: Bool) -> Void

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var markAsDefault: Bool = true
    /// 保存失败时给用户的提示(如超出 maxItems 上限)。
    @State private var errorMessage: String?

    /// 当前 focus 字段,决定 input box 是否高亮 1.5pt Ink.fg 描边。
    @FocusState private var focusedField: FocusField?
    private enum FocusField: Hashable { case name, email, phone }

    private var locale: Locale { AppLanguageManager.currentLocale }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPhone: String {
        phone.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 保存按钮可用条件:名字非空 + 邮箱本地校验通过。
    private var canSave: Bool {
        !trimmedName.isEmpty && Self.isValidEmail(trimmedEmail)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    companySection
                    nameSection
                    emailSection
                    phoneSection
                    defaultToggleSection
                    if let msg = errorMessage {
                        errorBanner(msg)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(Ink.bg)
            .navigationTitle(String(localized: "加联系人", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", locale: locale)) { dismiss() }
                        .foregroundStyle(Ink.fg)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Text(String(localized: "保存", locale: locale))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(canSave ? Ink.bg : Ink.fgDim)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(canSave ? Ink.fg : Ink.card)
                            )
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                // 进入页面默认 focus 姓名输入,公司已锁,优先填名字。
                focusedField = .name
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    /// 公司字段:read-only,显示当前 site 的 clientName。
    /// 灰底 + dim 文字,提示用户"此处由所在工地决定,不在此处改"。
    private var companySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(
                icon: "building.2",
                text: String(localized: "公司", locale: locale)
            )

            HStack(spacing: 8) {
                Text(company.isEmpty
                     ? String(localized: "未指定", locale: locale)
                     : company)
                    .font(.system(size: 15))
                    .foregroundStyle(Ink.fgDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Ink.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Ink.line, lineWidth: 1)
            )
        }
    }

    /// 姓名 section,必填,带 * 标记。
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(
                icon: "person",
                text: String(localized: "姓名", locale: locale),
                required: true
            )

            TextField(
                String(localized: "如 John Smith", locale: locale),
                text: $name
            )
            .focused($focusedField, equals: .name)
            .font(.system(size: 15))
            .tint(Ink.fg)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit { focusedField = .email }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Ink.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        focusedField == .name ? Ink.fg : Ink.line,
                        lineWidth: focusedField == .name ? 1.5 : 1
                    )
            )
        }
    }

    /// 邮箱 section,必填,带 * 标记。键盘类型 emailAddress。
    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(
                icon: "envelope",
                text: String(localized: "邮箱", locale: locale),
                required: true
            )

            TextField(
                String(localized: "john@lendlease.com", locale: locale),
                text: $email
            )
            .focused($focusedField, equals: .email)
            .font(.system(size: 15))
            .tint(Ink.fg)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit { focusedField = .phone }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Ink.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        focusedField == .email ? Ink.fg : Ink.line,
                        lineWidth: focusedField == .email ? 1.5 : 1
                    )
            )
        }
    }

    /// 手机 section,可留空。
    private var phoneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(
                icon: "phone",
                text: String(localized: "手机", locale: locale)
            )

            TextField(
                String(localized: "可留空", locale: locale),
                text: $phone
            )
            .focused($focusedField, equals: .phone)
            .font(.system(size: 15))
            .tint(Ink.fg)
            .keyboardType(.phonePad)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Ink.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        focusedField == .phone ? Ink.fg : Ink.line,
                        lineWidth: focusedField == .phone ? 1.5 : 1
                    )
            )
        }
    }

    /// "默认收件人"开关。默认 on,新增即设为本工地默认。
    private var defaultToggleSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "默认收件人", locale: locale))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                Text(String(
                    localized: "创建后自动勾选为本工地默认收件人",
                    locale: locale
                ))
                .font(.system(size: 11))
                .foregroundStyle(Ink.fgDim)
                .lineSpacing(2)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $markAsDefault)
                .labelsHidden()
                .tint(Ink.fg)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Ink.card)
        )
    }

    /// 错误条:存储失败时显示(如超出 maxItems 上限)。
    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Ink.red)
                .padding(.top, 2)
            Text(msg)
                .font(.system(size: 12))
                .foregroundStyle(Ink.fg)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Ink.red.opacity(0.08))
        )
    }

    /// Section 标签:icon + 文字,必填项加红色 *。
    private func sectionLabel(icon: String, text: String, required: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.fg)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ink.fg)
            if required {
                Text("*")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ink.red)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }
        errorMessage = nil

        let builder = Builder(
            name: trimmedName,
            company: company,            // 锁定值,来自调用方
            email: trimmedEmail,
            phone: trimmedPhone
        )

        // BuildersStorage.add 失败:可能是空 name/email(已被 canSave 拦截),
        // 或超出 maxItems 上限。后者给用户明确提示。
        guard BuildersStorage.add(builder) != nil else {
            errorMessage = String(
                localized: "联系人保存失败,可能已达上限。请到设置里清理后再加。",
                locale: locale
            )
            return
        }

        onAdded(builder, markAsDefault)
        dismiss()
    }

    // MARK: - Email validation

    /// 极轻量邮箱校验:含 @ 且 . 在 @ 之后,本地长度合理。
    /// 不上正则,避免 RFC 5322 焦虑;真正的有效性由发送时回执决定。
    static func isValidEmail(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 5 else { return false }
        guard let atIdx = s.firstIndex(of: "@") else { return false }
        // @ 不能在首位
        guard atIdx != s.startIndex else { return false }
        let afterAt = s.index(after: atIdx)
        guard afterAt < s.endIndex else { return false }
        // @ 之后必须出现至少一个 .,且 . 不能紧贴 @
        let domainPart = s[afterAt...]
        guard let dotIdx = domainPart.firstIndex(of: ".") else { return false }
        guard dotIdx != domainPart.startIndex else { return false }
        // . 之后还要有至少一个字符(顶级域)
        let afterDot = domainPart.index(after: dotIdx)
        guard afterDot < domainPart.endIndex else { return false }
        return true
    }
}
