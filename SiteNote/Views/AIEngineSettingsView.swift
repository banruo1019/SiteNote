//
//  AIEngineSettingsView.swift
//  SiteNote
//
//  AI 引擎设置页:选引擎(auto/openai/local)+ 填 OpenAI API Key + 选模型。
//  所有敏感数据(API key)走 Keychain,不进 UserDefaults。
//

import SwiftUI

struct AIEngineSettingsView: View {
    @AppStorage("settings.aiEngine") private var aiEngineRaw: String = AIEngine.auto.rawValue
    @AppStorage("settings.openAITextModel") private var textModel: String = "gpt-4o-mini"
    @AppStorage("settings.openAIVisionModel") private var visionModel: String = "gpt-4o-mini"
    @AppStorage("settings.openAIEmbeddingModel") private var embeddingModel: String = "text-embedding-3-small"
    @AppStorage(SettingsKeys.aiPolishEnabled) private var aiPolishEnabled: Bool = true
    @AppStorage(SettingsKeys.aiAutoTagEnabled) private var aiAutoTagEnabled: Bool = true

    @State private var apiKeyInput: String = ""
    @State private var hasKey: Bool = false
    @State private var showsTestResult: String?
    @State private var isTesting = false

    private var engine: Binding<AIEngine> {
        Binding(
            get: { AIEngine(rawValue: aiEngineRaw) ?? .auto },
            set: { aiEngineRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            engineSection
            featureSection
            openAISection
            statusSection
            privacySection
        }
        .navigationTitle("AI 辅助")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .onAppear { refreshKeyStatus() }
        .alert("测试结果", isPresented: Binding(
            get: { showsTestResult != nil },
            set: { if !$0 { showsTestResult = nil } }
        )) {
            Button("知道了") { showsTestResult = nil }
        } message: {
            Text(showsTestResult ?? "")
        }
    }

    // MARK: - 引擎选择

    private var engineSection: some View {
        Section {
            Picker("AI 引擎", selection: engine) {
                ForEach(AIEngine.allCases) { e in
                    Text(e.displayName).tag(e)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("引擎")
        } footer: {
            Text(engineHint)
                .font(.system(size: DesignTokens.FontSize.body))
        }
    }

    private var engineHint: String {
        switch engine.wrappedValue {
        case .auto:
            return "优先用 OpenAI(质量好),失败或未配置 key 时自动切到本地 Apple Intelligence。"
        case .openai:
            return "只用 OpenAI。数据(转写/照片)会发送到 OpenAI 服务器。需要配置下面的 API Key。"
        case .local:
            return "只用本地 Apple Intelligence。无需联网,数据不离开设备。要求 iPhone 15 Pro 及以上并在系统设置启用 Apple Intelligence。"
        }
    }

    // MARK: - 功能开关

    private var featureSection: some View {
        Section("功能") {
            Toggle("自动修复转写", isOn: $aiPolishEnabled)
                .font(.system(size: DesignTokens.FontSize.body))
            Toggle("自动推断标签", isOn: $aiAutoTagEnabled)
                .font(.system(size: DesignTokens.FontSize.body))
        }
    }

    // MARK: - OpenAI 配置

    private var openAISection: some View {
        Section {
            HStack {
                if hasKey {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("API Key 已保存")
                        .font(.system(size: DesignTokens.FontSize.body))
                } else {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text("未配置 API Key")
                        .font(.system(size: DesignTokens.FontSize.body))
                }
                Spacer()
                if hasKey {
                    Button("删除", role: .destructive) {
                        KeychainStorage.delete(for: KeychainKeys.openAIAPIKey)
                        refreshKeyStatus()
                    }
                    .font(.system(size: DesignTokens.FontSize.body))
                }
            }

            SecureField("sk-...", text: $apiKeyInput)
                .font(.system(size: DesignTokens.FontSize.body))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                saveKey()
            } label: {
                HStack {
                    Image(systemName: "key.fill")
                    Text(hasKey ? "更新 API Key" : "保存 API Key")
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    Spacer()
                }
            }
            .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)

            if hasKey {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                            Text("测试中...")
                        } else {
                            Image(systemName: "network")
                            Text("测试连通性")
                        }
                    }
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                }
                .disabled(isTesting)
            }

            Picker("文本模型", selection: $textModel) {
                Text("gpt-4o-mini(便宜快)").tag("gpt-4o-mini")
                Text("gpt-4o(质量高)").tag("gpt-4o")
                Text("gpt-4.1-mini").tag("gpt-4.1-mini")
                Text("gpt-4.1").tag("gpt-4.1")
            }
            .font(.system(size: DesignTokens.FontSize.body))

            Picker("视觉模型", selection: $visionModel) {
                Text("gpt-4o-mini").tag("gpt-4o-mini")
                Text("gpt-4o").tag("gpt-4o")
            }
            .font(.system(size: DesignTokens.FontSize.body))

            Picker("Embedding 模型(搜索)", selection: $embeddingModel) {
                Text("text-embedding-3-small(便宜)").tag("text-embedding-3-small")
                Text("text-embedding-3-large(精度高)").tag("text-embedding-3-large")
            }
            .font(.system(size: DesignTokens.FontSize.body))
        } header: {
            Text("OpenAI API 配置")
        } footer: {
            Text("API Key 保存在 iOS Keychain(加密存储),仅本机可用。可在 https://platform.openai.com/api-keys 获取。")
                .font(.system(size: DesignTokens.FontSize.body))
        }
    }

    // MARK: - 状态

    private var statusSection: some View {
        Section("当前状态") {
            statusRow(
                label: "OpenAI 文本/视觉",
                available: AIService.isOpenAIAvailable,
                hint: AIService.isOpenAIAvailable ? "已配置" : "未配置 API Key"
            )
            statusRow(
                label: "Apple Intelligence",
                available: AIService.isLocalAvailable,
                hint: AIService.isLocalAvailable ? "可用" : "机型或 iOS 不支持"
            )
            statusRow(
                label: "语义搜索 Embedding",
                available: SemanticSearchService.isAvailable,
                hint: semanticSearchHint
            )
        }
    }

    private var semanticSearchHint: String {
        if AIService.isOpenAIAvailable {
            return "OpenAI \(embeddingModel)"
        }
        if #available(iOS 17.0, *) {
            return "Apple 本地(中文)"
        }
        return "不可用(退回关键词子串)"
    }

    private func statusRow(label: String, available: Bool, hint: String) -> some View {
        HStack {
            Image(systemName: available ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(available ? Ink.fg : Ink.red)
            Text(label)
                .font(.system(size: DesignTokens.FontSize.body))
            Spacer()
            Text(hint)
                .font(.system(size: DesignTokens.FontSize.body))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 隐私声明

    private var privacySection: some View {
        Section("隐私") {
            Text("• 选择「OpenAI」或「自动(OpenAI 优先)」时,转写文本和照片会发送到 OpenAI 服务器处理。")
                .font(.system(size: DesignTokens.FontSize.body))
                .foregroundStyle(.secondary)
            Text("• 选择「仅本地」时,所有 AI 在设备内完成,不联网。")
                .font(.system(size: DesignTokens.FontSize.body))
                .foregroundStyle(.secondary)
            Text("• 如工地内容高度敏感,建议用本地引擎。")
                .font(.system(size: DesignTokens.FontSize.body))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func refreshKeyStatus() {
        hasKey = OpenAIClient.hasAPIKey
    }

    private func saveKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        if KeychainStorage.save(key, for: KeychainKeys.openAIAPIKey) {
            apiKeyInput = ""
            hasKey = true
        }
    }

    private func testConnection() {
        isTesting = true
        Task {
            do {
                let result = try await OpenAIClient.chat(user: "ping. 只回一个字:好")
                showsTestResult = "✅ 连通成功。响应: \(result.prefix(40))"
            } catch {
                showsTestResult = "❌ 失败: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
