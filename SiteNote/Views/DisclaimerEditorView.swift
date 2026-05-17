//
//  DisclaimerEditorView.swift
//  SiteNote
//
//  巡检报告默认免责声明编辑器。导出 Inspection PDF 时,如果 InspectionDraft
//  没自带 disclaimer,会用这里的内容(空则回退 DisclaimerStorage.defaults)。
//

import SwiftUI

struct DisclaimerEditorView: View {
    /// 当前正在编辑的列表(可能是已保存的自定义,也可能是 defaults 副本)。
    @State private var items: [String] = []

    /// 用户是否动过(决定"保存"按钮是否高亮)。
    @State private var isDirty: Bool = false

    /// "恢复默认"二次确认。
    @State private var showRestoreConfirm: Bool = false

    /// 顶部提示(保存成功 / 恢复成功)。
    @State private var topMessage: String?

    private var locale: Locale { AppLanguageManager.currentLocale }

    /// 当前用户自定义是否生效(非空 = 用了自定义)。
    private var hasCustom: Bool {
        !DisclaimerStorage.load().isEmpty
    }

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
                ForEach(items.indices, id: \.self) { idx in
                    TextEditor(text: Binding(
                        get: { idx < items.count ? items[idx] : "" },
                        set: { newValue in
                            guard idx < items.count else { return }
                            items[idx] = newValue
                            isDirty = true
                        }
                    ))
                    .font(.system(size: DesignTokens.FontSize.body))
                    .frame(minHeight: 80)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            remove(at: idx)
                        } label: {
                            Label(String(localized: "删除", locale: locale),
                                  systemImage: "trash")
                        }
                    }
                }

                Button {
                    items.append("")
                    isDirty = true
                } label: {
                    Label(String(localized: "新增一条", locale: locale),
                          systemImage: "plus.circle")
                }
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
            } header: {
                SectionHeader(String(localized: "免责声明 (\(items.count))", locale: locale))
            } footer: {
                SectionFooter(String(
                    localized: "导出 Inspection PDF 时用到。空表示用默认 5 条。",
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
            } footer: {
                SectionFooter(hasCustom
                     ? String(localized: "当前生效:自定义。", locale: locale)
                     : String(localized: "当前生效:默认 5 条。", locale: locale))
            }
        }
        .industrialForm()
        .navigationTitle(String(localized: "巡检免责声明", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reload()
        }
        .alert(String(localized: "恢复默认?", locale: locale),
               isPresented: $showRestoreConfirm) {
            Button(String(localized: "恢复", locale: locale), role: .destructive) {
                restoreDefaults()
            }
            Button(String(localized: "取消", locale: locale), role: .cancel) {}
        } message: {
            Text(String(localized: "会清除你自定义的内容,恢复到内置的 5 条标准 disclaimer。", locale: locale))
        }
    }

    // MARK: - Actions

    private func reload() {
        // 用户存过的优先;没存过就把 defaults 拷一份给用户编辑。
        let custom = DisclaimerStorage.load()
        items = custom.isEmpty ? DisclaimerStorage.defaults : custom
        isDirty = false
    }

    private func remove(at idx: Int) {
        guard idx < items.count else { return }
        items.remove(at: idx)
        isDirty = true
    }

    private func save() {
        DisclaimerStorage.save(items)
        // save 里会过滤空白条目,这里同步 UI。
        let saved = DisclaimerStorage.load()
        items = saved.isEmpty ? DisclaimerStorage.defaults : saved
        isDirty = false
        showTopMessage(String(localized: "已保存。", locale: locale))
    }

    private func restoreDefaults() {
        DisclaimerStorage.restoreDefaults()
        items = DisclaimerStorage.defaults
        isDirty = false
        showTopMessage(String(localized: "已恢复默认 5 条。", locale: locale))
    }

    private func showTopMessage(_ msg: String) {
        topMessage = msg
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            topMessage = nil
        }
    }
}
