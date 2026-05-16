//
//  PMSettingsView.swift
//  SiteNote
//
//  PM(项目经理)Profile 的设置首页。原 SettingsView 的 Form 抽出来独立。
//  Engineer 走 EngineerSettingsRoot;这里只服务 PM。
//

import SwiftUI

struct PMSettingsView: View {
    @State private var profileManager = UserProfileManager.shared
    @State private var languageManager = AppLanguageManager.shared
    @State private var showLanguageRestartHint = false

    var body: some View {
        Form {
            // 我是 — 角色切换(决定主屏分组 / AI 重点 / 默认 PDF)
            Section {
                NavigationLink {
                    ProfileSettingsView()
                } label: {
                    settingsRow(
                        icon: profileManager.current.sfSymbol,
                        color: profileColor(profileManager.current),
                        title: "我是 \(profileManager.current.displayName)",
                        subtitle: LocalizedStringKey(profileManager.current.subtitle)
                    )
                }
            } header: {
                Text("角色")
            } footer: {
                Text("决定主屏分组、AI 识别重点、默认导出 PDF 模板。可随时切换。")
                    .font(.system(size: 12))
            }

            // 语言 — 三档:跟随系统 / 简体中文 / English
            Section {
                Picker(selection: Binding(
                    get: { languageManager.current },
                    set: { newValue in
                        let oldId = languageManager.current.localeIdentifier
                        languageManager.current = newValue
                        if oldId != newValue.localeIdentifier {
                            showLanguageRestartHint = true
                        }
                    }
                )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                } label: {
                    Label {
                        Text("语言")
                    } icon: {
                        Image(systemName: "globe")
                            .foregroundStyle(.indigo)
                    }
                }
            } header: {
                Text("语言")
            } footer: {
                Text("界面立即切换;部分错误信息和 PDF 文案需重启 App 完全生效。")
                    .font(.system(size: 12))
            }

            // 常用 — 日常会反复打开:提醒时间、清数据
            Section("常用") {
                NavigationLink {
                    RemindersSettingsView()
                } label: {
                    settingsRow(
                        icon: "bell.badge",
                        color: .orange,
                        title: "提醒",
                        subtitle: "推送时间、每日汇总"
                    )
                }
                NavigationLink {
                    SavedReportsView()
                } label: {
                    settingsRow(
                        icon: "folder",
                        color: .blue,
                        title: "我的报告",
                        subtitle: "已导出 PDF + iCloud 同步状态"
                    )
                }
                NavigationLink {
                    DataAboutSettingsView()
                } label: {
                    settingsRow(
                        icon: "gearshape.2",
                        color: .gray,
                        title: "数据与关于",
                        subtitle: "清除已完成、版本、反馈"
                    )
                }
            }

            // 高级 — 工地资源 / Logo / 数据导出 / 模板 (重度配置类)
            Section("高级") {
                NavigationLink {
                    SiteResourcesSettingsView()
                } label: {
                    settingsRow(
                        icon: "building.2",
                        color: .green,
                        title: "工地资源",
                        subtitle: "工地标签、平面图、巡检模板、合同条款"
                    )
                }
            }

            // AI — 总开关 + 高级配置
            Section("AI") {
                NavigationLink {
                    InputAISettingsView()
                } label: {
                    settingsRow(
                        icon: "mic.and.signal.meter",
                        color: .blue,
                        title: "录入与 AI",
                        subtitle: "识别语言、AI 总开关与配置"
                    )
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .alert("已切换语言", isPresented: $showLanguageRestartHint) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("界面文字会立刻更新;少量错误信息和 PDF 文案需要重启 App 才完全切换。")
        }
    }

    private func profileColor(_ kind: ProfileKind) -> Color {
        switch kind {
        case .pm: return .orange
        case .engineer: return .blue
        }
    }

    @ViewBuilder
    private func settingsRow(icon: String, color: Color, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: DesignTokens.FontSize.body))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
