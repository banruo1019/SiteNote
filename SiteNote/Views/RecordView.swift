//
//  RecordView.swift
//  SiteNote
//
//  v1.3 大重构:主屏 "记" Tab 充当数据管理库。
//  - 按工地大组 → 每组内按 otherTags(分类标签)子组 → 子组内按 createdAt 倒序
//  - 底部固定段:已归档项目(SiteArchiveStorage)
//  - PM 和 Engineer 用同一 RecordView,角色不影响布局
//
//  关键架构:MIC 按钮(hero block)必须常驻,不能因为录音态切换而重建,
//  否则 DragGesture 目标节点消失 → 松不开。上方内容在 idle/recording 间切,下方 hero 稳定。
//

import SwiftUI
import SwiftData
import UIKit

struct RecordView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.createdAt,
        order: .reverse
    ) private var allNotes: [Note]
    /// Engineer idle 主屏的"今日巡检"列表数据源。
    /// @Query 拉所有 schedule(未软删),今天 + pending + 未挂 report 的过滤交给 `todayPendingSchedules`。
    /// 不在 @Query 里写 today 范围:Calendar.startOfDay 不是 Predicate 友好的常量。
    @Query(
        filter: #Predicate<SiteVisitSchedule> { $0.deletedAt == nil },
        sort: \SiteVisitSchedule.scheduledDate,
        order: .forward
    ) private var allSchedules: [SiteVisitSchedule]
    @State var viewModel = HomeViewModel()

    @State var isShowingCamera = false
    @State private var cameraCapturedImage: UIImage?
    @State var editingStagedIndex: EditingStagedIndex?

    @State private var navPath = NavigationPath()

    /// 顶部 Search 文本(常驻)。空 = 显示全部。
    @State private var searchText: String = ""
    /// 归档工地 set,影响默认列表是否包含其下的 Note。
    @State private var archivedSiteTags: Set<String> = SiteArchiveStorage.loadArchived()
    /// "已完成"段折叠状态(默认折叠 — 用户看的主要是待办)。
    @State private var doneSectionExpanded: Bool = false
    /// v1.6:待办段也可折叠,默认展开。
    @State private var pendingSectionExpanded: Bool = true
    /// v1.6 (en-v1):Site Team 主屏「已逾期」段,默认展开(高优先级一打开就看见)。
    @State private var overdueSectionExpanded: Bool = true
    /// Engineer 视角的工地 filter(nil = 全部工地)。PM 视角不用。
    @State private var engineerSiteFilter: String? = nil

    @State private var headerProvider = AppHeaderProvider.shared
    @State private var profileManager = UserProfileManager.shared

    // v1.4 Engineer 巡检 session 化:idle/active 双态主屏。
    // - idle:大"开始巡检"按钮 + 帮助文案,点 mic/camera 自动拦截弹 StartInspectionSheet
    // - active:InspectionSessionBanner + 只显示本 session 的 notes
    @State private var sessionManager = InspectionSessionManager.shared
    @State private var showsStartSheet: Bool = false
    @State private var showsEndSheet: Bool = false

    private let listVM = NoteListViewModel()

    // MARK: - Derived data

    /// 所有未删除的 Note,且属于当前角色(v1.5 同账号双世界)。
    /// 历史 nil 归 PM(老用户基线,见 Note.effectiveRole)。
    private var liveNotes: [Note] {
        allNotes.filter { $0.deletedAt == nil && $0.belongsToCurrentRole }
    }

    /// 应用 search + 归档过滤后的 Note 池(待办 + 已完成共用基础)。
    private var basePool: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            // 隐藏归档工地的 Note
            return liveNotes.filter { note in
                guard let s = note.siteTag else { return true }
                return !archivedSiteTags.contains(s)
            }
        }
        // search 跨全集,包括归档
        return liveNotes.filter { note in
            if note.transcription.lowercased().contains(query) { return true }
            if let s = note.siteTag, s.lowercased().contains(query) { return true }
            if note.otherTags.contains(where: { $0.lowercased().contains(query) }) { return true }
            return false
        }
    }

    /// v1.6 (en-v1):Site Team 主屏「已逾期」段 — 过 dueDate 但未完成、非归档、非 inbox。
    /// 按 dueDate 升序(最久逾期最上)。Engineer 模式返回空(不分段)。
    private var overdueNotes: [Note] {
        guard profileManager.current == .siteTeam else { return [] }
        let now = Date()
        return basePool
            .filter { note in
                !note.isDone
                && note.dueDate < now
                && note.deadline != .archive
                && note.deadline != .inbox
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    /// 待办段:未完成,按 createdAt 倒序。
    /// Site Team 模式排除逾期(归入 overdueNotes);Engineer 模式仍是全部未完成。
    private var pendingNotes: [Note] {
        let now = Date()
        let isSiteTeam = profileManager.current == .siteTeam
        return basePool
            .filter { note in
                guard !note.isDone else { return false }
                if isSiteTeam
                    && note.dueDate < now
                    && note.deadline != .archive
                    && note.deadline != .inbox {
                    return false  // 归 overdueNotes
                }
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 已完成段:已完成,按 createdAt 倒序。
    private var doneNotes: [Note] {
        basePool
            .filter { $0.isDone }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Body

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack(path: $navPath) {
            ZStack(alignment: .bottom) {
                Ink.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    if viewModel.isRecording {
                        recordingTopArea
                    } else if !viewModel.stagedPhotos.isEmpty {
                        stagedPhotoFocusArea
                    } else if profileManager.current == .engineer {
                        // v1.4:Engineer 走 session 化主屏(idle / 巡检中两态)
                        engineerHomeContent
                    } else {
                        idleTopArea
                    }
                    heroButtons
                        .padding(.bottom, 20)
                        // toast 显示时大按钮浅化但不消失,避免用户没法继续录
                        .opacity(viewModel.lastSave != nil ? 0.92 : 1)
                }

                if viewModel.lastSave != nil {
                    undoToastOverlay
                        .padding(.horizontal, 12)
                        // 上浮覆盖在 mic+camera 大按钮上方
                        .padding(.bottom, 168)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarHidden(true)
            .task {
                viewModel.setup(modelContext: modelContext)
                NotificationService.shared.rescheduleAll(notes: allNotes)
                headerProvider.ensureFresh()
                // 回到主屏时重新拉归档列表(用户在 settings 里改过可能)。
                archivedSiteTags = SiteArchiveStorage.loadArchived()
                // 自愈 ghost session:UserDefaults 有 sessionID 但 SwiftData 没 report
                // (上次清空数据 / 数据迁移 / App 被杀 → report 丢失);防止主屏卡在 active 态。
                sessionManager.validateOrCancel(in: modelContext)
                // 团队 mirror:进主屏拉一次 zone changes,把 owner/member 改的 preset/schedule/report 同步过来
                await TeamDataMirrorService.shared.fetchAndSyncAll(in: modelContext)
                // 团队协作:Owner 分配给我的新工地 → 弹 local notification + 标记已通知。
                TeamAssignmentNotifier.shared.scanAndNotify(Array(allSchedules))
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraPicker(image: $cameraCapturedImage)
                    .ignoresSafeArea()
            }
            .onChange(of: cameraCapturedImage) { _, newImage in
                guard let img = newImage else { return }
                cameraCapturedImage = nil
                editingStagedIndex = EditingStagedIndex(value: -1, image: img)
            }
            .sheet(item: $editingStagedIndex) { item in
                PhotoEditorView(originalImage: item.image) { edited in
                    if item.value < 0 {
                        viewModel.stagePhoto(edited)
                    } else if item.value < viewModel.stagedPhotos.count {
                        viewModel.stagedPhotos[item.value] = edited
                    }
                }
            }
            .navigationDestination(for: Note.self) { note in
                NoteRouter(note: note)
            }
            .navigationDestination(for: SettingsDestination.self) { _ in
                SettingsView()
            }
            .navigationDestination(for: InspectionEntryDestination.self) { _ in
                InspectionReportListView()
            }
            // v1.4 巡检 session 弹窗
            .sheet(isPresented: $showsStartSheet) {
                StartInspectionSheet(
                    onStarted: { _ in
                        showsStartSheet = false
                    },
                    prefilledSiteTag: engineerSiteFilter
                )
            }
            .sheet(isPresented: $showsEndSheet) {
                if let report = sessionManager.currentReport(in: modelContext) {
                    EndInspectionSheet(report: report) { _, _ in
                        showsEndSheet = false
                    }
                }
            }
            .alert("出错了", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 {
                    viewModel.errorMessage = nil
                    viewModel.showsPermissionSettingsButton = false
                } }
            )) {
                if viewModel.showsPermissionSettingsButton {
                    Button("打开设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                        viewModel.errorMessage = nil
                        viewModel.showsPermissionSettingsButton = false
                    }
                    Button("取消", role: .cancel) {
                        viewModel.errorMessage = nil
                        viewModel.showsPermissionSettingsButton = false
                    }
                } else {
                    Button("知道了") { viewModel.errorMessage = nil }
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.lastSave?.noteID)
            // 工程师:**录完一律自动跳详情**(每条都要仔细记录,不走主屏速记 toast 流程)。
            // 不再以 sessionManager.isActive 守门 — Engineer idle 录音也走详情;
            // session 中录音附带的 attachIfNeeded 在 commit 路径里另行处理,不依赖这里。
            // PM 走 Undo Toast 流程(双行 deadline chip + 详情按钮),不触发自动跳。
            .onChange(of: viewModel.lastSave?.noteID) { _, newID in
                guard newID != nil,
                      profileManager.current == .engineer else { return }
                if let note = viewModel.fetchLastSavedNote() {
                    navPath.append(note)
                    viewModel.dismissToastManually()
                }
            }
        }
    }

    // MARK: - Engineer 主屏(v1.4 session 化)

    /// Engineer 主屏分发:有 active session → 巡检中视图;否则 → idle 视图。
    @ViewBuilder
    private var engineerHomeContent: some View {
        if sessionManager.isActive {
            engineerActiveContent
        } else {
            engineerIdleContent
        }
    }

    /// Engineer idle 态:大"开始巡检"CTA + 帮助文案 + Spacer 把 hero 顶下去。
    /// 不显示 search / site filter / 今日速记列表 — 没在巡检时这些都没意义。
    /// 今天若有 pending 巡检日程,在 CTA **上方** 插一段"今日巡检"列表(空则整段 hidden)。
    private var engineerIdleContent: some View {
        VStack(spacing: 0) {
            titleBlockMinimal
            if !todayPendingSchedules.isEmpty {
                todaySchedulesSection
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
            }
            engineerStartInspectionCTA
                .padding(.horizontal, 24)
                .padding(.top, 8)
            engineerIdleHelpText
                .padding(.horizontal, 24)
                .padding(.top, 28)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 今日巡检日程(idle 主屏快捷入口)

    /// 今天日历日内,pending 且未关联任何已建 report 的 schedule。
    /// 按 scheduledTime(无则 fireDate)升序。
    private var todayPendingSchedules: [SiteVisitSchedule] {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        guard let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday) else {
            return []
        }
        return allSchedules
            .filter { s in
                guard s.deletedAt == nil else { return false }
                guard s.status != .completed, s.status != .cancelled else { return false }
                guard s.linkedReportID == nil else { return false }
                return s.scheduledDate >= startOfToday && s.scheduledDate < startOfTomorrow
            }
            .sorted { $0.fireDate < $1.fireDate }
    }

    /// "今日巡检" section:小段头(uppercase + count badge) + 卡片列表。
    private var todaySchedulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(String(localized: "今日巡检", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Ink.fgDim)
                Text("\(todayPendingSchedules.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Ink.fg2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Ink.card)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(Array(todayPendingSchedules.enumerated()), id: \.element.id) { idx, s in
                    Button {
                        startSession(from: s)
                    } label: {
                        todayScheduleRow(s)
                    }
                    .buttonStyle(.plain)
                    if idx < todayPendingSchedules.count - 1 {
                        Rectangle().fill(Ink.line).frame(height: 1)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Ink.line, lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Ink.bg))
            )
        }
    }

    /// 单行:左 时间 + 工地 + 标题,右 chevron。
    private func todayScheduleRow(_ s: SiteVisitSchedule) -> some View {
        HStack(spacing: 12) {
            Text(timeLabel(for: s))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Ink.fg)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(siteLabel(for: s))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.fg)
                    .lineLimit(1)
                if let subtitle = subtitleLabel(for: s) {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ink.dim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// 行点击行为:有 siteTag → 直接 startFromSchedule 进 active;无 siteTag → 弹
    /// StartInspectionSheet 让用户手动补工地。
    private func startSession(from s: SiteVisitSchedule) {
        let tag = s.siteTag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !tag.isEmpty else {
            showsStartSheet = true
            return
        }
        let preset = SitePresetStorage.find(siteTag: tag)
        _ = sessionManager.startFromSchedule(
            s,
            siteTag: tag,
            preset: preset,
            defaultAttn: preset?.defaultAttn ?? "",
            in: modelContext
        )
    }

    /// 时间标签:有 scheduledTime 显示 HH:mm,否则显示"全天"。
    private func timeLabel(for s: SiteVisitSchedule) -> String {
        if s.scheduledTime != nil {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: s.fireDate)
        }
        return String(localized: "全天", locale: AppLanguageManager.currentLocale)
    }

    /// 工地标签:siteTag 优先;为空时回退 title;再空显示占位。
    private func siteLabel(for s: SiteVisitSchedule) -> String {
        let tag = s.siteTag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !tag.isEmpty { return tag }
        let t = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return String(localized: "未指定工地", locale: AppLanguageManager.currentLocale)
    }

    /// 副标:有 siteTag 时显示 title;无 siteTag 时副标为 notes(避免与主标重复)。
    private func subtitleLabel(for s: SiteVisitSchedule) -> String? {
        let tag = s.siteTag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty, !title.isEmpty { return title }
        let notes = s.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.isEmpty ? nil : notes
    }

    /// idle 态主 CTA — 黑底白字胶囊,宽满,圆角 12,内 18pt 600 主标 + 12pt 60% 副标。
    private var engineerStartInspectionCTA: some View {
        Button {
            showsStartSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "开始巡检", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(String(
                        localized: "选工地 + 录音拍照,完成出 PDF",
                        locale: AppLanguageManager.currentLocale
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Ink.fg)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "开始巡检", locale: AppLanguageManager.currentLocale))
    }

    /// idle 态帮助文案 — 11pt fgDim 居中,3 行说明工作流。
    private var engineerIdleHelpText: some View {
        VStack(spacing: 4) {
            Text(String(localized: "提示", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Ink.fgDim)
                .padding(.bottom, 2)
            Text(String(
                localized: "工程师工作流以巡检为单位。",
                locale: AppLanguageManager.currentLocale
            ))
            Text(String(
                localized: "录的每条都属于某次巡检,",
                locale: AppLanguageManager.currentLocale
            ))
            Text(String(
                localized: "完成后自动出 PDF 发邮件。",
                locale: AppLanguageManager.currentLocale
            ))
        }
        .font(.system(size: 11))
        .foregroundStyle(Ink.fgDim)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// 巡检中:titleBlockMinimal + Banner + 限定到本 session 的 search + 本 session notes 列表。
    private var engineerActiveContent: some View {
        VStack(spacing: 0) {
            titleBlockMinimal
            InspectionSessionBanner { _ in
                showsEndSheet = true
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            if currentSessionNotes.isEmpty {
                engineerSessionEmptyHint
            } else {
                engineerSessionTimelineList
            }
        }
    }

    /// 极简 titleBlock — 只标题 + 齿轮(Engineer idle/active 都用这套)。
    /// 删 search button + site filter:idle 时 search 没目标可搜;active 时由 sessionSearchBar 接管,
    /// site filter 也由 session 自身锁定工地。
    private var titleBlockMinimal: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "记", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Ink.fg)
            Spacer()
            NavigationLink(value: SettingsDestination()) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Ink.fgDim)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "设置", locale: AppLanguageManager.currentLocale))
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    /// 当前 session 关联的 notes(只显示绑到本 session 的)。
    /// 巡检中场景一次最多十几条记录,不需要搜索。
    private var currentSessionNotes: [Note] {
        guard let sid = sessionManager.currentSessionID else { return [] }
        return liveNotes
            .filter { $0.inspectionSessionID == sid }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 巡检中 — 仅本 session notes 的 timeline 列表(复用 noteRowItem)。
    private var engineerSessionTimelineList: some View {
        List {
            ForEach(currentSessionNotes) { note in
                noteRowItem(note)
            }
        }
        .listStyle(.plain)
        .industrialForm()
        .environment(\.defaultMinListRowHeight, 0)
    }

    /// 巡检中 + 还没录任何东西时的提示。
    private var engineerSessionEmptyHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Ink.line).frame(height: 1)
                .padding(.bottom, 20)
            Text(String(localized: "本次巡检还没记录", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ink.fg)
            Text(String(
                localized: "按住麦克风说话,或点相机拍照,本次巡检的内容会出现在这里。",
                locale: AppLanguageManager.currentLocale
            ))
            .font(.system(size: 12))
            .foregroundStyle(Ink.fgDim)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    // MARK: - Idle top area

    private var idleTopArea: some View {
        VStack(spacing: 0) {
            titleBlock
            siteGroupedList
        }
    }

    /// "记" 大标题 + 项目下拉(Engineer 才有)+ 齿轮。
    /// 工程师工地多(10+),原 chip 行换成 SiteFilterMenu 下拉(UI 全局一致)。
    private var titleBlock: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "记", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Ink.fg)
            Spacer()
            if profileManager.current == .engineer, !engineerAllSiteTags.isEmpty {
                SiteFilterMenu(
                    allTags: engineerAllSiteTags,
                    selection: $engineerSiteFilter
                )
            }
            SearchBarButton()
            NavigationLink(value: SettingsDestination()) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Ink.fgDim)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "设置", locale: AppLanguageManager.currentLocale))
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    /// 主屏列表 — 按 profile 分两种结构:
    /// - PM:Search + 待办/已完成 两段(用户主要看待办)
    /// - Engineer:Search + 工地 filter + 创建顺序列表(数据库查询视角)
    @ViewBuilder
    private var siteGroupedList: some View {
        if profileManager.current == .engineer {
            engineerSiteFilteredList
        } else {
            VStack(spacing: 0) {
                searchBar
                if overdueNotes.isEmpty && pendingNotes.isEmpty && doneNotes.isEmpty {
                    emptyHint
                } else {
                    twoSectionList
                }
            }
        }
    }

    // MARK: - Engineer 视角:工地 filter + 创建顺序列表

    /// Engineer 已知工地(从 Note + SiteTagsStorage 合并)。
    private var engineerAllSiteTags: [String] {
        let fromNotes = Set(liveNotes.compactMap { $0.siteTag })
        let configured = Set(SiteTagsStorage.load())
        return Array(fromNotes.union(configured)).sorted()
    }

    /// Engineer 视角应用 filter 后的 Note。Search 不空时跨 filter 全文搜。
    private var engineerFilteredNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [Note]
        if let site = engineerSiteFilter, query.isEmpty {
            base = liveNotes.filter { $0.siteTag == site }
        } else if !query.isEmpty {
            base = liveNotes.filter { note in
                if note.transcription.lowercased().contains(query) { return true }
                if let s = note.siteTag, s.lowercased().contains(query) { return true }
                if note.otherTags.contains(where: { $0.lowercased().contains(query) }) { return true }
                return false
            }
        } else {
            base = liveNotes
        }
        return base.sorted { $0.createdAt > $1.createdAt }
    }

    @ViewBuilder
    private var engineerSiteFilteredList: some View {
        VStack(spacing: 0) {
            searchBar
            if engineerFilteredNotes.isEmpty {
                emptyHint
            } else {
                engineerTimelineList
            }
        }
    }

    private var engineerTimelineList: some View {
        List {
            ForEach(engineerFilteredNotes) { note in
                noteRowItem(note)
            }
        }
        .listStyle(.plain)
        .industrialForm()
        .environment(\.defaultMinListRowHeight, 0)
    }

    /// 顶部常驻 Search bar。M1 细描边风格(非填充)。
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Ink.fgDim)
            TextField(
                String(localized: "搜索记录", locale: AppLanguageManager.currentLocale),
                text: $searchText
            )
            .font(.system(size: 13))
            .foregroundStyle(Ink.fg)
            .tint(Ink.fg)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.fgDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Ink.line, lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 8).fill(Ink.bg))
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

    /// 三段列表(Site Team)/ 两段(Engineer):已逾期 + 待办 + 已完成。
    /// v1.6 (en-v1) 起 Site Team 多一个「已逾期」段,默认展开,red header。
    private var twoSectionList: some View {
        List {
            // 已逾期段(只 Site Team,只在有逾期时渲染)
            if !overdueNotes.isEmpty {
                Section {
                    if overdueSectionExpanded {
                        ForEach(overdueNotes) { note in
                            noteRowItem(note, isOverdue: true)
                        }
                    }
                } header: {
                    sectionHeader(
                        title: String(localized: "已逾期", locale: AppLanguageManager.currentLocale),
                        count: overdueNotes.count,
                        foldable: true,
                        expanded: $overdueSectionExpanded,
                        tone: .danger
                    )
                }
            }

            // 待办段(v1.6:也可折叠,默认展开)
            if !pendingNotes.isEmpty {
                Section {
                    if pendingSectionExpanded {
                        ForEach(pendingNotes) { note in
                            noteRowItem(note)
                        }
                    }
                } header: {
                    sectionHeader(
                        title: String(localized: "待办", locale: AppLanguageManager.currentLocale),
                        count: pendingNotes.count,
                        foldable: true,
                        expanded: $pendingSectionExpanded
                    )
                }
            }

            // 已完成段(可折叠)
            if !doneNotes.isEmpty {
                Section {
                    if doneSectionExpanded {
                        ForEach(doneNotes) { note in
                            noteRowItem(note)
                        }
                    }
                } header: {
                    sectionHeader(
                        title: String(localized: "已完成", locale: AppLanguageManager.currentLocale),
                        count: doneNotes.count,
                        foldable: true,
                        expanded: $doneSectionExpanded
                    )
                }
            }
        }
        .listStyle(.plain)
        .industrialForm()
        .environment(\.defaultMinListRowHeight, 0)
    }

    /// 单条 Note row + swipe + 长按删除。
    /// 视觉本体在 `NoteTimelineRow`,这里只包 Button(替代 NavigationLink 去 List 隐式 chevron)
    /// + swipe(必须点 capsule 才生效 — allowsFullSwipe: false 防误触)+ contextMenu(长按删除)。
    /// `isOverdue=true` 时(Site Team「已逾期」段)圆点染红。
    @ViewBuilder
    private func noteRowItem(_ note: Note, isOverdue: Bool = false) -> some View {
        Button {
            navPath.append(note)
        } label: {
            NoteTimelineRow(note: note, isOverdue: isOverdue)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Ink.bg)
        // v1.6:右滑(leading)→ 完成 toggle;左滑(trailing)→ 删除(destructive)。
        // 两个方向都允许 full swipe(滑到底直接触发),贴近 Apple Mail 习惯。
        // contextMenu 长按删除保留作 backup 入口(防误触 + 维持发现性)。
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                toggleDone(note)
            } label: {
                Label(
                    note.isDone ? "未完成" : "完成",
                    systemImage: note.isDone ? "arrow.uturn.left" : "checkmark"
                )
            }
            .tint(Ink.fg)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                softDelete(note)
            } label: {
                Label(String(localized: "删除", locale: AppLanguageManager.currentLocale), systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                softDelete(note)
            } label: {
                Label(String(localized: "删除", locale: AppLanguageManager.currentLocale), systemImage: "trash")
            }
        }
    }

    /// Section header — 标题左 + 计数 chip + (可选)折叠 chevron。
    /// v1.6 (en-v1):section header tone — default 走原 dim 灰色,danger 走 red(已逾期段)。
    enum SectionTone { case `default`, danger }

    private func sectionHeader(
        title: String,
        count: Int,
        foldable: Bool,
        expanded: Binding<Bool>,
        tone: SectionTone = .default
    ) -> some View {
        let titleColor: Color = tone == .danger ? Ink.red : Ink.fgDim
        let chipFg: Color = tone == .danger ? Ink.red : Ink.fg2
        let chipBg: Color = tone == .danger ? Ink.red.opacity(0.12) : Ink.card
        return Button {
            if foldable {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.wrappedValue.toggle()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(titleColor)
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(chipFg)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Spacer()
                if foldable {
                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.dim)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!foldable)
        .textCase(nil)
    }

    /// 空态
    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Ink.line).frame(height: 1)
                .padding(.bottom, 20)
            Text(String(localized: "还没有速记", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ink.fg)
            Text(String(localized: "按住下方麦克风说话,开始一条新速记。", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 12))
                .foregroundStyle(Ink.fgDim)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private func toggleDone(_ note: Note) {
        note.isDone.toggle()
        if note.isDone {
            NotificationService.shared.cancel(for: note)
        } else {
            NotificationService.shared.schedule(for: note)
        }
    }

    private func softDelete(_ note: Note) {
        NotificationService.shared.cancel(for: note)
        note.deletedAt = Date()
    }

    // MARK: - Recording top area

    private var recordingTopArea: some View {
        RecordingTopArea(
            isRecording: viewModel.isRecording,
            audioLevel: viewModel.currentAudioLevel,
            partialTranscription: viewModel.partialTranscription,
            recordingStartTime: viewModel.recordingStartTime,
            siteTag: liveNotes.first?.siteTag
        )
    }

    // MARK: - Hero (常驻,MIC 按钮节点稳定)

    private var heroButtons: some View {
        HeroButtons(
            viewModel: viewModel,
            onShowCamera: {
                // Engineer 在 idle 态点 camera → 先开 session(必须归属一次巡检)
                if profileManager.current == .engineer && !sessionManager.isActive {
                    showsStartSheet = true
                } else {
                    isShowingCamera = true
                }
            },
            canStartRecording: {
                // Engineer 必须在巡检中才能录音 — idle 时拦截 + 弹 StartSheet
                if profileManager.current == .engineer && !sessionManager.isActive {
                    showsStartSheet = true
                    return false
                }
                return true
            }
        )
    }

    // MARK: - Undo toast

    private var undoToastOverlay: some View {
        UndoToast(
            message: viewModel.lastSave?.summary ?? "",
            secondsRemaining: viewModel.undoSecondsRemaining,
            // v1.5:PM 走双行 4 按钮(deadline chip + 详情);Engineer 用单行整行 tap 详情。
            showsDeadlineActions: profileManager.current == .siteTeam,
            currentDeadline: viewModel.lastSave?.deadline ?? .threeDays,
            onDetail: {
                if let note = viewModel.fetchLastSavedNote() {
                    navPath.append(note)
                }
                viewModel.dismissToastManually()
            },
            onUndo: { viewModel.undoLastSave() },
            onSetDeadline: { newDeadline in
                viewModel.setLastSaveDeadline(newDeadline)
                viewModel.dismissToastManually()
            }
        )
    }
}

struct EditingStagedIndex: Identifiable {
    let id: UUID = UUID()
    let value: Int
    let image: UIImage
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, ShareLog.self, configurations: config)
    return RecordView().modelContainer(container)
}
