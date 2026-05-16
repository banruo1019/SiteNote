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
    @State var viewModel = HomeViewModel()
    /// 当前用户角色。@Observable 单例,角色切换时本视图自动重画。
    @State private var profileManager = UserProfileManager.shared

    @State private var isShowingCamera = false
    @State private var cameraCapturedImage: UIImage?
    @State var editingStagedIndex: EditingStagedIndex?

    @State var photoAnalysisResult: PhotoAnalysisDisplay?
    @State var isAnalyzingPhoto = false

    @State private var navPath = NavigationPath()

    /// PM 主屏折叠状态(R2 简化:5 段 → 2 段)。
    /// - 今天:hazard + overdue + today 合并(默认展开)
    /// - 其他:inbox + done/archived 合并(默认折叠)
    @State private var todayExpanded = true
    @State private var otherExpanded = false

    // Engineer 专属分组的折叠状态。
    // Engineer 主屏 R7 简化后只剩"最近笔记"一段(默认展开,无需折叠交互,但保留 binding 以走通用 section 渲染)。
    @State private var recentNotesExpanded = true

    /// 天气 + 位置数据源(@Observable,属性变化会驱动 body 刷新)
    @State private var headerProvider = AppHeaderProvider.shared

    private let listVM = NoteListViewModel()

    /// 首屏可显示的分组。按 ProfileKind 决定渲染哪几条。
    /// PM(v1.2 减负):2 段 — todayMerged(隐患/逾期/今天)、otherMerged(待分类/已完成已归档)。
    /// Engineer(R7 简化):**只一个** recentNotes 段 —— 工程师巡检入口在「报告」Tab,
    ///   主屏不需要 PM 的"今天/隐患/逾期"分桶,工程师就想看自己刚记的最近内容。
    private enum HomeSection: Hashable {
        case todayMerged, otherMerged
        case recentNotes
    }

    /// 当前 Profile 决定的 section 顺序。
    private var visibleSections: [HomeSection] {
        switch profileManager.current {
        case .pm:
            return [.todayMerged, .otherMerged]
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

    /// PM 主屏"今天"段:隐患 + 逾期 + 今天到期(R2 减负后合并为一段)。
    /// 顺序保留 hazard → overdue → today,优先级从高到低,UI 上仍能一眼看到隐患在最前。
    private var todayMergedNotes: [Note] {
        hazardNotes + overdueNotes + todayNotes
    }

    /// PM 主屏"其他"段:待分类 + 已完成/归档(默认折叠)。
    private var otherMergedNotes: [Note] {
        inboxNotes + doneOrArchivedNotes
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
                    if viewModel.isRecording {
                        recordingTopArea
                    } else if !viewModel.stagedPhotos.isEmpty {
                        stagedPhotoFocusArea
                    } else {
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

    // MARK: - Idle top area

    private var idleTopArea: some View {
        VStack(spacing: 0) {
            // 固定顶区:标题 + 统计 stats(PM 已减负为 EmptyView,Engineer 保留)
            VStack(alignment: .leading, spacing: 0) {
                titleBlock
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

    /// 日期单行副标题。
    /// v1.2 减负:仅显示日期,天气 / 位置不再渲染。
    /// 注意:headerProvider 仍在 task 阶段 ensureFresh,下游 Note 字段(siteTag/weather)
    /// 由 HomeViewModel 在保存时回填,PDF 报告路径不受影响。
    private var subtitleRow: some View {
        Text(todayDateLabel)
            .font(.system(size: 12, weight: .medium))
            .tracking(-0.1)
            .foregroundStyle(Ink.fgDim)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    /// 顶部 stats 行。Profile 决定显示几个 cell:
    /// - PM(v1.2 减负):无 stat,EmptyView()。
    /// - Engineer:2 档(待巡检 / 已完成),纯展示
    @ViewBuilder
    private var statsRow: some View {
        switch profileManager.current {
        case .pm:
            EmptyView()
        case .engineer:
            engineerStatsRow
        }
    }

    /// Engineer 2 档 stat:待巡检 / 已完成。展示型。
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

    /// 非 PM 用的展示型 stat cell:纯只读,不可点(v1.2 大减负 LogTab 下架后,
    /// 原"点击跳日志纵览"目标消失,改成纯数字展示)。
    private func readonlyStatCell(
        count: Int,
        label: String,
        color: Color,
        icon: String? = nil
    ) -> some View {
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
                ForEach(Array(visibleSections.enumerated()), id: \.element) { idx, section in
                    let items = notes(for: section)
                    if !items.isEmpty, showSection(matching: section) {
                        // PM v1.2 减负:在两段之间插一条视觉分隔(Section header 之外的明显分界)。
                        if idx > 0 {
                            Divider()
                                .overlay(Ink.line)
                                .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 4, trailing: 24))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Ink.bg)
                        }
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
        case .todayMerged: return todayMergedNotes
        case .otherMerged: return otherMergedNotes
        case .recentNotes: return recentNotes
        }
    }

    private func title(for section: HomeSection) -> String {
        switch section {
        case .todayMerged: return String(localized: "今天", locale: AppLanguageManager.currentLocale)
        case .otherMerged: return String(localized: "其他", locale: AppLanguageManager.currentLocale)
        case .recentNotes: return String(localized: "最近记录", locale: AppLanguageManager.currentLocale)
        }
    }

    private func color(for section: HomeSection) -> Color {
        switch section {
        case .todayMerged: return Ink.fg
        case .otherMerged: return Ink.fgDim
        case .recentNotes: return Ink.fg
        }
    }

    private func expansionBinding(for section: HomeSection) -> Binding<Bool> {
        switch section {
        case .todayMerged: return $todayExpanded
        case .otherMerged: return $otherExpanded
        case .recentNotes: return $recentNotesExpanded
        }
    }

    /// 当前过滤下该 section 是否显示。
    /// v1.2 减负后无 filter,这里恒为 true 但保留以承接 todoListArea 调用点。
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

struct EditingStagedIndex: Identifiable {
    let id: UUID = UUID()
    let value: Int
    let image: UIImage
}

struct PhotoAnalysisDisplay: Identifiable {
    let id = UUID()
    let analysis: AIService.PhotoAnalysis
}

extension RecordView {
    func analyzeLastStagedPhoto() {
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
