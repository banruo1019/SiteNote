//
//  AIEngineSettingsView.swift
//  SiteNote
//
//  v1.2 大幅简化:
//  - 只保留 Apple Intelligence(本地)用于 AI 转写修复
//  - 删除 OpenAI Key / 引擎切换 / 模型选择 / 测试连通性 / 高级配置等
//  - 整页只显示 Apple Intelligence 可用状态
//
//  AIService.isLanguageModelAvailable 由主线保留为 static var。
//

import SwiftUI

struct AIEngineSettingsView: View {
    var body: some View {
        AIAdvancedSettingsView()
    }
}

struct AIAdvancedSettingsView: View {
    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: AIService.isLanguageModelAvailable ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(AIService.isLanguageModelAvailable ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AIService.isLanguageModelAvailable
                             ? "Apple Intelligence 已启用"
                             : "Apple Intelligence 不可用")
                            .font(.system(size: 14, weight: .semibold))
                        Text(AIService.isLanguageModelAvailable
                             ? "用于自动修复录音转写的口语化文字。"
                             : "需要 iPhone 15 Pro 及以上 + iOS 26 + 在系统设置启用 Apple Intelligence。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("AI 转写修复")
            } footer: {
                Text("v1.2 起仅使用本地 Apple Intelligence(无 OpenAI),数据不离开设备。Apple Intelligence 不可用时直接显示语音识别原文。")
                    .font(.system(size: 11))
            }
        }
        .navigationTitle("AI 辅助")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
    }
}
