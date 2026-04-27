//
//  JargonTermsEditorView.swift
//  SiteNote
//
//  用户自定义"专业词汇"编辑器。一行一个词,加进去后会被喂给:
//  - SFSpeechRecognizer.contextualStrings (无模型转录的 hint,提升识别)
//  - AIService.polishTranscription 的 prompt context (告诉 AI 不要瞎改)
//
//  限制:每词 ≤30 字符(Apple SFSpeechRecognizer 的硬要求)。
//

import SwiftUI

struct JargonTermsEditorView: View {
    @State private var terms: [String] = JargonStorage.loadCustomTerms()
    @State private var newTerm: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        Form {
            Section {
                if terms.isEmpty {
                    Text("还没有自定义词。下面输入框加一个试试。")
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.fgDim)
                } else {
                    ForEach(terms, id: \.self) { term in
                        HStack {
                            Image(systemName: "text.bubble")
                                .foregroundStyle(Ink.fgDim)
                                .frame(width: 18)
                            Text(term)
                                .font(.system(size: DesignTokens.FontSize.body))
                            Spacer()
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                remove(term)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("自定义词汇 (\(terms.count))")
            } footer: {
                Text("这些词会让语音识别**更准**(听到时优先匹配)+ AI 修文本时**不瞎改**(保留原样)。\n\n适合加:你公司/工地的专属称呼、自家产品名、上级单位、本地俚语等系统不知道的词。\n\n基础词典(澳洲工地通用 100+ 词)已经内置,**不用重复加** AS4000 / RFI / 钢筋 / concrete 这些。")
                    .font(.system(size: 12))
            }

            Section {
                HStack {
                    TextField("新词(≤30 字符)", text: $newTerm)
                        .font(.system(size: DesignTokens.FontSize.body))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($inputFocused)
                        .onSubmit { add() }
                    Button("添加") { add() }
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .disabled(!canAdd)
                }
            } header: {
                Text("新增")
            } footer: {
                Text("回车直接加。重复的不会重复存。超过 30 字符会被丢弃。")
                    .font(.system(size: 12))
            }
        }
        .industrialForm()
        .navigationTitle("专业词汇")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canAdd: Bool {
        let t = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t.count <= 30
    }

    private func add() {
        guard canAdd else { return }
        terms = JargonStorage.addCustomTerm(newTerm)
        newTerm = ""
        inputFocused = true
    }

    private func remove(_ term: String) {
        terms = JargonStorage.removeCustomTerm(term)
    }
}
