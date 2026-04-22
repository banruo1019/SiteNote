//
//  SubTagsEditorView.swift
//  SiteNote
//
//  全局子标签编辑器。子标签是独立的标签类型(RFI / 缺陷 / 施工 / 开会 / 紧急 ...),
//  和工地正交,不按工地隔离。
//

import SwiftUI

struct SubTagsEditorView: View {
    @State private var subs: [SubTag] = SubTagsStorage.load()
    @State private var showsAdd: Bool = false
    @State private var editingTag: SubTag?

    var body: some View {
        List {
            if subs.isEmpty {
                Section {
                    VStack(spacing: DesignTokens.Spacing.small) {
                        Image(systemName: "tag")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 20)
                        Text("还没有子标签")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        Text("常用分类:RFI、缺陷、施工、开会、紧急、个人")
                            .font(.system(size: DesignTokens.FontSize.body))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else {
                Section {
                    ForEach(subs) { sub in
                        Button {
                            editingTag = sub
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(sub.color)
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
                                    )
                                Text(sub.name)
                                    .font(.system(size: DesignTokens.FontSize.body))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "pencil.circle")
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                subs = SubTagsStorage.remove(id: sub.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text("左滑删除。点行可以改颜色和名字。子标签是全局的,不分工地。颜色会用在平面图图钉上。")
                        .font(.system(size: 12))
                }
            }

            Section {
                Button {
                    showsAdd = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("新建子标签")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("子标签")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .onAppear { subs = SubTagsStorage.load() }
        .sheet(isPresented: $showsAdd) {
            NewSubTagSheet { newTag in
                subs = SubTagsStorage.add(newTag)
            }
        }
        .sheet(item: $editingTag) { tag in
            EditSubTagSheet(tag: tag) { updated in
                subs = SubTagsStorage.update(updated)
            }
        }
    }
}

/// 编辑已有子标签(改名字 / 改颜色)。
private struct EditSubTagSheet: View {
    let tag: SubTag
    let onSaved: (SubTag) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorName: String

    init(tag: SubTag, onSaved: @escaping (SubTag) -> Void) {
        self.tag = tag
        self.onSaved = onSaved
        _name = State(initialValue: tag.name)
        _colorName = State(initialValue: tag.colorName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text("名字")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("", text: $name)
                            .font(.system(size: DesignTokens.FontSize.body))
                            .padding(DesignTokens.Spacing.medium)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text("颜色")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                            spacing: 14
                        ) {
                            ForEach(SubTag.availableColorNames, id: \.self) { c in
                                Button {
                                    colorName = c
                                } label: {
                                    Circle()
                                        .fill(SubTag.color(from: c))
                                        .frame(width: 42, height: 42)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    colorName == c ? Color.primary : Color.black.opacity(0.15),
                                                    lineWidth: colorName == c ? 3 : 1
                                                )
                                        )
                                        .overlay {
                                            if colorName == c {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text("预览")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(SubTag.color(from: colorName))
                                .frame(width: 10, height: 10)
                            Text(name.isEmpty ? "(名字)" : name)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(SubTag.color(from: colorName))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(SubTag.color(from: colorName).opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
                .padding()
            }
            .navigationTitle("编辑子标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSaved(SubTag(id: tag.id, name: trimmed, colorName: colorName))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .bold()
                }
            }
        }
    }
}
