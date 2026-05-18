//
//  AddContactSheet.swift
//  SiteNote
//
//  在 SitePresetEditor 里 inline 添加新联系人(Contact)的 bottom sheet。
//
//  设计动机:
//  - 用户填工地预设时常发现"这个联系人还没存进通讯录",原本要退出去 Settings
//    页加完再回来,容易丢上下文。这个 sheet 把"加联系人 + 自动 link 到本工地"
//    合并成一步。
//
//  v1.5 改:Builder 拆成 Builder(公司)+ Contact(联系人)后,sheet 的职责变成:
//  1. 选/新建 Builder(公司)— 公司是必需的;若 SitePreset.clientName 能匹配已有
//     公司,默认选中那家;否则提示用户选或新建。
//  2. 填 Contact 的 name / email / phone。
//  3. 保存:ContactsStorage.add 写入,回调 onAdded(contact, markAsDefault),
//     SitePresetEditor 把 contact.id 塞进 linkedContactIDs / defaultRecipientIDs。
//

import SwiftUI

struct AddContactSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 当前 site 的 clientName。用于尝试匹配已有公司;匹配不到也作为新公司名的默认值。
    /// 传空字符串也允许,UI 会让用户从下拉里选。
    let company: String

    /// 完成回调。把新建好的 Contact 和"是否设为本工地默认收件人"开关传回。
    /// SitePresetEditor 把 contact.id 写到 linkedContactIDs / defaultRecipientIDs。
    var onAdded: (Contact, _ markAsDefault: Bool) -> Void

    /// 全部已有公司(用于下拉选)。
    @State private var allBuilders: [Builder] = []
    /// 当前选中的公司 id。nil = 还没选(需要选或新建)。
    @State private var selectedBuilderID: UUID? = nil
    /// 新建公司输入框(只在 selectedBuilderID == nil 时显示)。
    @State private var newCompanyName: String = ""

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var markAsDefault: Bool = true
    /// 保存失败时的错误提示。
    @State private var errorMessage: String?

    @FocusState private var focusedField: FocusField?
    private enum FocusField: Hashable { case newCompany, name, email, phone }

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

    private var trimmedNewCompany: String {
        newCompanyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 选定 / 新建后能落到一个具体的 Builder.id。
    /// - 已选中:返 selectedBuilderID
    /// - 没选:必须新建,新建公司名非空时返新 id(在 save 时创建)
    private var canSave: Bool {
        let nameOK = !trimmedName.isEmpty
        let companyOK = (selectedBuilderID != nil) || !trimmedNewCompany.isEmpty
        // 邮箱可空,有邮箱则要本地校验通过(便于一键发邮件)。
        let emailOK = trimmedEmail.isEmpty || Self.isValidEmail(trimmedEmail)
        return nameOK && companyOK && emailOK
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
            .onAppear(perform: bootstrap)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    /// 公司字段:Picker 选已有 + "新建公司"行。
    /// 启动时如果 `company` 参数匹配已有 Builder 名,默认选中那家;
    /// 否则空选,把它预填到"新建公司"输入框。
    private var companySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(
                icon: "building.2",
                text: String(localized: "公司", locale: locale),
                required: true
            )

            // 已有公司 Picker(只在有公司时显示)
            if !allBuilders.isEmpty {
                Menu {
                    ForEach(allBuilders) { b in
                        Button {
                            selectedBuilderID = b.id
                            newCompanyName = ""
                        } label: {
                            if selectedBuilderID == b.id {
                                Label(b.name, systemImage: "checkmark")
                            } else {
                                Text(b.name)
                            }
                        }
                    }
                    Divider()
                    Button {
                        selectedBuilderID = nil
                        focusedField = .newCompany
                    } label: {
                        Label(String(localized: "新建公司...", locale: locale),
                              systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(selectedCompanyLabel)
                            .font(.system(size: 15))
                            .foregroundStyle(selectedBuilderID == nil ? Ink.fgDim : Ink.fg)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Ink.fgDim)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(Ink.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Ink.line, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            // 新建公司输入框(没选已有 → 显示这个)
            if selectedBuilderID == nil {
                TextField(
                    String(localized: "新公司名(如 HRK Construction)", locale: locale),
                    text: $newCompanyName
                )
                .focused($focusedField, equals: .newCompany)
                .font(.system(size: 15))
                .tint(Ink.fg)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focusedField = .name }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Ink.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            focusedField == .newCompany ? Ink.fg : Ink.line,
                            lineWidth: focusedField == .newCompany ? 1.5 : 1
                        )
                )
            }
        }
    }

    /// 公司选中态显示文案。
    private var selectedCompanyLabel: String {
        if let id = selectedBuilderID,
           let b = allBuilders.first(where: { $0.id == id }) {
            return b.name
        }
        return String(localized: "选择公司(或往下新建)", locale: locale)
    }

    /// 姓名 section,必填。
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

    /// 邮箱 section,可选(填了就 validate)。
    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(
                icon: "envelope",
                text: String(localized: "邮箱", locale: locale)
            )

            TextField(
                String(localized: "john@example.com", locale: locale),
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

    // MARK: - Lifecycle

    private func bootstrap() {
        allBuilders = BuildersStorage.load()
        // 尝试用 company 参数匹配已有 Builder。命中 → 自动选中;否则把 company 预填到"新公司"。
        let target = company.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !target.isEmpty,
           let matched = allBuilders.first(where: { $0.name.lowercased() == target }) {
            selectedBuilderID = matched.id
        } else {
            selectedBuilderID = nil
            if newCompanyName.isEmpty {
                newCompanyName = company.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // 默认 focus 姓名输入(若已选公司);否则先填新公司名。
        focusedField = (selectedBuilderID == nil && newCompanyName.isEmpty) ? .newCompany : .name
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }
        errorMessage = nil

        // 1) 确保 builderID 存在 — 没有就先创建公司。
        let builderID: UUID
        if let existing = selectedBuilderID {
            builderID = existing
        } else {
            let newCompany = Builder(name: trimmedNewCompany)
            guard let createdID = BuildersStorage.add(newCompany) else {
                errorMessage = String(
                    localized: "公司创建失败,可能已达上限。请到设置里清理后再加。",
                    locale: locale
                )
                return
            }
            builderID = createdID
        }

        // 2) 创建 Contact。
        let contact = Contact(
            builderID: builderID,
            name: trimmedName,
            email: trimmedEmail,
            phone: trimmedPhone
        )
        guard ContactsStorage.add(contact) != nil else {
            errorMessage = String(
                localized: "联系人保存失败,可能已达上限。请到设置里清理后再加。",
                locale: locale
            )
            return
        }

        onAdded(contact, markAsDefault)
        dismiss()
    }

    // MARK: - Email validation

    /// 极轻量邮箱校验:含 @ 且 . 在 @ 之后,本地长度合理。
    static func isValidEmail(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 5 else { return false }
        guard let atIdx = s.firstIndex(of: "@") else { return false }
        guard atIdx != s.startIndex else { return false }
        let afterAt = s.index(after: atIdx)
        guard afterAt < s.endIndex else { return false }
        let domainPart = s[afterAt...]
        guard let dotIdx = domainPart.firstIndex(of: ".") else { return false }
        guard dotIdx != domainPart.startIndex else { return false }
        let afterDot = domainPart.index(after: dotIdx)
        guard afterDot < domainPart.endIndex else { return false }
        return true
    }
}
