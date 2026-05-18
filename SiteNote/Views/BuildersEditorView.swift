//
//  BuildersEditorView.swift
//  SiteNote
//
//  建造商联系簿编辑器(两级):
//    Level 1: BuildersEditorView         — 公司列表(Builder = 公司)
//    Level 2: BuilderContactsListView    — 单个公司下的联系人列表(Contact)
//
//  数据存 BuildersStorage(公司,上限 200)+ ContactsStorage(联系人,上限 1000)。
//
//  v1.5 重写:之前是扁平的"联系人 = Builder",现在拆成两级。老数据由
//  ContactsStorage.migrateFromBuilderLegacyOnce() 一次性迁移。
//

import SwiftUI

// MARK: - Level 1: 公司列表

struct BuildersEditorView: View {
    /// 当前展示的公司列表(每次增删改后从 storage 重新 load)。
    @State private var builders: [Builder] = BuildersStorage.load()

    /// 添加 / 编辑公司表单的 sheet 状态。
    @State private var editing: BuilderEditingTarget? = nil

    /// 通用 alert(超上限等)。
    @State private var alertMessage: String? = nil

    private var locale: Locale { AppLanguageManager.currentLocale }

    var body: some View {
        Form {
            if builders.isEmpty {
                Section {
                    Text(String(localized: "还没有公司。点右上角「添加」加一个,然后进去加联系人。", locale: locale))
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.fgDim)
                }
            } else {
                Section {
                    ForEach(builders) { builder in
                        NavigationLink {
                            BuilderContactsListView(builder: builder) {
                                // 编辑/删 contact 后回来刷新一下(其实 navigation pop 不会重 init,
                                // 但万一回来后还要看 contact 数,留个口子)。
                                builders = BuildersStorage.load()
                            }
                        } label: {
                            row(for: builder)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                remove(builder)
                            } label: {
                                Label(String(localized: "删除", locale: locale),
                                      systemImage: "trash")
                            }
                            Button {
                                editing = .edit(builder)
                            } label: {
                                Label(String(localized: "改名", locale: locale),
                                      systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .onMove(perform: moveBuilders)
                } header: {
                    SectionHeader(String(localized: "公司 (\(builders.count))", locale: locale))
                } footer: {
                    SectionFooter(String(
                        localized: "最多 \(BuildersStorage.maxItems) 家公司。点公司进去管理它的联系人。",
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
        let contactCount = ContactsStorage.find(builderID: b.id).count
        HStack(spacing: 10) {
            Image(systemName: "building.2")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(b.name)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                Text(String(localized: "\(contactCount) 位联系人", locale: locale))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func remove(_ b: Builder) {
        // BuildersStorage.remove 会连带删该公司下的全部 Contact。
        BuildersStorage.remove(id: b.id)
        builders = BuildersStorage.load()
    }

    private func moveBuilders(from source: IndexSet, to destination: Int) {
        var copy = builders
        copy.move(fromOffsets: source, toOffset: destination)
        BuildersStorage.save(copy)
        builders = BuildersStorage.load()
    }

    private func handleSave(_ draft: Builder, target: BuilderEditingTarget) {
        switch target {
        case .new:
            guard builders.count < BuildersStorage.maxItems else {
                alertMessage = String(localized: "已达 \(BuildersStorage.maxItems) 条上限,删一些再加。", locale: locale)
                return
            }
            if BuildersStorage.add(draft) == nil {
                alertMessage = String(localized: "保存失败:公司名为空。", locale: locale)
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

// MARK: - Editing target(公司)

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

// MARK: - Edit sheet(公司)

private struct BuilderEditSheet: View {
    let target: BuilderEditingTarget
    let onSave: (Builder) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var notes: String

    @State private var errorMessage: String?

    private var locale: Locale { AppLanguageManager.currentLocale }

    init(target: BuilderEditingTarget,
         onSave: @escaping (Builder) -> Void) {
        self.target = target
        self.onSave = onSave
        let initial = target.initial
        _name = State(initialValue: initial.name)
        _notes = State(initialValue: initial.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "公司名(必填,如 HRK Construction)", locale: locale),
                              text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    SectionHeader(String(localized: "基本信息", locale: locale))
                } footer: {
                    SectionFooter(String(localized: "公司名会出现在工地预设的联系人选择里。", locale: locale))
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
        case .new: return String(localized: "新建公司", locale: locale)
        case .edit: return String(localized: "编辑公司", locale: locale)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !trimmedName.isEmpty }

    private func attemptSave() {
        guard !trimmedName.isEmpty else {
            errorMessage = String(localized: "公司名不能为空。", locale: locale)
            return
        }
        var draft = target.initial
        draft.name = trimmedName
        draft.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(draft)
        dismiss()
    }
}

// MARK: - Level 2: 公司下的联系人列表

struct BuilderContactsListView: View {
    let builder: Builder
    /// 父视图 dismiss 回来后,通知父视图刷新公司行(联系人数会变)。
    var onChange: () -> Void

    @State private var contacts: [Contact] = []
    @State private var editing: ContactEditingTarget? = nil
    @State private var alertMessage: String? = nil

    private var locale: Locale { AppLanguageManager.currentLocale }

    var body: some View {
        Form {
            if contacts.isEmpty {
                Section {
                    Text(String(localized: "「\(builder.name)」还没联系人。点右上角「添加」加一个。",
                                locale: locale))
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.fgDim)
                }
            } else {
                Section {
                    ForEach(contacts) { contact in
                        Button {
                            editing = .edit(contact)
                        } label: {
                            row(for: contact)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                remove(contact)
                            } label: {
                                Label(String(localized: "删除", locale: locale),
                                      systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    SectionHeader(String(localized: "联系人 (\(contacts.count))", locale: locale))
                } footer: {
                    SectionFooter(String(localized: "这些联系人会出现在工地预设的「本工地联系人」段。", locale: locale))
                }
            }
        }
        .industrialForm()
        .navigationTitle(builder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = .new
                } label: {
                    Label(String(localized: "添加", locale: locale),
                          systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { target in
            ContactEditSheet(
                builderID: builder.id,
                target: target,
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
            contacts = ContactsStorage.find(builderID: builder.id)
        }
        .onDisappear {
            onChange()
        }
    }

    @ViewBuilder
    private func row(for c: Contact) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.text.rectangle")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name.isEmpty
                     ? String(localized: "(未命名联系人)", locale: locale)
                     : c.name)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                if !c.email.isEmpty {
                    Text(c.email)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !c.phone.isEmpty {
                    Text(c.phone)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.dim)
        }
        .contentShape(Rectangle())
    }

    private func remove(_ c: Contact) {
        ContactsStorage.remove(id: c.id)
        contacts = ContactsStorage.find(builderID: builder.id)
    }

    private func handleSave(_ draft: Contact, target: ContactEditingTarget) {
        switch target {
        case .new:
            if ContactsStorage.add(draft) == nil {
                alertMessage = String(localized: "保存失败:姓名为空或已达上限。", locale: locale)
            }
        case .edit:
            if !ContactsStorage.update(draft) {
                alertMessage = String(localized: "保存失败:找不到原条目。", locale: locale)
            }
        }
        contacts = ContactsStorage.find(builderID: builder.id)
        editing = nil
    }
}

// MARK: - Editing target(联系人)

enum ContactEditingTarget: Identifiable {
    case new
    case edit(Contact)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let c): return c.id.uuidString
        }
    }

    /// 给 sheet 内 init 用的初始 Contact。.new 需要外部传 builderID 后再构造。
    func initialContact(builderID: UUID) -> Contact {
        switch self {
        case .new: return Contact(builderID: builderID)
        case .edit(let c): return c
        }
    }
}

// MARK: - Edit sheet(联系人)

private struct ContactEditSheet: View {
    /// 所属公司 — 新增时锁死 builderID,编辑时取 Contact 已有 builderID。
    let builderID: UUID
    let target: ContactEditingTarget
    let onSave: (Contact) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var email: String
    @State private var phone: String
    @State private var notes: String

    @State private var errorMessage: String?

    private var locale: Locale { AppLanguageManager.currentLocale }

    init(builderID: UUID,
         target: ContactEditingTarget,
         onSave: @escaping (Contact) -> Void) {
        self.builderID = builderID
        self.target = target
        self.onSave = onSave
        let initial = target.initialContact(builderID: builderID)
        _name = State(initialValue: initial.name)
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
                } header: {
                    SectionHeader(String(localized: "基本信息", locale: locale))
                }

                Section {
                    TextField(String(localized: "邮箱(可选)", locale: locale), text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(String(localized: "手机(可选)", locale: locale), text: $phone)
                        .keyboardType(.phonePad)
                } header: {
                    SectionHeader(String(localized: "联系方式", locale: locale))
                } footer: {
                    SectionFooter(String(localized: "邮箱用于「一键发邮件」(没填邮箱的联系人不会出现在收件人列表)。", locale: locale))
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

    private var canSave: Bool { !trimmedName.isEmpty }

    private func attemptSave() {
        guard !trimmedName.isEmpty else {
            errorMessage = String(localized: "姓名不能为空。", locale: locale)
            return
        }
        var draft = target.initialContact(builderID: builderID)
        draft.name = trimmedName
        draft.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(draft)
        dismiss()
    }
}
