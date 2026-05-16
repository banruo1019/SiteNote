//
//  SettingsView.swift
//  SiteNote
//
//  设置首页 — 仅做角色路由。两种模式各自的实际首页:
//    - Engineer → EngineerSettingsRoot
//    - PM       → PMSettingsView
//  下方文件还有若干共用子页(InputAISettingsView 等),两个 Profile 都能跳。
//

import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import PhotosUI

struct SettingsView: View {
    @State private var profileManager = UserProfileManager.shared

    var body: some View {
        if profileManager.current == .engineer {
            EngineerSettingsRoot()
        } else {
            PMSettingsView()
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
        case .auto: parts.append(String(localized: "自动", locale: AppLanguageManager.currentLocale))
        case .openai: parts.append("OpenAI")
        case .local: parts.append(String(localized: "本地", locale: AppLanguageManager.currentLocale))
        }
        if AIService.isOpenAIAvailable { parts.append("OpenAI ✓") }
        if AIService.isLocalAvailable { parts.append("Apple ✓") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 子页 2:提醒

struct RemindersSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKeys.morningReminderHour) private var morningHour: Int = 7
    @AppStorage(SettingsKeys.morningReminderMinute) private var morningMinute: Int = 30
    @AppStorage(SettingsKeys.dailyDigestEnabled) private var dailyDigestEnabled: Bool = false

    /// E3.6:权限状态。.notDetermined 时给"点开提醒会请求授权"提示;.denied 时给跳设置按钮。
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            permissionBanner

            Section {
                DatePicker(
                    "早上推送时间",
                    selection: morningTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                .font(.system(size: DesignTokens.FontSize.body))
                // E3.8:时间一改立刻 reschedule(不再等"下次启动")。
                .onChange(of: morningHour) { _, _ in rescheduleAfterTimeChange() }
                .onChange(of: morningMinute) { _, _ in rescheduleAfterTimeChange() }

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
                Text("改时间后立刻对所有未完成速记重新排推送。")
                    .font(.system(size: DesignTokens.FontSize.body))
            }
        }
        .navigationTitle("提醒")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .task { await refreshAuthStatus() }
        // 用户从系统设置回来时,UIApplication.willEnterForegroundNotification 触发刷新。
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification
        )) { _ in
            Task { await refreshAuthStatus() }
        }
    }

    /// E3.6:顶部权限横幅。
    @ViewBuilder
    private var permissionBanner: some View {
        switch authStatus {
        case .denied:
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.slash.fill")
                            .foregroundStyle(.red)
                        Text("通知未授权,提醒不会响")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    Text("请到「系统设置」打开 SiteNote 的通知权限,否则下面这些时间设置都不会生效。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("打开系统设置", systemImage: "arrow.up.right.square")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        case .notDetermined:
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("首次开启提醒时会请求通知授权。")
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(.secondary)
                }
            }
        default:
            EmptyView()
        }
    }

    private func refreshAuthStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run { authStatus = settings.authorizationStatus }
    }

    private func rescheduleAfterTimeChange() {
        // 改时间立即对全量未完成 note reschedule + 重排每日汇总。
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.deletedAt == nil && $0.isDone == false }
        )
        let notes = (try? modelContext.fetch(descriptor)) ?? []
        NotificationService.shared.rescheduleAll(notes: notes)
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
    @State private var showsNewSiteSheet: Bool = false
    /// 刷新计数器:从 SubTagsEditorView 返回后 bump 一下,让分类数量重算。
    @State private var refreshTick: Int = 0

    @State private var clauseRefs: [String] = ClauseRefsStorage.load()
    @State private var newClauseRef: String = ""

    var body: some View {
        Form {
            siteTagsSection
            subTagsSection
            floorPlansSection
            clausesSection
            buildersSection
            sitePresetSection
            disclaimerSection
        }
        .navigationTitle("工地资源")
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .onAppear {
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
                NewSiteSheet { _, _ in
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
                    .buttonStyle(.plain)
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

    private var buildersSection: some View {
        Section {
            NavigationLink {
                BuildersEditorView()
            } label: {
                HStack {
                    Image(systemName: "person.text.rectangle")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("建造商联系簿")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        Text("Email 一键发送 / Attn 自动填入")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("建造商")
        } footer: {
            Text("Inspection 报告里「Attn」字段会从这里挑人,导出 PDF 后还能一键发邮件给收件人。")
                .font(.system(size: DesignTokens.FontSize.body))
        }
    }

    private var sitePresetSection: some View {
        Section {
            NavigationLink {
                SitePresetEditorView()
            } label: {
                HStack {
                    Image(systemName: "building.2.crop.circle")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("工地预设")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        Text("Engineer · 导出 PDF 时自动填字段")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("工地预设")
        } footer: {
            Text("工程师专用。一个 siteTag 一条预设,导出 Inspection 报告时自动填 Header(项目名 / 编号 / 客户 / 地址 / 默认收件人)。")
                .font(.system(size: DesignTokens.FontSize.body))
        }
    }

    private var disclaimerSection: some View {
        Section {
            NavigationLink {
                DisclaimerEditorView()
            } label: {
                HStack {
                    Image(systemName: "doc.plaintext")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("巡检免责声明")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        Text("用户自定义,空则用默认 5 条")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("免责声明")
        } footer: {
            Text("Inspection PDF 末页打印的 \u{201C}This inspection does not include \u{2026}\u{201D} 段落。空则用 QDE 那套标准 5 条。")
                .font(.system(size: DesignTokens.FontSize.body))
        }
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


// MARK: - 子页 5:数据与关于

struct DataAboutSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showsClearConfirm: Bool = false
    @State private var clearResultMessage: String?

    /// 一键清空的倒计时:nil = idle,>0 = 正在数,0 = 即将触发。
    @State private var nukeCountdown: Int? = nil
    @State private var nukeTask: Task<Void, Never>? = nil

    /// E3.7:反馈分享面板的 items(包含正文 + 可选 crash JSON 附件)。
    @State private var feedbackShareItems: [Any]? = nil

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
        // E3.7:反馈分享面板。有 crash JSON 时把它作为附件,否则只分享正文(等价于以前 mailto 的体验)。
        .sheet(isPresented: Binding(
            get: { feedbackShareItems != nil },
            set: { if !$0 { feedbackShareItems = nil } }
        )) {
            if let items = feedbackShareItems {
                ShareSheet(items: items)
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    /// 反馈入口。E3.7:有 crash JSON 时弹 ActivityViewController 把 crash 作为附件;
    /// 没 crash log 则降级为系统 mailto:(预填收件人/主题/正文)。
    private func openFeedbackMail() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        let iosVersion = UIDevice.current.systemVersion
        let device = UIDevice.current.model
        let body = String(
            localized: "请描述问题或建议:\n\n\n---\nSiteNote \(version) (\(build))\niOS \(iosVersion) · \(device)\n邮箱:banruostudio@gmail.com",
            locale: AppLanguageManager.currentLocale
        )

        // 有最新 crash JSON 就走 ShareSheet,带附件;没有就走 mailto:。
        if let crash = CrashReporter.latestCrashReport() {
            feedbackShareItems = [body, crash]
            return
        }

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
        // TODO(v1.2 主线):Team/TeamMember 接入 Schema 后,这里也要补。
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

        // 1c. InspectionReport(QDE 巡检报告 model)+ SiteVisitSchedule(工程师日程)
        //     这两个表也在主 Schema 里,清空时一并硬删。
        if let reports = try? modelContext.fetch(FetchDescriptor<InspectionReport>()) {
            for r in reports { modelContext.delete(r) }
        }
        if let schedules = try? modelContext.fetch(FetchDescriptor<SiteVisitSchedule>()) {
            for s in schedules { modelContext.delete(s) }
        }

        // 2. 一并清掉 Documents 下的三大文件目录(音频/照片/平面图)+ 隐藏目录(诊断包/备份元/branding logo)
        if let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first {
            for sub in ["audio", "photos", "floorplans", "branding", "_crash_reports", "_backup_meta"] {
                let url = docs.appendingPathComponent(sub, isDirectory: true)
                try? FileManager.default.removeItem(at: url)
            }
        }

        // 2b. 清 Keychain 里的 OpenAI API Key(否则手机转手时残留)
        KeychainStorage.delete(for: KeychainKeys.openAIAPIKey)

        // 3. 清 UserDefaults 里的"用户内容"(列表数据,不动偏好)
        let defaults = UserDefaults.standard
        for key in [
            "settings.siteTags",
            "settings.subTagsGlobalV1",
            "settings.clauseRefs",
            "settings.floorPlans",
            "settings.siteCentroids.v1"
        ] {
            defaults.removeObject(forKey: key)
        }
        // 术语 / 快捷词也属于用户内容,清空时连带清掉(否则下次录音 AI 还会用旧术语)。
        JargonStorage.clearAll()
        // 工地预设(Engineer 用)也属于用户内容,清掉(否则手机转手时残留项目/客户信息)。
        SitePresetStorage.clearAll()

        // 4. 干掉所有推送
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        // 5. 落盘
        do {
            try modelContext.save()
            clearResultMessage = String(localized: "已清空:\(noteCount) 条速记 + 全部文件与资源", locale: AppLanguageManager.currentLocale)
        } catch {
            clearResultMessage = String(localized: "清空时出错:\(error.localizedDescription)", locale: AppLanguageManager.currentLocale)
        }
    }

    private func clearCompleted() {
        // 包括已软删的已完成 note 一起清(反正已完成+已软删 == 真废弃)。
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.isDone == true }
        )
        guard let completed = try? modelContext.fetch(descriptor) else {
            clearResultMessage = String(localized: "清除失败(读取数据库出错)", locale: AppLanguageManager.currentLocale)
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
            clearResultMessage = count == 0 ? String(localized: "没有已完成的记录可清除", locale: AppLanguageManager.currentLocale) : String(localized: "已清除 \(count) 条", locale: AppLanguageManager.currentLocale)
        } catch {
            clearResultMessage = String(localized: "清除时出错: \(error.localizedDescription)", locale: AppLanguageManager.currentLocale)
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
    /// HomeViewModel:633 用此 key 控分类管线;UI 里"自动推断标签" toggle 直接对它。
    /// 旧 key aiAutoTagEnabled 已废,SiteNoteApp.init 里做一次性 migration 把旧值复制过来。
    static let aiOmniClassifyEnabled = "settings.aiOmniClassifyEnabled"
    /// HomeViewModel:634 用此 key 控 LogEntry 抽取。需要独立 UI 入口。
    static let aiLogExtractEnabled = "settings.aiLogExtractEnabled"
    /// **已废**(保留常量给 SiteNoteApp.init 做一次性 migration,删常量 = 升级用户 toggle 状态丢失)。
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
        f.locale = AppLanguageManager.currentLocale
        f.dateFormat = nil
        f.dateStyle = .medium
        f.timeStyle = .short
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
