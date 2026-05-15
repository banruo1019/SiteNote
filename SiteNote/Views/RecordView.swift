//
//  RecordView.swift
//  SiteNote
//
//  M1 "Linear 极简白":白底 + 大字"今天"标题 + 三列统计 + 最紧急卡
//  + 下方 132pt 黑色 MIC + 白描边 CAM 双按钮。
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
        sort: \Note.dueDate
    ) private var allNotes: [Note]
    @State private var viewModel = HomeViewModel()
    /// 当前用户角色。@Observable 单例,角色切换时本视图自动重画。
    @State private var profileManager = UserProfileManager.shared

    /// 角色切换后的一次性 hint banner 是否显示。
    /// 机制:UserDefaults 存上次"看到主屏的角色",当前角色和它不同 → 显示 banner;
    /// 用户点 X 关闭 → 写入 dismissed flag(以新角色为 key),下次切换才再触发。
    @State private var showsProfileSwitchBanner: Bool = false
    @State private var profileSwitchBannerFromName: String = ""

    @State private var isShowingCamera = false
    @State private var cameraCapturedImage: UIImage?
    @State private var editingStagedIndex: EditingStagedIndex?

    @State private var photoAnalysisResult: PhotoAnalysisDisplay?
    @State private var isAnalyzingPhoto = false

    @State private var navPath = NavigationPath()

    /// 首页 4 档过滤 stat。点一个 stat 列就只显示那类;再点同一个还原全部。
    @State private var todoFilter: TodoFilter = .all

    /// 各分类折叠状态(独立 binding)。
    @State private var overdueExpanded = true
    @State private var todayExpanded = true
    @State private var inboxExpanded = true
    @State private var hazardExpanded = true
    @State private var archivedExpanded = false

    // Engineer 专属分组的折叠状态。
    // Engineer 主屏 R7 简化后只剩"最近笔记"一段(默认展开,无需折叠交互,但保留 binding 以走通用 section 渲染)。
    @State private var recentNotesExpanded = true

    /// 天气 + 位置数据源(@Observable,属性变化会驱动 body 刷新)
    @State private var headerProvider = AppHeaderProvider.shared

    private let listVM = NoteListViewModel()

    enum TodoFilter: Hashable {
        case all, overdue, today, inbox, hazard
    }

    /// 首屏可显示的分组。按 ProfileKind 决定渲染哪几条。
    /// PM:hazard / overdue / today / inbox / archived(原行为)
    /// Engineer(R7 简化):**只一个** recentNotes 段 —— 工程师巡检入口在「报告」Tab,
    ///   主屏不需要 PM 的"今天/隐患/逾期"分桶,工程师就想看自己刚记的最近内容。
    private enum HomeSection: Hashable {
        case hazard, overdue, today, inbox, archived
        case recentNotes
    }

    /// 当前 Profile 决定的 section 顺序。
    private var visibleSections: [HomeSection] {
        switch profileManager.current {
        case .pm:
            return [.hazard, .overdue, .today, .inbox, .archived]
        case .engineer:
            return [.recentNotes]
        }
    }

    // MARK: - Derived data
    // 设计:4 组 **互斥**,hazard 优先吃掉其他档。
    // 一条"逾期的隐患"只出现在隐患组,不在逾期组重复。

    private var sections: NoteListViewModel.Sections {
        listVM.partition(allNotes)
    }

    /// 隐患:pending 或 inbox 里 isHazard=true 的(未完成)。
    /// 施工日记如果 AI 判定了隐患,也该进这组——安全信号永远要看见。
    private var hazardNotes: [Note] {
        (sections.pending + sections.inbox).filter { $0.isHazard }
    }

    /// 逾期:pending + 已过期 + **非隐患**。
    /// 施工日记如果用户确认了 AI 的 deadline(混合 note,如"水工来了今天下午验收"),仍然显示——真的 urgency 不过滤。
    private var overdueNotes: [Note] {
        let now = Date()
        return sections.pending.filter { $0.dueDate < now && !$0.isHazard }
    }

    /// 今天:pending + 今天到期 + **非隐患** + **非逾期**。
    private var todayNotes: [Note] {
        let cal = Calendar.current
        let now = Date()
        return sections.pending.filter {
            $0.dueDate >= now
                && cal.isDateInToday($0.dueDate)
                && !$0.isHazard
        }
    }

    /// 待分类:inbox + **非隐患** + **非施工日记**。
    /// 施工日记默认 deadline=.inbox 但它不是"待分类",所以这里滤掉——它在 LogTabView 纵览的"待分类"段里显示。
    private var inboxNotes: [Note] {
        sections.inbox.filter { !$0.isHazard && !$0.isDiaryRecord }
    }

    /// 已完成 / 已归档(PM 与 Engineer 共用 logic)。
    /// `sections.done` 已经按 createdAt 倒序;再加 `sections.archived` 以承接"只是记录"的速记。
    private var doneOrArchivedNotes: [Note] {
        sections.done + sections.archived
    }

    // MARK: - Engineer 派生数据
    //
    // R7 后 Engineer 主屏不再分桶展示 pending/done — 列表只显示 recentNotes,
    // 但 engineerPendingNotes / engineerDoneNotes 仍被顶部 statsRow 使用(快速指标),
    // 故保留计算属性。

    /// Engineer "最近 Note":按 createdAt 倒序,过滤已删除,取前 20 条。
    /// 不分桶不过滤其他维度 —— 工程师就是要看自己刚记的内容。
    private var recentNotes: [Note] {
        allNotes
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(20)
            .map { $0 }
    }

    /// 工程师"待巡检":pending + inbox 中 (隐患 ∪ 已逾期 ∪ 含勾选项的巡检) 的未完成项。
    /// 用 isDone == false 兜一下(理论上 sections.pending/inbox 都是未完成,但保险)。
    private var engineerPendingNotes: [Note] {
        let now = Date()
        let pool = sections.pending + sections.inbox
        return pool.filter { note in
            !note.isDone &&
            (note.isHazard || note.dueDate < now || !note.checkedItems.isEmpty || note.floorPlanRef != nil)
        }
    }

    /// 工程师"已完成":只在巡检视角范围内 — 与 engineerPendingNotes 同口径,
    /// 但 isDone == true。避免主屏 stats 里"已完成"显示 PM 全集导致和"待巡检"看似不对账(E2.10)。
    private var engineerDoneNotes: [Note] {
        let now = Date()
        let pool = allNotes
        return pool.filter { note in
            note.isDone &&
            (note.isHazard || note.dueDate < now || !note.checkedItems.isEmpty || note.floorPlanRef != nil)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private var todayDateLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEEE · d MMM"
        return f.string(from: Date())
    }

    // MARK: - Body

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack(path: $navPath) {
            ZStack(alignment: .bottom) {
                Ink.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    // AI 自动转日志后的 5s 提示 banner(只在录音/拍照空闲时露,
                    // 避免遮挡录音中的反馈区)。
                    if !viewModel.isRecording && viewModel.stagedPhotos.isEmpty {
                        DiaryConversionBanner()
                    }
                    if viewModel.isRecording {
                        recordingTopArea
                    } else if !viewModel.stagedPhotos.isEmpty {
                        stagedPhotoFocusArea
                    } else {
                        // 角色切换后的一次性 hint(idle 态才显示,别打扰录音/拍照)
                        if showsProfileSwitchBanner {
                            profileSwitchBanner
                        }
                        idleTopArea
                    }
                    // heroButtons 常驻(MIC DragGesture 节点稳定)。
                    // 只在有 lastSave(undo toast 显示中)时隐藏,给 toast 让位盖住这块空间。
                    if viewModel.lastSave == nil {
                        heroButtons
                            .padding(.bottom, 20)
                    }
                }

                if viewModel.lastSave != nil {
                    undoToastOverlay
                        .padding(.horizontal, 12)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

            }
            .navigationBarHidden(true)
            .task {
                // P2 改:不再启动就请求权限。
                // - 麦克风/语音:用户首次按住 MIC 时由 HomeViewModel.startRecording 触发请求
                // - 通知:首次有 note 需要排推送时由 NotificationService.schedule 触发请求
                viewModel.setup(modelContext: modelContext)
                NotificationService.shared.rescheduleAll(notes: allNotes)
                headerProvider.ensureFresh()
                evaluateProfileSwitchBanner()
            }
            .onChange(of: profileManager.current) { _, _ in
                evaluateProfileSwitchBanner()
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
            .navigationDestination(for: AIStatusDestination.self) { _ in
                InputAISettingsView()
            }
            .navigationDestination(for: InspectionEntryDestination.self) { _ in
                InspectionReportListView()
            }
            .alert("出错了", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 {
                    viewModel.errorMessage = nil
                    viewModel.showsPermissionSettingsButton = false
                } }
            )) {
                // E1.6:权限被拒时多一个"打开设置"快速入口。
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
            .sheet(item: $photoAnalysisResult) { result in
                PhotoAnalysisResultView(result: result.analysis)
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.lastSave?.noteID)
        }
    }

    // MARK: - Profile switch hint banner

    /// 一次性提醒 banner:用户从其他角色切到当前角色后,首次进入主屏显示。
    /// 数据没消失,只是分组规则不一样——给入口跳转到日志的"纵览"段,让 PM 老数据可见。
    /// 视觉与 OpenPlantSessionsBanner 风格保持一致(细横条 + icon + 操作)。
    private var profileSwitchBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ink.fg)
            VStack(alignment: .leading, spacing: 2) {
                Text("已切换到 \(profileManager.current.displayName) 模式")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                Text("之前的所有记录都还在")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
            }
            Spacer(minLength: 8)
            Button {
                AppRouter.shared.requestTab(.log, logMode: .overview)
            } label: {
                Text("打开日志")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Ink.fg, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            Button {
                dismissProfileSwitchBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.fgDim)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Ink.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: 1)
        }
    }

    /// 评估当前角色是否需要显示切换提醒 banner。
    /// 规则:
    ///   - lastSeenProfile 不存在 → 写入当前角色,不显示(首次启动)
    ///   - lastSeenProfile != current 且 dismissed flag (key 含当前角色) 未设 → 显示
    ///   - 用户点 X → dismissed flag 写为 true,直到下次再切换才会清空
    private func evaluateProfileSwitchBanner() {
        let defaults = UserDefaults.standard
        let currentRaw = profileManager.current.rawValue
        let lastSeen = defaults.string(forKey: Self.lastSeenProfileKey)

        guard let last = lastSeen else {
            // 首次记录,不显示
            defaults.set(currentRaw, forKey: Self.lastSeenProfileKey)
            showsProfileSwitchBanner = false
            return
        }

        if last == currentRaw {
            // 没切换过,不显示(并清掉残留 dismissed flag,避免堵塞)
            showsProfileSwitchBanner = false
            return
        }

        // 真切换了:更新 lastSeen 并清掉旧 dismissed flag(每次切换都重新触发)
        defaults.set(currentRaw, forKey: Self.lastSeenProfileKey)
        defaults.removeObject(forKey: Self.dismissedFlagKey(for: currentRaw))

        if let lastKind = ProfileKind(rawValue: last) {
            profileSwitchBannerFromName = lastKind.displayName
        } else {
            profileSwitchBannerFromName = ""
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            showsProfileSwitchBanner = true
        }
    }

    private func dismissProfileSwitchBanner() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.dismissedFlagKey(for: profileManager.current.rawValue))
        withAnimation(.easeInOut(duration: 0.2)) {
            showsProfileSwitchBanner = false
        }
    }

    private static let lastSeenProfileKey = "record.lastSeenProfile"
    private static func dismissedFlagKey(for raw: String) -> String {
        "record.profileSwitchBanner.dismissed.\(raw)"
    }

    // MARK: - Idle top area

    private var idleTopArea: some View {
        VStack(spacing: 0) {
            // 固定顶区:AI 状态条 + 标题 + Key 引导(若需) + 统计 stats + 开启中机械提示
            VStack(alignment: .leading, spacing: 0) {
                AIStatusBar()
                titleBlock
                AIKeyHintBanner()            // AI 没配且没 dismiss 时出现
                OpenPlantSessionsBanner()    // 有未闭合的挖机 session 时才显示
                statsRow
            }
            // 可滚动分组 list(折叠 + 左右滑)
            todoListArea
        }
    }

    /// "今天"大标题 + 齿轮 + 下方 subtitle(日期 · 天气 · 位置)。
    /// 顶部 padding 20 / bottom 16,和 LogTabView、ReportsView 的标题行对齐。
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("今天")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.8)
                    .foregroundStyle(Ink.fg)
                Spacer()
                SearchBarButton()
                NavigationLink(value: SettingsDestination()) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Ink.fgDim)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("设置")
            }
            subtitleRow
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    /// 日期 · 天气 · 位置 — 一行小字副标题。
    /// 位置名有时很长(反向地理编码会返回区 + 州 + 国),用 minimumScaleFactor 兜底,
    /// 不够时整行缩放而不是挤爆换行。
    private var subtitleRow: some View {
        HStack(spacing: 6) {
            Text(todayDateLabel)
            if let weather = headerProvider.weatherSummary {
                Text("·")
                Text(weather)
            }
            if let loc = headerProvider.locationShort {
                Text("·")
                Image(systemName: "location.fill")
                    .font(.system(size: 9))
                Text(loc)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .tracking(-0.1)
        .foregroundStyle(Ink.fgDim)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    /// 顶部 stats 行。Profile 决定显示几个 cell:
    /// - PM:4 档(逾期 / 今天 / 待分类 / 隐患),点击切 todoFilter
    /// - Engineer:2 档(待巡检 / 已完成),纯展示
    @ViewBuilder
    private var statsRow: some View {
        switch profileManager.current {
        case .pm:
            pmStatsRow
        case .engineer:
            engineerStatsRow
        }
    }

    /// PM 4 档 stat 切换:逾期 / 今天 / 待分类 / 隐患。点击某个就筛到那类,再点还原。
    /// 选中态:数字放大 + 色块底 + label 加粗。
    private var pmStatsRow: some View {
        HStack(spacing: 6) {
            statCell(
                filter: .overdue,
                count: overdueNotes.count,
                label: String(localized: "逾期", locale: AppLanguageManager.currentLocale),
                color: Ink.red
            )
            statCell(
                filter: .today,
                count: todayNotes.count,
                label: String(localized: "今天", locale: AppLanguageManager.currentLocale),
                color: Ink.fg
            )
            statCell(
                filter: .inbox,
                count: inboxNotes.count,
                label: String(localized: "待分类", locale: AppLanguageManager.currentLocale),
                color: Ink.fgDim
            )
            statCell(
                filter: .hazard,
                count: hazardNotes.count,
                label: String(localized: "隐患", locale: AppLanguageManager.currentLocale),
                color: Ink.red,
                icon: "exclamationmark.triangle.fill"
            )
        }
        .padding(.horizontal, 24)   // 对齐标题 / subtitle / 列表的 24pt 左右边距
        .padding(.bottom, 10)
    }

    /// Engineer 2 档 stat:待巡检 / 已完成。展示型,不切 filter(filter 仍只服务 PM)。
    /// "已完成"用 engineerDoneNotes(同口径),避免和 PM doneOrArchived 全集混淆(E2.10)。
    private var engineerStatsRow: some View {
        HStack(spacing: 6) {
            readonlyStatCell(
                count: engineerPendingNotes.count,
                label: String(localized: "待巡检", locale: AppLanguageManager.currentLocale),
                color: Ink.accentBlue
            )
            readonlyStatCell(
                count: engineerDoneNotes.count,
                label: String(localized: "已完成", locale: AppLanguageManager.currentLocale),
                color: Ink.green
            )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    /// 非 PM 用的展示型 stat cell:点击跳到日志「纵览」段(只读 hint = chevron),
    /// 之前用户会误以为是 PM 的可切档 stat,加 caret + tap 跳转给一个清晰出口(E2.8)。
    private func readonlyStatCell(
        count: Int,
        label: String,
        color: Color,
        icon: String? = nil
    ) -> some View {
        Button {
            AppRouter.shared.requestTab(.log, logMode: .overview)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(count)")
                        .font(.system(size: 26, weight: .semibold))
                        .tracking(-0.8)
                        .foregroundStyle(count > 0 ? color : Ink.dim)
                        .monospacedDigit()
                    if let icon, count > 0 {
                        Image(systemName: icon)
                            .font(.system(size: 10))
                            .foregroundStyle(color)
                    }
                    Spacer(minLength: 0)
                    // 提示这是个跳转入口,不是和 PM 同样的 toggle stat。
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Ink.dim)
                }
                Text(label)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Ink.fgDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(count > 0 ? color.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statCell(
        filter: TodoFilter,
        count: Int,
        label: String,
        color: Color,
        icon: String? = nil
    ) -> some View {
        let isSelected = todoFilter == filter
        let canSelect = count > 0 || isSelected
        return Button {
            guard canSelect else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                todoFilter = isSelected ? .all : filter
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    // 不用大小跳跃表达选中——改用色块底 + 边框 + 加粗标签。
                    // 之前 34pt vs 26pt 会让整行高度变化,视觉抖动。
                    Text("\(count)")
                        .font(.system(size: 26, weight: .semibold))
                        .tracking(-0.8)
                        .foregroundStyle(count > 0 ? color : Ink.dim)
                        .monospacedDigit()
                    if let icon, count > 0 {
                        Image(systemName: icon)
                            .font(.system(size: 10))
                            .foregroundStyle(color)
                    }
                }
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Ink.fg : Ink.fgDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? color.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? color.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .opacity(canSelect ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!canSelect)
    }

    /// 折叠 + swipeActions 的 todo list。用 List 包住,swipeActions 才能被识别。
    /// 按 Profile 切换的是 sections 顺序与内容(visibleSections);单个 section 的渲染统一走 foldableTodoSection。
    ///
    /// R7:Engineer 模式不再在此插入"新建 Inspection"按钮 —— 巡检入口已搬到「报告」Tab 的
    /// InspectionReportListView,主屏简化为「最近 Note」一段。
    @ViewBuilder
    private var todoListArea: some View {
        if visibleSections.allSatisfy({ notes(for: $0).isEmpty }) {
            emptyHint
        } else {
            List {
                ForEach(visibleSections, id: \.self) { section in
                    let items = notes(for: section)
                    if !items.isEmpty, showSection(matching: section) {
                        foldableTodoSection(
                            title: title(for: section),
                            color: color(for: section),
                            notes: items,
                            expanded: expansionBinding(for: section)
                        )
                    }
                }
            }
            .listStyle(.plain)
            .industrialForm()
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    /// 取某 section 对应的 notes 数组(集中维护,UI 不直接读底层)。
    private func notes(for section: HomeSection) -> [Note] {
        switch section {
        case .hazard: return hazardNotes
        case .overdue: return overdueNotes
        case .today: return todayNotes
        case .inbox: return inboxNotes
        case .archived: return doneOrArchivedNotes
        case .recentNotes: return recentNotes
        }
    }

    private func title(for section: HomeSection) -> String {
        switch section {
        case .hazard: return String(localized: "隐患", locale: AppLanguageManager.currentLocale)
        case .overdue: return String(localized: "逾期", locale: AppLanguageManager.currentLocale)
        case .today: return String(localized: "今天到期", locale: AppLanguageManager.currentLocale)
        case .inbox: return String(localized: "待分类", locale: AppLanguageManager.currentLocale)
        case .archived: return String(localized: "已完成", locale: AppLanguageManager.currentLocale)
        case .recentNotes: return String(localized: "最近记录", locale: AppLanguageManager.currentLocale)
        }
    }

    private func color(for section: HomeSection) -> Color {
        switch section {
        case .hazard, .overdue: return Ink.red
        case .today: return Ink.fg
        case .inbox: return Ink.fgDim
        case .archived: return Ink.fgDim
        case .recentNotes: return Ink.fg
        }
    }

    private func expansionBinding(for section: HomeSection) -> Binding<Bool> {
        switch section {
        case .hazard: return $hazardExpanded
        case .overdue: return $overdueExpanded
        case .today: return $todayExpanded
        case .inbox: return $inboxExpanded
        case .archived: return $archivedExpanded
        case .recentNotes: return $recentNotesExpanded
        }
    }

    /// 当前过滤下该 section 是否显示。
    /// 已废弃过滤隐藏逻辑(polish #1):filter 只作为高亮选中态,所有 section 始终可见,
    /// 用户点"逾期"高亮后不丢失其他段的上下文。函数保留以承接 todoListArea 调用点,
    /// 总是返回 true。
    private func showSection(matching section: HomeSection) -> Bool {
        return true
    }

    private func foldableTodoSection(
        title: String,
        color: Color,
        notes: [Note],
        expanded: Binding<Bool>
    ) -> some View {
        Section {
            if expanded.wrappedValue {
                ForEach(notes) { note in
                    NavigationLink(value: note) {
                        NoteRow(note: note, urgency: listVM.urgency(for: note))
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Ink.bg)
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            softDelete(note)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .tint(Ink.red)
                    }
                }
            }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(color)
                    Spacer()
                    Text("\(notes.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.dim)
                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Ink.dim)
                        .padding(.leading, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .textCase(nil)
        }
    }

    /// 空态
    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Ink.line).frame(height: 1)
                .padding(.bottom, 20)
            Text("今天没有待办")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ink.fg)
            Text("按住下方麦克风说话,开始一条新速记。")
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

    // MARK: - 拍照暂存"专注"模式
    //
    // 用户点相机拍完后,stagedPhotos 非空。我们隐藏 stats / 最紧急 / 列表,
    // 整个上方区域只显示:标题 + 最后一张大图预览(小图缩略行在下面),
    // 主操作按钮("直接存" / "AI 分析")**下移到右手拇指可达的位置**。
    @ViewBuilder
    private var stagedPhotoFocusArea: some View {
        VStack(spacing: 0) {
            // 顶部栏:标题 + 齿轮 + "丢弃"
            HStack {
                Text("刚拍 \(viewModel.stagedPhotos.count) 张")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(Ink.fg)
                Spacer()
                Button {
                    viewModel.clearStagedPhotos()
                } label: {
                    Text("丢弃")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.red)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // 大图(最后一张)+ 右上角减号删除
            if let last = viewModel.stagedPhotos.last {
                let lastIdx = viewModel.stagedPhotos.count - 1
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: last)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 380)
                        .background(Ink.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingStagedIndex = EditingStagedIndex(value: lastIdx, image: last)
                        }

                    deletePhotoButton {
                        viewModel.removeStagedPhoto(at: lastIdx)
                    }
                    .padding(10)
                }
                .padding(.horizontal, 24)
            }

            // 缩略图行(非最后一张)+ 每张右上角减号
            if viewModel.stagedPhotos.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(viewModel.stagedPhotos.dropLast().enumerated()), id: \.offset) { idx, image in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    editingStagedIndex = EditingStagedIndex(value: idx, image: image)
                                } label: {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(Ink.line, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)

                                deletePhotoButton(size: 18) {
                                    viewModel.removeStagedPhoto(at: idx)
                                }
                                .offset(x: 6, y: -6)
                            }
                            .frame(width: 62, height: 62, alignment: .topTrailing)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 12)

            // 主操作按钮:下移到右手拇指触碰区(屏幕下半部)
            HStack(spacing: 10) {
                Button {
                    viewModel.savePhotosOnly()
                } label: {
                    Text("直接存")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Ink.fg, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    analyzeLastStagedPhoto()
                } label: {
                    HStack(spacing: 6) {
                        if isAnalyzingPhoto {
                            SparkleLoading(label: "分析中")
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                            Text("AI 分析")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Ink.fg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isAnalyzingPhoto)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    /// 删除按钮:黑圆底白色减号,右上角悬浮。用于暂存照片的大图和缩略图。
    private func deletePhotoButton(size: CGFloat = 24, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus")
                .font(.system(size: size * 0.55, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(width: size, height: size)
                .background(Ink.fg)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(Color.white, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("删除这张照片")
    }


    // MARK: - Recording top area

    private var recordingTopArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        PulsingDot(color: Ink.red)
                        Text("REC")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.3)
                            .foregroundStyle(Ink.red)
                    }
                    // E1.1:实时计时。TimelineView 每 0.5s tick 一次,
                    // 工地用户长录(30-60s)能看到进度。
                    // recordingStartTime 为 nil(未录音/已 commit)显示占位 ●:●●。
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        Text(recordingDurationLabel(now: ctx.date))
                            .font(.system(size: 40, weight: .medium))
                            .tracking(-1.2)
                            .foregroundStyle(Ink.fg)
                            .monospacedDigit()
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(allNotes.first?.siteTag ?? "SiteNote")
                        .foregroundStyle(Ink.fgDim)
                    Text("双通道 · zh+en")
                        .foregroundStyle(Ink.fgDim)
                }
                .font(.system(size: 12))
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)

            // Thin waveform
            AudioWaveformView(level: viewModel.currentAudioLevel)
                .frame(height: 48)
                .padding(.horizontal, 24)
                .padding(.top, 40)

            // Transcript
            VStack(alignment: .leading, spacing: 10) {
                Text("转写")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Ink.fgDim)
                HStack(alignment: .top, spacing: 2) {
                    Text(viewModel.partialTranscription.isEmpty ? "…" : viewModel.partialTranscription)
                        .font(.system(size: 18, weight: .regular))
                        .tracking(-0.2)
                        .lineSpacing(4)
                        .foregroundStyle(Ink.fg)
                    if !viewModel.partialTranscription.isEmpty {
                        BlinkingCursor()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 24)

            Spacer()
        }
    }

    /// E1.1:基于 viewModel.recordingStartTime 实时计算 mm:ss。
    /// recordingStartTime 为 nil(未录音/已 commit)时显示占位 ●:●●。
    private func recordingDurationLabel(now: Date) -> String {
        guard let start = viewModel.recordingStartTime else { return "●:●●" }
        let elapsed = max(0, now.timeIntervalSince(start))
        let total = Int(elapsed)
        let mm = total / 60
        let ss = total % 60
        return String(format: "%02d:%02d", mm, ss)
    }

    // MARK: - Hero (常驻,MIC 按钮节点稳定)

    private var heroButtons: some View {
        HStack(spacing: 16) {
            // 布局:cam 在左 / mic 在右(更顺右手拇指)。
            // 录音时 cam 不销毁,只隐藏,让 mic 保持在右半槽位,不会"跳到中间"。
            cameraButton
                .opacity(viewModel.isRecording ? 0 : 1)
                .allowsHitTesting(!viewModel.isRecording)
            micButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var micButton: some View {
        // 单手势:按住录音,松手保存。日志 / 隐患 / 撤销 由 UndoToast 按钮承担。
        ZStack {
            Circle()
                .fill(circleColor)
                .frame(width: 132, height: 132)
            if viewModel.isRecording {
                Circle()
                    .stroke(circleColor.opacity(0.12), lineWidth: 10)
                    .frame(width: 142, height: 142)
            }
            Image(systemName: "mic.fill")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Color.white)
        }
        .frame(width: 132, height: 132)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !viewModel.isRecording { viewModel.startRecording() }
                }
                .onEnded { _ in
                    guard viewModel.isRecording else { return }
                    Task { await viewModel.stopAndSave() }
                }
        )
        .sensoryFeedback(.impact(weight: .heavy), trigger: viewModel.isRecording)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("录音")
        .accessibilityHint("长按开始录音,松手保存")
    }

    /// 录音时红色提醒,静息时黑色。
    private var circleColor: Color {
        viewModel.isRecording ? Ink.red : Ink.fg
    }

    private var cameraButton: some View {
        Circle()
            .fill(Ink.bg)
            .overlay(Circle().strokeBorder(Ink.fg, lineWidth: 1.5))
            .frame(width: 132, height: 132)
            .overlay(
                Image(systemName: "camera.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Ink.fg)
            )
            .onTapGesture {
                isShowingCamera = true
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: isShowingCamera)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("拍照")
    }

    // MARK: - Undo toast

    private var undoToastOverlay: some View {
        UndoToast(
            message: viewModel.lastSave?.summary ?? "",
            secondsRemaining: viewModel.undoSecondsRemaining,
            onSaveAsDiary: { viewModel.convertLastSaveToDiary() },
            onDetail: {
                if let note = viewModel.fetchLastSavedNote() {
                    navPath.append(note)
                }
                viewModel.dismissToastManually()
            },
            onUndo: { viewModel.undoLastSave() }
        )
    }
}

// MARK: - 光标闪烁

private struct BlinkingCursor: View {
    @State private var on = true
    var body: some View {
        Text("|")
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(Ink.fgDim)
            .opacity(on ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    on.toggle()
                }
            }
    }
}

private struct EditingStagedIndex: Identifiable {
    let id: UUID = UUID()
    let value: Int
    let image: UIImage
}

private struct PhotoAnalysisDisplay: Identifiable {
    let id = UUID()
    let analysis: AIService.PhotoAnalysis
}

extension RecordView {
    fileprivate func analyzeLastStagedPhoto() {
        guard let image = viewModel.stagedPhotos.last else { return }
        isAnalyzingPhoto = true
        Task {
            do {
                let result = try await AIService.shared.analyzePhoto(image)
                photoAnalysisResult = PhotoAnalysisDisplay(analysis: result)
            } catch {
                viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "AI 分析失败", locale: AppLanguageManager.currentLocale)
            }
            isAnalyzingPhoto = false
        }
    }
}

private struct PhotoAnalysisResultView: View {
    let result: AIService.PhotoAnalysis
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("AI 描述") {
                    Text(result.description).font(.system(size: 14))
                }
                if result.suggestedHazard {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Ink.red)
                            Text("建议标记为隐患")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Ink.red)
                        }
                    }
                }
                if let action = result.suggestedAction, !action.isEmpty {
                    Section("建议动作") {
                        Text(action).font(.system(size: 14))
                    }
                }
                if !result.rawLabels.isEmpty {
                    Section("原始标签") {
                        Text(result.rawLabels.joined(separator: " · "))
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.fgDim)
                    }
                }
            }
            .industrialForm()
            .navigationTitle("AI 分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, ShareLog.self, configurations: config)
    return RecordView().modelContainer(container)
}
