//
//  EngineerSettingsRoot.swift
//  SiteNote
//
//  Engineer 角色专属设置主页(极简,5 sections / ~15 rows)。
//
//  设计动机:
//  - 原 SettingsView 是 PM-leaning,Engineer 用着 80% rows 是 PM 才需要的(日报提醒、AI tag、Obsidian 同步等)。
//  - 工程师常用配置 = 公司抬头(出现在 PDF) + 工地资源(工地/平面图/预设/建造商) + 报告免责声明 + 默认日程提醒 + 数据导出/语言。
//  - 这页是 Engineer 主屏 "我"/Settings tab 的根。完整 PDF 高级配置(Logo 宽高比、Obsidian) 留在 PM 版,不在这里展开。
//
//  风格约束:Form + .industrialForm() + SectionHeader/Footer。字符串走 String(localized:, locale:)。
//

import SwiftUI
import SwiftData
import UIKit
import PhotosUI

/// Engineer 角色的设置首页。5 section、~15 row,刻意保持薄。
struct EngineerSettingsRoot: View {
    // MARK: - 我和公司
    @AppStorage("settings.engineerCompanyName") private var companyName: String = ""
    @AppStorage("settings.engineerABN") private var abn: String = ""
    @State private var logoPickerItem: PhotosPickerItem?
    @State private var currentLogo: UIImage? = BrandingStorage.loadLogo()

    // MARK: - 工作资源(工地)
    @State private var siteTags: [String] = SiteTagsStorage.load()
    @State private var showsNewSiteSheet: Bool = false

    // MARK: - 日程默认提醒
    /// 取值:1440(1 天) / 60(1 小时) / 30(30 分钟) / 0(关闭)。
    @AppStorage("engineer.scheduleDefaultReminderMinutes") private var defaultReminderMinutes: Int = 60

    // MARK: - 语言
    @State private var languageManager = AppLanguageManager.shared
    @State private var showLanguageRestartHint = false
    @State private var showICloudRestartHint = false

    // MARK: - 数据导出 / 反馈
    @State private var backupShareURL: URL?
    @State private var backupError: String?
    @State private var feedbackShareItems: [Any]?

    private var locale: Locale { AppLanguageManager.currentLocale }

    var body: some View {
        Form {
            meAndCompanySection
            teamSection
            workResourcesSection
            reportSection
            scheduleSection
            dataAndAboutSection
        }
        .navigationTitle(String(localized: "设置", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .onChange(of: logoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   BrandingStorage.saveLogo(img) {
                    await MainActor.run {
                        currentLogo = BrandingStorage.loadLogo()
                    }
                }
                await MainActor.run {
                    logoPickerItem = nil
                }
            }
        }
        .sheet(isPresented: $showsNewSiteSheet) {
            NewSiteSheet { _, _ in
                siteTags = SiteTagsStorage.load()
            }
        }
        .sheet(item: Binding(
            get: { backupShareURL.map { EngineerSettingsBackupItem(url: $0) } },
            set: { _ in backupShareURL = nil }
        )) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(isPresented: Binding(
            get: { feedbackShareItems != nil },
            set: { if !$0 { feedbackShareItems = nil } }
        )) {
            if let items = feedbackShareItems {
                ShareSheet(items: items)
            }
        }
        .alert(
            String(localized: "备份出错", locale: locale),
            isPresented: Binding(
                get: { backupError != nil },
                set: { if !$0 { backupError = nil } }
            )
        ) {
            Button(String(localized: "知道了", locale: locale)) { backupError = nil }
        } message: {
            Text(backupError ?? "")
        }
        .alert(
            String(localized: "已切换语言", locale: locale),
            isPresented: $showLanguageRestartHint
        ) {
            Button(String(localized: "知道了", locale: locale), role: .cancel) { }
        } message: {
            Text(String(localized: "界面文字会立刻更新;少量错误信息和 PDF 文案需要重启 App 才完全切换。", locale: locale))
        }
        .alert(
            String(localized: "iCloud 同步设置已更新", locale: locale),
            isPresented: $showICloudRestartHint
        ) {
            Button(String(localized: "知道了", locale: locale), role: .cancel) { }
        } message: {
            Text(String(localized: "请完全退出 App(从后台划掉)再打开,新设置才会生效。本地数据已保留,不会丢失。", locale: locale))
        }
        .onAppear {
            siteTags = SiteTagsStorage.load()
            currentLogo = BrandingStorage.loadLogo()
        }
    }

    // MARK: - Section 1: 我和公司

    private var meAndCompanySection: some View {
        Section {
            NavigationLink {
                ProfileSettingsView()
            } label: {
                HStack {
                    Image(systemName: "person.crop.square")
                        .foregroundStyle(Ink.fg)
                    Text(String(localized: "我的角色", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body))
                }
            }

            HStack {
                Text(String(localized: "公司名", locale: locale))
                    .font(.system(size: DesignTokens.FontSize.body))
                    .frame(width: 80, alignment: .leading)
                TextField(
                    String(localized: "如 ABC Engineering Pty Ltd", locale: locale),
                    text: $companyName
                )
                .font(.system(size: DesignTokens.FontSize.body))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            }

            HStack {
                Text(String(localized: "ABN", locale: locale))
                    .font(.system(size: DesignTokens.FontSize.body))
                    .frame(width: 80, alignment: .leading)
                TextField(
                    String(localized: "11 位 ABN(可留空)", locale: locale),
                    text: $abn
                )
                .font(.system(size: DesignTokens.FontSize.body))
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
            }

            // 公司 Logo
            HStack {
                if let logo = currentLogo {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .background(Ink.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 24))
                        .foregroundStyle(Ink.fgDim)
                        .frame(width: 50, height: 50)
                        .background(Ink.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "公司 Logo", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    Text(currentLogo != nil
                        ? String(localized: "已上传", locale: locale)
                        : String(localized: "未上传", locale: locale)
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }

            PhotosPicker(selection: $logoPickerItem, matching: .images) {
                Label(
                    String(localized: "上传 / 替换 Logo", locale: locale),
                    systemImage: "photo.badge.plus"
                )
                .font(.system(size: DesignTokens.FontSize.body))
            }

            if currentLogo != nil {
                Button(role: .destructive) {
                    BrandingStorage.clearLogo()
                    currentLogo = nil
                } label: {
                    Label(
                        String(localized: "移除 Logo", locale: locale),
                        systemImage: "trash"
                    )
                    .font(.system(size: DesignTokens.FontSize.body))
                }
            }
        } header: {
            SectionHeader(String(localized: "我和公司", locale: locale))
        } footer: {
            SectionFooter(String(localized: "这些会出现在 PDF 报告封面。", locale: locale))
        }
    }

    // MARK: - Section: 团队

    private var teamSection: some View {
        Section {
            NavigationLink {
                TeamManagementView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(Ink.accent)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "我的团队", locale: AppLanguageManager.currentLocale))
                            .font(.system(size: 14, weight: .semibold))
                        Text(String(localized: "和工程师 / 老板协作 · 最多 10 人", locale: AppLanguageManager.currentLocale))
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
            }
        } header: {
            SectionHeader(String(localized: "团队", locale: AppLanguageManager.currentLocale))
        } footer: {
            SectionFooter(String(localized: "第一版免费;创建团队后可邀请最多 9 个成员协作。", locale: AppLanguageManager.currentLocale))
        }
    }

    // MARK: - Section 2: 工作资源

    private var workResourcesSection: some View {
        Section {
            // 工地列表 inline:工程师最常用,直接在 root 展开;新建按钮触发 NewSiteSheet。
            ForEach(siteTags, id: \.self) { tag in
                HStack {
                    Image(systemName: "building.2.fill")
                        .foregroundStyle(.green)
                    Text(tag)
                        .font(.system(size: DesignTokens.FontSize.body))
                    Spacer()
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        siteTags = SiteTagsStorage.remove(tag)
                    } label: {
                        Label(
                            String(localized: "删除", locale: locale),
                            systemImage: "trash"
                        )
                    }
                }
            }
            Button {
                showsNewSiteSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                    Text(String(localized: "新建工地", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NavigationLink {
                SitePresetEditorView()
            } label: {
                HStack {
                    Image(systemName: "building.2.crop.circle")
                        .foregroundStyle(.blue)
                    Text(String(localized: "工地预设", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body))
                }
            }

            NavigationLink {
                FloorPlanManageView()
            } label: {
                HStack {
                    Image(systemName: "map")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "平面图", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body))
                }
            }

            NavigationLink {
                BuildersEditorView()
            } label: {
                HStack {
                    Image(systemName: "person.text.rectangle")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "建造商联系簿", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body))
                }
            }
        } header: {
            SectionHeader(String(localized: "工作资源", locale: locale))
        } footer: {
            SectionFooter(String(localized: "首次使用建议先建工地 + 上传平面图。", locale: locale))
        }
    }

    // MARK: - Section 3: 报告

    private var reportSection: some View {
        Section {
            NavigationLink {
                DisclaimerEditorView()
            } label: {
                HStack {
                    Image(systemName: "doc.plaintext")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "默认免责声明", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body))
                }
            }
        } header: {
            SectionHeader(String(localized: "报告", locale: locale))
        } footer: {
            SectionFooter(String(localized: "PDF 封面会用这段免责声明。", locale: locale))
        }
    }

    // MARK: - Section 4: 日程

    private var scheduleSection: some View {
        Section {
            Picker(selection: $defaultReminderMinutes) {
                Text(String(localized: "1 天", locale: locale)).tag(1440)
                Text(String(localized: "1 小时", locale: locale)).tag(60)
                Text(String(localized: "30 分钟", locale: locale)).tag(30)
                Text(String(localized: "关闭", locale: locale)).tag(0)
            } label: {
                HStack {
                    Image(systemName: "bell")
                        .foregroundStyle(Ink.fg)
                    Text(String(localized: "默认提醒提前时间", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body))
                }
            }
        } header: {
            SectionHeader(String(localized: "日程", locale: locale))
        } footer: {
            SectionFooter(String(localized: "新建日程时默认带上这个提醒,可单独覆盖。", locale: locale))
        }
    }

    // MARK: - Section 5: 数据和关于

    private var dataAndAboutSection: some View {
        Section {
            // iCloud 同步开关。首次开启需 Apple ID + iCloud 容器配置就位。
            // 开关切换后**重启 App** 才完全生效(SwiftData 不支持 hot-swap ModelConfiguration)。
            Toggle(isOn: Binding(
                get: { ICloudSyncConfig.shared.isEnabled },
                set: { newValue in
                    ICloudSyncConfig.shared.isEnabled = newValue
                    showICloudRestartHint = true
                }
            )) {
                HStack {
                    Image(systemName: "icloud")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "iCloud 同步", locale: locale))
                            .font(.system(size: DesignTokens.FontSize.body))
                        Text(String(localized: "跨设备同步 + 团队协作的前置条件,重启 App 生效", locale: locale))
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
            }

            Button {
                exportBackup()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Ink.fg)
                    Text(String(localized: "导出全部数据 ZIP", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(Ink.fg)
                }
            }

            NavigationLink {
                SavedReportsView()
            } label: {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(Ink.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "我的报告", locale: locale))
                            .font(.system(size: DesignTokens.FontSize.body))
                        Text(String(localized: "导出过的 PDF 巡检日志 / SVR 报告", locale: locale))
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
            }

            NavigationLink {
                TrashView()
            } label: {
                HStack {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "垃圾桶", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body))
                }
            }

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
                HStack {
                    Image(systemName: "globe")
                        .foregroundStyle(.indigo)
                    Text(String(localized: "语言", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body))
                }
            }

            Button {
                openFeedback()
            } label: {
                HStack {
                    Image(systemName: "envelope")
                        .foregroundStyle(Ink.fg)
                    Text(String(localized: "反馈与建议", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(Ink.fg)
                    Spacer()
                    Text("banruostudio@gmail.com")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.fgDim)
                }
            }

            HStack {
                Text(String(localized: "版本", locale: locale))
                    .font(.system(size: DesignTokens.FontSize.body))
                Spacer()
                Text(appVersion)
                    .font(.system(size: DesignTokens.FontSize.body))
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader(String(localized: "数据和关于", locale: locale))
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (build: \(build))"
    }

    private func exportBackup() {
        do {
            let url = try BackupService.createBackupZip()
            backupShareURL = url
        } catch {
            backupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 反馈入口:有最新 crash JSON 走 ShareSheet 带附件,否则降级 mailto:。
    /// 行为与 DataAboutSettingsView.openFeedbackMail 保持一致。
    private func openFeedback() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        let iosVersion = UIDevice.current.systemVersion
        let device = UIDevice.current.model
        let body = String(
            localized: "请描述问题或建议:\n\n\n---\nSiteNote \(version) (\(build))\niOS \(iosVersion) · \(device)\n邮箱:banruostudio@gmail.com",
            locale: locale
        )

        if let crash = CrashReporter.latestCrashReport() {
            feedbackShareItems = [body, crash]
            return
        }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "banruostudio@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: String(localized: "SiteNote 反馈", locale: locale)),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }
}

/// 包装备份 URL 以满足 `.sheet(item:)` 的 Identifiable 要求。
/// 用单独的 struct 避免与 SettingsView 里同名的 `private struct BackupShareItem` 冲突。
private struct EngineerSettingsBackupItem: Identifiable {
    let id: UUID = UUID()
    let url: URL
}

#Preview {
    NavigationStack {
        EngineerSettingsRoot()
    }
}
