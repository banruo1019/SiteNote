//
//  EngineerSettingsRoot.swift
//  SiteNote
//
//  统一设置主页(PM / Engineer 共用)。M1 卡片布局:
//  - 顶部黑底大卡:当前角色 + "切换" 胶囊
//  - 灰小段头 + 白底圆角矩形 row(描边 + 内嵌图标方块)
//  - 工地 + 建造商联系簿 在同一张卡里(中间 hairline)
//  - 通知段 3 行也在同一张卡里(默认提醒 / 每日汇总 / 早上推送)
//  - 数据和关于段沿用旧 row,但视觉对齐
//

import SwiftUI
import SwiftData
import UIKit

struct EngineerSettingsRoot: View {

    // 日程默认提醒(分钟)
    @AppStorage("engineer.scheduleDefaultReminderMinutes") private var defaultReminderMinutes: Int = 60

    // 早上推送 + 每日汇总(合并自 RemindersSettingsView)
    @AppStorage(SettingsKeys.morningReminderHour) private var morningHour: Int = 7
    @AppStorage(SettingsKeys.morningReminderMinute) private var morningMinute: Int = 30
    @AppStorage(SettingsKeys.dailyDigestEnabled) private var dailyDigestEnabled: Bool = false

    // 语言
    @State private var languageManager = AppLanguageManager.shared
    @State private var showLanguageRestartHint = false
    @State private var showICloudRestartHint = false

    // 数据导出 / 反馈
    @State private var backupShareURL: URL?
    @State private var backupError: String?
    @State private var feedbackShareItems: [Any]?

    @State private var profileManager = UserProfileManager.shared

    @Environment(\.modelContext) private var modelContext

    private var locale: Locale { AppLanguageManager.currentLocale }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                roleCard
                companyGroup
                teamGroup
                siteGroup
                reportGroup
                notificationsGroup
                dataAndAboutGroup
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "设置", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
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
    }

    // MARK: - 角色卡(黑底大卡)

    private var roleCard: some View {
        NavigationLink {
            ProfileSettingsView()
        } label: {
            HStack(spacing: 12) {
                Text(roleGlyph)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Ink.bg)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "当前角色", locale: locale))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.white.opacity(0.55))
                    Text(profileManager.current.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Ink.bg)
                    Text(profileManager.current.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Text(String(localized: "切换", locale: locale))
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Ink.bg)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.14))
                .clipShape(Capsule())
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Ink.fg)
            )
        }
        .buttonStyle(.plain)
    }

    /// 角色的 1 字 emoji-glyph(PM = "P",Engineer = "工")。
    private var roleGlyph: String {
        switch profileManager.current {
        case .pm: return "P"
        case .engineer: return "工"
        }
    }

    // MARK: - 公司段

    private var companyGroup: some View {
        groupBlock(
            header: String(localized: "公司", locale: locale),
            footer: String(localized: "这些会出现在 PDF 报告封面。", locale: locale)
        ) {
            cardContainer {
                navRow(
                    icon: "doc.text",
                    title: String(localized: "公司信息", locale: locale),
                    sub: String(localized: "公司名 · ABN · Logo", locale: locale),
                    isLast: true
                ) {
                    CompanyInfoSettingsView()
                }
            }
        }
    }

    // MARK: - 团队段

    private var teamGroup: some View {
        groupBlock(
            header: String(localized: "团队", locale: locale),
            footer: String(localized: "第一版免费;创建团队后可邀请最多 9 个成员协作。", locale: locale)
        ) {
            cardContainer {
                navRow(
                    icon: "person.3",
                    title: String(localized: "我的团队", locale: locale),
                    sub: String(localized: "最多 10 人 · 第一版免费", locale: locale),
                    isLast: true
                ) {
                    TeamManagementView()
                }
            }
        }
    }

    // MARK: - 工地段(工地 + 建造商联系簿 同一张卡)

    private var siteGroup: some View {
        groupBlock(
            header: String(localized: "工地", locale: locale),
            footer: String(localized: "工地内部包含 平面图 / 工地预设 / 子标签。建造商联系簿独立管理。", locale: locale)
        ) {
            cardContainer {
                navRow(
                    icon: "building.2",
                    title: String(localized: "工地", locale: locale),
                    sub: String(localized: "含 平面图、巡检模板", locale: locale),
                    isLast: false
                ) {
                    SitePresetEditorView()
                }
                cardDivider
                navRow(
                    icon: "person.text.rectangle",
                    title: String(localized: "建造商联系簿", locale: locale),
                    sub: String(localized: "Inspection PDF 收件人", locale: locale),
                    isLast: true
                ) {
                    BuildersEditorView()
                }
            }
        }
    }

    // MARK: - 报告段

    private var reportGroup: some View {
        groupBlock(
            header: String(localized: "报告", locale: locale),
            footer: String(localized: "PDF 封面会用这段免责声明。", locale: locale)
        ) {
            cardContainer {
                navRow(
                    icon: "doc.plaintext",
                    title: String(localized: "默认免责声明", locale: locale),
                    sub: nil,
                    isLast: true
                ) {
                    DisclaimerEditorView()
                }
            }
        }
    }

    // MARK: - 通知段(3 行同卡:默认提醒 / 每日汇总 / 早上推送)

    private var notificationsGroup: some View {
        groupBlock(
            header: String(localized: "通知", locale: locale),
            footer: String(localized: "默认提醒会带进新建日程,可单独覆盖。每日汇总用上方时间推送。", locale: locale)
        ) {
            cardContainer {
                defaultReminderRow
                cardDivider
                dailyDigestRow
                cardDivider
                morningTimeRow
            }
        }
    }

    /// 默认提醒提前时间:点开 Menu 选择,右侧显示当前值 + chevron。
    private var defaultReminderRow: some View {
        Menu {
            Button { defaultReminderMinutes = 1440 } label: {
                rowLabel(String(localized: "1 天", locale: locale),
                         checked: defaultReminderMinutes == 1440)
            }
            Button { defaultReminderMinutes = 60 } label: {
                rowLabel(String(localized: "1 小时", locale: locale),
                         checked: defaultReminderMinutes == 60)
            }
            Button { defaultReminderMinutes = 30 } label: {
                rowLabel(String(localized: "30 分钟", locale: locale),
                         checked: defaultReminderMinutes == 30)
            }
            Button { defaultReminderMinutes = 0 } label: {
                rowLabel(String(localized: "关闭", locale: locale),
                         checked: defaultReminderMinutes == 0)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "默认提醒提前时间", locale: locale))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.fg)
                    Text(String(localized: "新建日程时预填", locale: locale))
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                }
                Spacer()
                Text(defaultReminderLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.fg2)
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.dim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }

    private var defaultReminderLabel: String {
        switch defaultReminderMinutes {
        case 1440: return String(localized: "1 天", locale: locale)
        case 60: return String(localized: "1 小时", locale: locale)
        case 30: return String(localized: "30 分钟", locale: locale)
        case 0: return String(localized: "关闭", locale: locale)
        default: return "\(defaultReminderMinutes)m"
        }
    }

    /// 每日汇总 toggle 行。
    private var dailyDigestRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "每日汇总", locale: locale))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.fg)
                Text(String(localized: "每天早上推一条今日任务", locale: locale))
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { dailyDigestEnabled },
                set: { newValue in
                    dailyDigestEnabled = newValue
                    NotificationService.shared.updateDailyDigest()
                }
            ))
            .labelsHidden()
            .tint(Ink.fg)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// 早上推送时间行 — DatePicker compact 样式贴右。
    private var morningTimeRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "早上推送时间", locale: locale))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.fg)
            }
            Spacer()
            DatePicker(
                "",
                selection: morningTimeBinding,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .onChange(of: morningHour) { _, _ in rescheduleAfterTimeChange() }
            .onChange(of: morningMinute) { _, _ in rescheduleAfterTimeChange() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// 早上时间的 Binding。
    private var morningTimeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = morningHour
                c.minute = morningMinute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                morningHour = comps.hour ?? morningHour
                morningMinute = comps.minute ?? morningMinute
            }
        )
    }

    private func rescheduleAfterTimeChange() {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.deletedAt == nil && $0.isDone == false }
        )
        let notes = (try? modelContext.fetch(descriptor)) ?? []
        NotificationService.shared.rescheduleAll(notes: notes)
    }

    // MARK: - 数据和关于段

    private var dataAndAboutGroup: some View {
        groupBlock(
            header: String(localized: "数据和关于", locale: locale),
            footer: nil
        ) {
            cardContainer {
                iCloudRow
                cardDivider
                exportBackupRow
                cardDivider
                navRow(
                    icon: "folder",
                    title: String(localized: "我的报告", locale: locale),
                    sub: String(localized: "导出过的 PDF 巡检日志 / SVR 报告", locale: locale),
                    isLast: false
                ) {
                    SavedReportsView()
                }
                cardDivider
                navRow(
                    icon: "trash",
                    title: String(localized: "垃圾桶", locale: locale),
                    sub: nil,
                    isLast: false
                ) {
                    TrashView()
                }
                cardDivider
                languageRow
                cardDivider
                feedbackRow
                cardDivider
                versionRow
            }
        }
    }

    private var iCloudRow: some View {
        HStack(spacing: 12) {
            iconBox(systemName: "icloud")
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "iCloud 同步", locale: locale))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.fg)
                Text(String(localized: "跨设备同步 + 团队协作的前置条件,重启 App 生效", locale: locale))
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { ICloudSyncConfig.shared.isEnabled },
                set: { newValue in
                    ICloudSyncConfig.shared.isEnabled = newValue
                    showICloudRestartHint = true
                }
            ))
            .labelsHidden()
            .tint(Ink.fg)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var exportBackupRow: some View {
        Button {
            exportBackup()
        } label: {
            HStack(spacing: 12) {
                iconBox(systemName: "square.and.arrow.up")
                Text(String(localized: "导出全部数据 ZIP", locale: locale))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.fg)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.dim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var languageRow: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    let oldId = languageManager.current.localeIdentifier
                    languageManager.current = lang
                    if oldId != lang.localeIdentifier {
                        showLanguageRestartHint = true
                    }
                } label: {
                    rowLabel(lang.displayName, checked: languageManager.current == lang)
                }
            }
        } label: {
            HStack(spacing: 12) {
                iconBox(systemName: "globe")
                Text(String(localized: "语言", locale: locale))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.fg)
                Spacer()
                Text(languageManager.current.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.fg2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.dim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }

    private var feedbackRow: some View {
        Button {
            openFeedback()
        } label: {
            HStack(spacing: 12) {
                iconBox(systemName: "envelope")
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "反馈与建议", locale: locale))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.fg)
                    Text("banruostudio@gmail.com")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.dim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var versionRow: some View {
        HStack(spacing: 12) {
            iconBox(systemName: "info.circle")
            Text(String(localized: "版本", locale: locale))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ink.fg)
            Spacer()
            Text(appVersion)
                .font(.system(size: 12))
                .foregroundStyle(Ink.fgDim)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 通用 building blocks

    /// 一段 group:tiny header + 卡片内容 + 可选 tiny footer。
    @ViewBuilder
    private func groupBlock<Content: View>(
        header: String,
        footer: String?,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Ink.fgDim)
                .padding(.horizontal, 4)
            content()
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
                    .padding(.horizontal, 4)
                    .lineSpacing(2)
            }
        }
    }

    /// 白底圆角卡片容器。
    @ViewBuilder
    private func cardContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Ink.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Ink.line, lineWidth: 1)
        )
    }

    /// 卡内行间分隔线 — 左缩进让 icon 列连贯。
    private var cardDivider: some View {
        Rectangle()
            .fill(Ink.line)
            .frame(height: 1)
            .padding(.leading, 14)
    }

    /// 标准 navigation row(icon + title + sub + chevron),整行可点。
    @ViewBuilder
    private func navRow<Destination: View>(
        icon: String,
        title: String,
        sub: String?,
        isLast: Bool,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                iconBox(systemName: icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.fg)
                    if let sub {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.fgDim)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.dim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 行首小图标方块 — 灰描边 + 黑 icon。
    private func iconBox(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Ink.fg)
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Ink.line2, lineWidth: 1)
            )
    }

    /// Menu 内的勾选行 — checkmark + 文本。
    private func rowLabel(_ text: String, checked: Bool) -> some View {
        HStack {
            Text(text)
            if checked {
                Image(systemName: "checkmark")
            }
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func exportBackup() {
        do {
            let url = try BackupService.createBackupZip()
            backupShareURL = url
        } catch {
            backupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 反馈入口:有最新 crash JSON 走 ShareSheet,否则 mailto:。
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

/// 包装备份 URL 以满足 `.sheet(item:)` 的 Identifiable。
private struct EngineerSettingsBackupItem: Identifiable {
    let id: UUID = UUID()
    let url: URL
}

#Preview {
    NavigationStack {
        EngineerSettingsRoot()
    }
}
