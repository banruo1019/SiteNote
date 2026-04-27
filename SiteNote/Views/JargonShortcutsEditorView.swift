//
//  JargonShortcutsEditorView.swift
//  SiteNote
//
//  用户自定义"快捷词"编辑器。一对替换:from → to。
//
//  例:from = "打 con", to = "打 concrete"
//      你说"打 con",系统在 AI 修文本之前先把这个替换掉,保存的就是"打 concrete"。
//
//  和"专业词汇"的区别:
//  - 专业词汇 = 给系统一个 hint,让识别得对(听准了就保留)
//  - 快捷词   = 主动改写文本,让你说短话也能存全文
//

import SwiftUI

struct JargonShortcutsEditorView: View {
    @State private var shortcuts: [JargonStorage.Shortcut] = JargonStorage.loadShortcuts()
    @State private var newFrom: String = ""
    @State private var newTo: String = ""

    var body: some View {
        Form {
            Section {
                if shortcuts.isEmpty {
                    Text("还没有快捷词。")
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.fgDim)
                } else {
                    ForEach(shortcuts) { sc in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sc.from)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Ink.fg)
                                Text("说这个")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Ink.dim)
                            }
                            Image(systemName: "arrow.right")
                                .foregroundStyle(Ink.fgDim)
                                .font(.system(size: 12, weight: .semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sc.to)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Ink.fg)
                                Text("存这个")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Ink.dim)
                            }
                            Spacer()
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                remove(sc.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("已有 \(shortcuts.count) 条")
            } footer: {
                Text("你说的话被识别成 from(左边)→ AI 修文本之前先替换为 to(右边)→ 存的就是 to。\n\n例子: 打 con → 打 concrete · 走 RFI → 提交 RFI · 出 ITP → 准备 ITP\n\n大小写敏感。同 from 重复加会**覆盖**旧的。")
                    .font(.system(size: 12))
            }

            Section {
                TextField("from(说的简称)", text: $newFrom)
                    .font(.system(size: DesignTokens.FontSize.body))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("to(自动替换为)", text: $newTo)
                    .font(.system(size: DesignTokens.FontSize.body))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    add()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("添加这一对")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    }
                }
                .disabled(!canAdd)
            } header: {
                Text("新增")
            } footer: {
                Text("两个都填了才能加。")
                    .font(.system(size: 12))
            }
        }
        .industrialForm()
        .navigationTitle("快捷词")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canAdd: Bool {
        !newFrom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !newTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        guard canAdd else { return }
        shortcuts = JargonStorage.addShortcut(from: newFrom, to: newTo)
        newFrom = ""
        newTo = ""
    }

    private func remove(_ id: UUID) {
        shortcuts = JargonStorage.removeShortcut(id: id)
    }
}
