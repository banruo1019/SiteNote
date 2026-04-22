//
//  TemplateEditorView.swift
//  SiteNote
//
//  编辑一个巡检模板(名字 + 检查项列表)。新建或编辑同一个视图。
//

import SwiftUI

/// 编辑/新建巡检模板。
struct TemplateEditorView: View {
    /// 传入 nil 表示新建;非 nil 表示编辑现有模板。
    let existing: InspectionTemplate?

    @State private var name: String = ""
    @State private var items: [String] = []
    @State private var newItemText: String = ""
    @Environment(\.dismiss) private var dismiss

    private var isNew: Bool { existing == nil }

    var body: some View {
        Form {
            Section("名字") {
                TextField("例如: 安全日检", text: $name)
                    .font(.system(size: DesignTokens.FontSize.body))
            }

            Section {
                if items.isEmpty {
                    Text("(还没有检查项)")
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.system(size: DesignTokens.FontSize.body))
                    }
                    .onDelete { offsets in
                        items.remove(atOffsets: offsets)
                    }
                    .onMove { indices, newOffset in
                        items.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }

                HStack {
                    TextField("新检查项", text: $newItemText)
                        .font(.system(size: DesignTokens.FontSize.body))
                    Button("添加") {
                        addItem()
                    }
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("检查项")
            } footer: {
                Text("长按拖动可以排序;左滑删除。")
                    .font(.system(size: DesignTokens.FontSize.body))
            }
        }
        .navigationTitle(isNew ? "新建模板" : "编辑模板")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .disabled(isSaveDisabled)
            }
        }
        .onAppear {
            if let existing {
                name = existing.name
                items = existing.items
            }
        }
    }

    /// 提出来避免 toolbar 里的表达式太复杂导致 Swift 类型检查超时。
    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || items.isEmpty
    }

    private func addItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(trimmed)
        newItemText = ""
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !items.isEmpty else { return }

        if let existing {
            var updated = existing
            updated.name = trimmedName
            updated.items = items
            InspectionTemplatesStorage.update(updated)
        } else {
            let new = InspectionTemplate(name: trimmedName, items: items)
            InspectionTemplatesStorage.add(new)
        }
        dismiss()
    }
}
