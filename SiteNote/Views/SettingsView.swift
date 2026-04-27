//
//  SettingsView.swift
//  SiteNote
//
//  设置首页(P1-3 简化后):3 组导航 — 常用 / 工地资源 / AI。
//  原 5 个子页全部保留,只是入口归类。每组具体项在各自子页。
//

import SwiftUI
import SwiftData
import UIKit
import UserNotifications

/// 设置首页。3 组导航(P1-3)。
struct SettingsView: View {
    var body: some View {
        Form {
            // 常用 — 日常会反复打开:提醒时间、导出报告、清数据
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
                    ReportsExportSettingsView()
                } label: {
                    settingsRow(
                        icon: "doc.text",
                        color: .purple,
                        title: "报告与导出",
                        subtitle: "周报、EOT、PDF、ZIP"
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

            // 工地资源 — 配置类:工地、平面图、模板、条款
            Section("工地资源") {
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
    }

    @ViewBuilder
    private func settingsRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
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

// MARK: - 子页 1:录入与 AI

struct InputAISettingsView: View {
    @AppStorage(SettingsKeys.speechLanguage) private var speechLanguage: String = "zh-CN"

    var body: some View {
        Form {
            Section("语音识别") {
                Picker("识别语言", selection: $speechLanguage) {
                    Text("中文").tag("zh-CN")
                    Text("英文").tag("en-US")
                }
                .font(.system(size: DesignTokens.FontSize.body))
            }

            Section {
                NavigationLink {
                    JargonTermsEditorView()
                } label: {
                    HStack {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(Ink.fg)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("专业词汇")
                                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            Text("自家专属词,加进去识别更准 + AI 不瞎改")
                                .font(.system(size: 12))
                                .foregroundStyle(Ink.fgDim)
                        }
                    }
                }
                NavigationLink {
                    JargonShortcutsEditorView()
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.swap")
                            .foregroundStyle(Ink.fg)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("快捷词")
                                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            Text("说短话自动展开,如「打 con」→「打 concrete」")
                                .font(.system(size: 12))
                                .foregroundStyle(Ink.fgDim)
                        }
                    }
                }
            } header: {
                Text("识别词典")
            } footer: {
                Text("基础词典(澳洲工地通用 100+ 词)已内置,这里只配你公司/工地的专属词。")
                    .font(.system(size: 12))
            }

            Section {
                NavigationLink {
                    AIEngineSettingsView()
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Ink.fg)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI 辅助设置")
                                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            Text(aiQuickStatus)
                                .font(.system(size: DesignTokens.FontSize.body))
                                .foregroundStyle(Ink.fgDim)
                        }
                    }
                }
            } header: {
                Text("AI 辅助")
            } footer: {
                Text("选择引擎(OpenAI / 本地)、填 API Key、切换功能开关。")
                    .font(.system(size: DesignTokens.FontSize.body))
            }
        }
        .navigationTitle("录入与 AI")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
    }

    private var aiQuickStatus: String {
        let engine = AIService.currentEngine
        var parts: [String] = []
        switch engine {
        case .auto: parts.append("自动")
        case .openai: parts.append("OpenAI")
        case .local: parts.append("本地")
        }
        if AIService.isOpenAIAvailable { parts.append("OpenAI ✓") }
        if AIService.isLocalAvailable { parts.append("Apple ✓") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 子页 2:提醒

struct RemindersSettingsView: View {
    @AppStorage(SettingsKeys.morningReminderHour) private var morningHour: Int = 7
    @AppStorage(SettingsKeys.morningReminderMinute) private var morningMinute: Int = 30
    @AppStorage(SettingsKeys.dailyDigestEnabled) private var dailyDigestEnabled: Bool = false

    var body: some View {
        Form {
            Section {
                DatePicker(
                    "早上推送时间",
                    selection: morningTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                .font(.system(size: DesignTokens.FontSize.body))

                Toggle(isOn: Binding(
                    get: { dailyDigestEnabled },
                    set: { newValue in
                        dailyDigestEnabled = newValue
                        NotificationService.shared.updateDailyDigest()
                    }
                )) {
                    HStack {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(Ink.fg)
                        Text("每日汇总提醒")
                            .font(.system(size: DesignTokens.FontSize.body))
                    }
                }

                Text("推送分两级:\n• **普通**:每天早 \(formattedMorningTime) 推一次,最多 7 天\n• **隐患**:早 + 晚 18:00,Day 3+ 加中午 12:00,最多 10 天\n\n每日汇总开启后:每天早 \(formattedMorningTime) 推一条「打开 SiteNote 查看今日任务」。")
                    .font(.system(size: DesignTokens.FontSize.body))
                    .foregroundStyle(.secondary)
            } header: {
                Text("推送时间")
            } footer: {
                Text("改动后下次 App 启动时对所有未完成速记生效。")
                    .font(.system(size: DesignTokens.FontSize.body))
            }
        }
        .navigationTitle("提醒")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
    }

    private var formattedMorningTime: String {
        String(format: "%02d:%02d", morningHour, morningMinute)
    }

    private var morningTimeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = morningHour
                comps.minute = morningMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                morningHour = comps.hour ?? 7
                morningMinute = comps.minute ?? 30
            }
        )
    }
}

// MARK: - 子页 3:工地资源(标签 / 平面图 / 模板 / 条款)

struct SiteResourcesSettingsView: View {
    @State private var siteTags: [String] = SiteTagsStorage.load()
    @State private var newTagName: String = ""
    @State private var showsNewSiteSheet: Bool = false
    /// 刷新计数器:从 SubTagsEditorView 返回后 bump 一下,让分类数量重算。
    @State private var refreshTick: Int = 0

    @State private var templates: [InspectionTemplate] = InspectionTemplatesStorage.load()

    @State private var clauseRefs: [String] = ClauseRefsStorage.load()
    @State private var newClauseRef: String = ""

    var body: some View {
        Form {
            siteTagsSection
            subTagsSection
            floorPlansSection
            templatesSection
            clausesSection
        }
        .navigationTitle("工地资源")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .onAppear {
            templates = InspectionTemplatesStorage.load()
            siteTags = SiteTagsStorage.load()
            clauseRefs = ClauseRefsStorage.load()
            refreshTick += 1
        }
    }

    private var siteTagsSection: some View {
        Section {
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
                        deleteTag(tag)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }

            Button {
                showsNewSiteSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                    Text("新建工地")
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.dim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showsNewSiteSheet) {
                NewSiteSheet { _ in
                    siteTags = SiteTagsStorage.load()
                }
            }
        } header: {
            Text("工地标签")
        } footer: {
            Text("左滑删除工地。删工地不影响已打过标签的历史 note。")
                .font(.system(size: DesignTokens.FontSize.body))
        }
    }

    private var subTagsSection: some View {
        Section {
            NavigationLink {
                SubTagsEditorView()
            } label: {
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(Ink.fg)
                    Text("分类管理")
                        .font(.system(size: DesignTokens.FontSize.body))
                    Spacer()
                    let count = SubTagsStorage.load().count
                    Text(count == 0 ? "未创建" : "\(count) 个")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("分类")
        } footer: {
            Text("全局类型分类(RFI / 缺陷 / 施工 / 开会 / 紧急 等),不按工地分。每个带颜色,平面图图钉会用这颜色。")
                .font(.system(size: DesignTokens.FontSize.body))
        }
        .id(refreshTick)
    }

    private var floorPlansSection: some View {
        Section {
            NavigationLink {
                FloorPlanManageView()
            } label: {
                HStack {
                    Image(systemName: "map")
                        .foregroundStyle(.secondary)
                    Text("管理工地平面图")
                        .font(.system(size: DesignTokens.FontSize.body))
                }
            }
        } header: {
            Text("工地平面图")
        } footer: {
            Text("上传楼层/工地平面图后,录音时可以在图上点位置,比 GPS 的 \"Willoughby, NSW\" 精确 10 倍。")
                .font(.system(size: DesignTokens.FontSize.body))
        }
    }

    private var templatesSection: some View {
        Section {
            ForEach(templates) { template in
                NavigationLink {
                    TemplateEditorView(existing: template)
                } label: {
                    HStack {
                        Image(systemName: "checklist")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.system(size: DesignTokens.FontSize.body))
                            Text("\(template.items.count) 项")
                                .font(.system(size: DesignTokens.FontSize.body))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for idx in offsets {
                    InspectionTemplatesStorage.remove(id: templates[idx].id)
                }
                templates = InspectionTemplatesStorage.load()
            }

            NavigationLink {
                TemplateEditorView(existing: nil)
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("新建模板")
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                }
                .foregroundStyle(Color.accentColor)
            }
        } header: {
            Text("巡检模板")
        } footer: {
            Text("录音时可选一个模板跟着检查,漏项会在详情页红字提示。默认提供 3 个典型模板,可改可删。")
                .font(.system(size: DesignTokens.FontSize.body))
        }
    }

    private var clausesSection: some View {
        Section {
            ForEach(clauseRefs, id: \.self) { ref in
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text(ref)
                        .font(.system(size: DesignTokens.FontSize.body))
                    Spacer()
                    Button {
                        clauseRefs = ClauseRefsStorage.remove(ref)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                TextField("新条款(如 Clause 19.2 Suspension)", text: $newClauseRef)
                    .font(.system(size: DesignTokens.FontSize.body))
                Button("添加") {
                    addClauseRef()
                }
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                .disabled(newClauseRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("合同条款库")
        } footer: {
            Text("录音时可引用一条,出现在 note 详情和 PDF 导出里,便于争议取证。已预置 AS4000 常用条款。")
                .font(.system(size: DesignTokens.FontSize.body))
        }
    }

    private func addTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        siteTags = SiteTagsStorage.add(trimmed)
        newTagName = ""
    }

    private func deleteTag(_ tag: String) {
        siteTags = SiteTagsStorage.remove(tag)
    }

    private func addClauseRef() {
        let trimmed = newClauseRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        clauseRefs = ClauseRefsStorage.add(trimmed)
        newClauseRef = ""
    }
}

// MARK: - 子页 4:报告与导出

struct ReportsExportSettingsView: View {
    @State private var backupShareURL: URL?
    @State private var backupError: String?

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    WeeklySummaryView()
                } label: {
                    HStack {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .foregroundStyle(.secondary)
                        Text("本周总结")
                            .font(.system(size: DesignTokens.FontSize.body))
                    }
                }
                NavigationLink {
                    EOTReportView()
                } label: {
                    HStack {
                        Image(systemName: "cloud.rain")
                            .foregroundStyle(.secondary)
                        Text("EOT 工期延误报告")
                            .font(.system(size: DesignTokens.FontSize.body))
                    }
                }
            } header: {
                Text("分析与报告")
            } footer: {
                Text("本周总结给项目经理;EOT 基于天气数据生成工期延长主张(交业主/律师)。")
                    .font(.system(size: DesignTokens.FontSize.body))
            }

            Section {
                NavigationLink {
                    PDFExportView()
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("导出 PDF 巡检日志")
                            .font(.system(size: DesignTokens.FontSize.body))
                    }
                }

                Text("在 iPhone 的「文件」App → 「我的 iPhone」→「SiteNote」可以看到所有录音和照片文件。")
                    .font(.system(size: DesignTokens.FontSize.body))
                    .foregroundStyle(.secondary)
                Button("导出全部数据为 ZIP") {
                    exportBackup()
                }
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
            } header: {
                Text("数据导出与备份")
            } footer: {
                Text("PDF 用于交业主或法律存档;ZIP **包含速记数据 + 录音 + 照片 + 设置**,用于整体备份到 iCloud Drive/邮件。清空全部数据前建议先导一份。")
                    .font(.system(size: DesignTokens.FontSize.body))
            }
        }
        .navigationTitle("报告与导出")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .sheet(item: Binding(
            get: { backupShareURL.map { BackupShareItem(url: $0) } },
            set: { _ in backupShareURL = nil }
        )) { item in
            ShareSheet(items: [item.url])
        }
        .alert("备份出错", isPresented: Binding(
            get: { backupError != nil },
            set: { if !$0 { backupError = nil } }
        )) {
            Button("知道了") { backupError = nil }
        } message: {
            Text(backupError ?? "")
        }
    }

    private func exportBackup() {
        do {
            let url = try BackupService.createBackupZip()
            backupShareURL = url
        } catch {
            backupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - 子页 5:数据与关于

struct DataAboutSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showsClearConfirm: Bool = false
    @State private var clearResultMessage: String?

    /// 一键清空的倒计时:nil = idle,>0 = 正在数,0 = 即将触发。
    @State private var nukeCountdown: Int? = nil
    @State private var nukeTask: Task<Void, Never>? = nil

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    TrashView()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                        Text("垃圾桶")
                            .font(.system(size: DesignTokens.FontSize.body))
                    }
                }
            } header: {
                Text("已删除")
            } footer: {
                Text("删除的速记会进入这里,可以恢复或永久删除。")
                    .font(.system(size: DesignTokens.FontSize.body))
            }

            Section {
                Button(role: .destructive) {
                    showsClearConfirm = true
                } label: {
                    Text("清除所有已完成记录")
                        .font(.system(size: DesignTokens.FontSize.body))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let msg = clearResultMessage {
                    Text(msg)
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("数据清理")
            } footer: {
                Text("会同时删除对应的录音和照片文件,不可恢复。")
                    .font(.system(size: DesignTokens.FontSize.body))
            }

            nukeAllSection

            ShareLogStatsSection()

            Section("反馈") {
                Button {
                    openFeedbackMail()
                } label: {
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundStyle(Ink.fg)
                        Text("反馈与建议")
                            .font(.system(size: DesignTokens.FontSize.body))
                            .foregroundStyle(Ink.fg)
                        Spacer()
                        Text("banruostudio@gmail.com")
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
            }

            Section("关于") {
                HStack {
                    Text("版本")
                        .font(.system(size: DesignTokens.FontSize.body))
                    Spacer()
                    Text(appVersion)
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("数据与关于")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .alert("清除所有已完成记录?", isPresented: $showsClearConfirm) {
            Button("清除", role: .destructive) { clearCompleted() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除所有已完成的速记、对应的录音和照片,不可恢复。")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    /// 打开邮件 App,预填收件人/主题/带版本+设备信息的正文。用 URLComponents 安全转义。
    private func openFeedbackMail() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        let iosVersion = UIDevice.current.systemVersion
        let device = UIDevice.current.model
        let body = "\n\n---\nSiteNote \(version) (\(build))\niOS \(iosVersion) · \(device)"

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "banruostudio@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "SiteNote 反馈"),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }

    /// 一键清空 Section。倒计时中显示"X 秒后清空 / 取消"条,否则显示按钮。
    @ViewBuilder
    private var nukeAllSection: some View {
        Section {
            if let countdown = nukeCountdown {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Ink.red)
                    Text("\(countdown) 秒后清空所有内容")
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .foregroundStyle(Ink.red)
                        .contentTransition(.numericText())
                    Spacer()
                    Button("取消") {
                        cancelNuke()
                    }
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .buttonStyle(.bordered)
                }
            } else {
                Button(role: .destructive) {
                    startNukeCountdown()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("一键清空所有内容")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } header: {
            Text("一键清空")
        } footer: {
            Text("清空所有速记(含垃圾桶)、录音、照片、平面图、工地 / 分类 / 模板 / 条款 / 术语 / 快捷词。**不可恢复**。建议先到「报告与导出」→「导出全部数据为 ZIP」做备份再清。按下后 3 秒内可取消。")
                .font(.system(size: DesignTokens.FontSize.body))
        }
    }

    private func startNukeCountdown() {
        nukeTask?.cancel()
        clearResultMessage = nil
        nukeCountdown = 3
        nukeTask = Task { @MainActor in
            for i in stride(from: 3, through: 1, by: -1) {
                nukeCountdown = i
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            nukeEverything()
            nukeCountdown = nil
            nukeTask = nil
        }
    }

    private func cancelNuke() {
        nukeTask?.cancel()
        nukeTask = nil
        nukeCountdown = nil
    }

    /// 硬清空:所有 Note(含垃圾桶) + 所有文件 + 所有用户配置的资源列表。
    /// 保留:AppStorage 偏好(识别语言、AI Key、早推送时间等)。
    private func nukeEverything() {
        // 1. 硬删所有 Note(含已软删/已完成)
        let descriptor = FetchDescriptor<Note>()
        var noteCount = 0
        if let notes = try? modelContext.fetch(descriptor) {
            noteCount = notes.count
            for note in notes {
                NotificationService.shared.cancel(for: note)
                modelContext.delete(note)
            }
        }

        // 1b. 硬删所有 LogEntry(包括软删的孤儿)+ ShareLog 分享记录。
        // Note 删了但这些表会留下"孤儿"数据,违反"不可恢复"承诺。
        if let entries = try? modelContext.fetch(FetchDescriptor<LogEntry>()) {
            for e in entries { modelContext.delete(e) }
        }
        if let shares = try? modelContext.fetch(FetchDescriptor<ShareLog>()) {
            for s in shares { modelContext.delete(s) }
        }

        // 2. 一并清掉 Documents 下的三大文件目录(音频/照片/平面图)
        if let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first {
            for sub in ["audio", "photos", "floorplans"] {
                let url = docs.appendingPathComponent(sub, isDirectory: true)
                try? FileManager.default.removeItem(at: url)
            }
        }

        // 3. 清 UserDefaults 里的"用户内容"(列表数据,不动偏好)
        let defaults = UserDefaults.standard
        for key in [
            "settings.siteTags",
            "settings.subTagsGlobalV1",
            "settings.inspectionTemplates",
            "settings.clauseRefs",
            "settings.floorPlans",
            "settings.siteCentroids.v1"
        ] {
            defaults.removeObject(forKey: key)
        }
        // 术语 / 快捷词也属于用户内容,清空时连带清掉(否则下次录音 AI 还会用旧术语)。
        JargonStorage.clearAll()

        // 4. 干掉所有推送
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        // 5. 落盘
        do {
            try modelContext.save()
            clearResultMessage = "已清空:\(noteCount) 条速记 + 全部文件与资源"
        } catch {
            clearResultMessage = "清空时出错:\(error.localizedDescription)"
        }
    }

    private func clearCompleted() {
        // 包括已软删的已完成 note 一起清(反正已完成+已软删 == 真废弃)。
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.isDone == true }
        )
        guard let completed = try? modelContext.fetch(descriptor) else {
            clearResultMessage = "清除失败(读取数据库出错)"
            return
        }

        var count = 0
        for note in completed {
            if let audio = note.audioFilePath,
               let url = VoiceCaptureService.absoluteURL(forRelative: audio) {
                try? FileManager.default.removeItem(at: url)
            }
            for photo in note.photoPaths {
                if let url = PhotoStorage.absoluteURL(forRelative: photo) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            NotificationService.shared.cancel(for: note)
            modelContext.delete(note)
            count += 1
        }

        // 显式落盘:SwiftData 默认自动保存但在某些路径下(比如 sheet 内按钮)不会立即 flush,
        // 导致 @Query 驱动的列表看着"没变化"。显式 save 保证一致。
        do {
            try modelContext.save()
            clearResultMessage = count == 0 ? "没有已完成的记录可清除" : "已清除 \(count) 条"
        } catch {
            clearResultMessage = "清除时出错: \(error.localizedDescription)"
        }
    }
}

// MARK: - 共享

/// AppStorage 的键名集中维护。
enum SettingsKeys {
    static let speechLanguage = "settings.speechLanguage"
    static let morningReminderHour = "settings.morningReminderHour"
    static let morningReminderMinute = "settings.morningReminderMinute"
    /// P1-5:AI 总开关。默认开(符合"AI 显眼"约束)。关掉 = polish/autoTag 都不跑。
    static let aiMasterEnabled = "settings.aiMasterEnabled"
    static let aiPolishEnabled = "settings.aiPolishEnabled"
    static let aiAutoTagEnabled = "settings.aiAutoTagEnabled"
    static let dailyDigestEnabled = "settings.dailyDigestEnabled"
}

/// P1-5:统一读 AI 总开关 + 单功能开关。两个都开才返回 true。
/// `master` 默认 true(显眼);`feature` 默认 true(同上)。
enum AIToggle {
    static var masterEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.aiMasterEnabled) as? Bool ?? true
    }

    static func featureEnabled(_ key: String) -> Bool {
        let feature = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        return masterEnabled && feature
    }
}

/// 包装备份 URL 以满足 `.sheet(item:)` 的 Identifiable 要求。
private struct BackupShareItem: Identifiable {
    let id: UUID = UUID()
    let url: URL
}

/// 分享/导出统计 Section。展示历史数据让用户感受到产品 last-mile 的累积。
struct ShareLogStatsSection: View {
    @Query(sort: [SortDescriptor(\ShareLog.sharedAt, order: .reverse)])
    private var logs: [ShareLog]

    private var completedCount: Int { logs.filter { $0.completed }.count }

    private var lastShareLabel: String? {
        guard let last = logs.first(where: { $0.completed }) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日 HH:mm"
        return "\(f.string(from: last.sharedAt)) · \(last.channelLabel)"
    }

    /// channel → count(完成的)。
    private var channelBreakdown: [(name: String, count: Int)] {
        let completed = logs.filter { $0.completed }
        let grouped = Dictionary(grouping: completed, by: { $0.channelLabel })
        return grouped
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        Section {
            if logs.isEmpty {
                Text("还没有分享过。在日志 tab 的某一天底部用「生成今日简报」导出 PDF。")
                    .font(.system(size: DesignTokens.FontSize.body))
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("总分享次数")
                        .font(.system(size: DesignTokens.FontSize.body))
                    Spacer()
                    Text("\(completedCount)")
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Ink.fg)
                }
                if let last = lastShareLabel {
                    HStack {
                        Text("上次分享")
                            .font(.system(size: DesignTokens.FontSize.body))
                        Spacer()
                        Text(last)
                            .font(.system(size: DesignTokens.FontSize.body))
                            .foregroundStyle(.secondary)
                    }
                }
                if !channelBreakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("分享渠道")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.3)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                        ForEach(channelBreakdown, id: \.name) { item in
                            HStack {
                                Text(item.name)
                                    .font(.system(size: DesignTokens.FontSize.body))
                                Spacer()
                                Text("\(item.count)")
                                    .font(.system(size: DesignTokens.FontSize.body))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        } header: {
            Text("分享记录")
        } footer: {
            Text("iOS 不告诉我们具体分享给谁,只能记录是哪个 App 接受。")
                .font(.system(size: DesignTokens.FontSize.body))
        }
    }
}
