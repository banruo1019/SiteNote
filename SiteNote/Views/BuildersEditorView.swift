//
//  BuildersEditorView.swift
//  SiteNote
//
//  建造商 / 工头联系人簿编辑器。给 Inspection 工作流里的 "Attn" 字段
//  和"一键发邮件"提供数据源。
//
//  数据存 BuildersStorage(UserDefaults JSON,上限 200)。
//

import SwiftUI

struct BuildersEditorView: View {
    /// 当前展示的列表。增删改后从 storage 重新 load,保证一致。
    @State private var builders: [Builder] = BuildersStorage.load()

    /// 添加 / 编辑表单的 sheet 状态。
    @State private var editing: BuilderEditingTarget? = nil

    /// 通用 alert(重复 email、超上限等)。
    @State private var alertMessage: String? = nil

    private var locale: Locale { AppLanguageManager.currentLocale }

    var body: some View {
        Form {
            if builders.isEmpty {
                Section {
                    Text(String(localized: "还没有联系人。点右上角「添加」加一个试试。", locale: locale))
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.fgDim)
                }
            } else {
                Section {
                    ForEach(builders) { builder in
                        Button {
                            editing = .edit(builder)
                        } label: {
                            row(for: builder)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                remove(builder)
                            } label: {
                                Label(String(localized: "删除", locale: locale),
                                      systemImage: "trash")
                            }
                        }
                    }
                    .onMove(perform: moveBuilders)
                } header: {
                    SectionHeader(String(localized: "联系人 (\(builders.count))", locale: locale))
                } footer: {
                    SectionFooter(String(
                        localized: "最多 200 个。空 email 拒收。这些联系人会出现在 Inspection 表单的「Attn」字段和「一键发邮件」。",
                        locale: locale
                    ))
                }
            }
        }
        .industrialForm()
        .navigationTitle(String(localized: "建造商联系簿", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !builders.isEmpty {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = .new
                } label: {
                    Label(String(localized: "添加", locale: locale),
                          systemImage: "plus")
                }
                .disabled(builders.count >= BuildersStorage.maxItems)
            }
        }
        .sheet(item: $editing) { target in
            BuilderEditSheet(
                target: target,
                existingEmails: existingEmails(excluding: target.editingID),
                onSave: { handleSave($0, target: target) }
            )
        }
        .alert(String(localized: "无法保存", locale: locale),
               isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
               )) {
            Button(String(localized: "知道了", locale: locale), role: .cancel) {
                alertMessage = nil
            }
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear {
            builders = BuildersStorage.load()
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for b: Builder) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.text.rectangle")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(b.name)
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                    if !b.company.isEmpty {
                        Text("· \(b.company)")
                            .font(.system(size: DesignTokens.FontSize.body))
                            .foregroundStyle(.secondary)
                    }
                }
                if !b.email.isEmpty {
                    Text(b.email)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.dim)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func remove(_ b: Builder) {
        BuildersStorage.remove(id: b.id)
        builders = BuildersStorage.load()
    }

    private func moveBuilders(from source: IndexSet, to destination: Int) {
        var copy = builders
        copy.move(fromOffsets: source, toOffset: destination)
        BuildersStorage.save(copy)
        builders = BuildersStorage.load()
    }

    /// 取出"用于查重"的 email 集合,可选地排除某条(编辑时本人不算重复)。
    private func existingEmails(excluding id: UUID?) -> Set<String> {
        var set = Set<String>()
        for b in builders {
            if let id, b.id == id { continue }
            set.insert(b.email.lowercased())
        }
        return set
    }

    private func handleSave(_ draft: Builder, target: BuilderEditingTarget) {
        // 表单 sheet 已经做过 name/email 校验和查重。这里只把数据落盘。
        switch target {
        case .new:
            guard builders.count < BuildersStorage.maxItems else {
                alertMessage = String(localized: "已达 200 条上限,删一些再加。", locale: locale)
                return
            }
            if BuildersStorage.add(draft) == nil {
                alertMessage = String(localized: "保存失败:name 或 email 为空。", locale: locale)
            }
        case .edit:
            if !BuildersStorage.update(draft) {
                alertMessage = String(localized: "保存失败:找不到原条目。", locale: locale)
            }
        }
        builders = BuildersStorage.load()
        editing = nil
    }
}

// MARK: - Editing target

enum BuilderEditingTarget: Identifiable {
    case new
    case edit(Builder)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let b): return b.id.uuidString
        }
    }

    var editingID: UUID? {
        switch self {
        case .new: return nil
        case .edit(let b): return b.id
        }
    }

    var initial: Builder {
        switch self {
        case .new: return Builder()
        case .edit(let b): return b
        }
    }
}

// MARK: - Edit sheet

private struct BuilderEditSheet: View {
    let target: BuilderEditingTarget
    /// 用于查重(已 lowercased)。编辑时本人不算重复。
    let existingEmails: Set<String>
    let onSave: (Builder) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var company: String
    @State private var email: String
    @State private var phone: String
    @State private var notes: String

    @State private var errorMessage: String?

    private var locale: Locale { AppLanguageManager.currentLocale }

    init(target: BuilderEditingTarget,
         existingEmails: Set<String>,
         onSave: @escaping (Builder) -> Void) {
        self.target = target
        self.existingEmails = existingEmails
        self.onSave = onSave
        let initial = target.initial
        _name = State(initialValue: initial.name)
        _company = State(initialValue: initial.company)
        _email = State(initialValue: initial.email)
        _phone = State(initialValue: initial.phone)
        _notes = State(initialValue: initial.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "姓名(必填)", locale: locale), text: $name)
                        .textInputAutocapitalization(.words)
                    TextField(String(localized: "公司", locale: locale), text: $company)
                        .textInputAutocapitalization(.words)
                } header: {
                    SectionHeader(String(localized: "基本信息", locale: locale))
                }

                Section {
                    TextField(String(localized: "邮箱(必填)", locale: locale), text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(String(localized: "手机", locale: locale), text: $phone)
                        .keyboardType(.phonePad)
                } header: {
                    SectionHeader(String(localized: "联系方式", locale: locale))
                } footer: {
                    SectionFooter(String(localized: "邮箱用于「一键发邮件」。手机仅留作备用,不会自动拨号。", locale: locale))
                }

                Section {
                    TextField(String(localized: "备注(可选)", locale: locale),
                              text: $notes,
                              axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    SectionHeader(String(localized: "备注", locale: locale))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                }
            }
            .industrialForm()
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "取消", locale: locale)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "保存", locale: locale)) {
                        attemptSave()
                    }
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .disabled(!canSave)
                }
            }
        }
    }

    private var navTitle: String {
        switch target {
        case .new: return String(localized: "新建联系人", locale: locale)
        case .edit: return String(localized: "编辑联系人", locale: locale)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 简化的 email 合规检测(不用正则)。
    private func isValidEmail(_ s: String) -> Bool {
        s.contains("@") && s.contains(".") && s.count > 5
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && isValidEmail(trimmedEmail)
    }

    private func attemptSave() {
        guard !trimmedName.isEmpty else {
            errorMessage = String(localized: "姓名不能为空。", locale: locale)
            return
        }
        guard isValidEmail(trimmedEmail) else {
            errorMessage = String(localized: "邮箱格式不对(需含 @ 和 .)。", locale: locale)
            return
        }
        if existingEmails.contains(trimmedEmail.lowercased()) {
            errorMessage = String(localized: "已存在使用同一邮箱的联系人。", locale: locale)
            return
        }

        var draft = target.initial   // 保留 id(编辑时)
        draft.name = trimmedName
        draft.company = company.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.email = trimmedEmail
        draft.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        onSave(draft)
        dismiss()
    }
}
