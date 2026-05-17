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

    /// 所有未删除的 Note。
    private var liveNotes: [Note] {
        allNotes.filter { $0.deletedAt == nil }
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

    /// 待办段:未完成,按 createdAt 倒序。
    private var pendingNotes: [Note] {
        basePool
            .filter { !$0.isDone }
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
            // 工程师巡检中:每条录音/拍照保存后自动跳详情(每条要详细记录,不是速记)
            // PM / 自由速记不触发,保留主屏 Undo Toast 流程。
            .onChange(of: viewModel.lastSave?.noteID) { _, newID in
                guard newID != nil,
                      profileManager.current == .engineer,
                      sessionManager.isActive else { return }
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
    private var engineerIdleContent: some View {
        VStack(spacing: 0) {
            titleBlockMinimal
            engineerStartInspectionCTA
                .padding(.horizontal, 24)
                .padding(.top, 8)
            engineerIdleHelpText
                .padding(.horizontal, 24)
                .padding(.top, 28)
            Spacer(minLength: 0)
        }
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
            sessionSearchBar
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
    /// 搜索文本生效时,在已限定的子集里继续过滤。
    private var currentSessionNotes: [Note] {
        guard let sid = sessionManager.currentSessionID else { return [] }
        let scoped = liveNotes.filter { $0.inspectionSessionID == sid }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [Note]
        if query.isEmpty {
            filtered = scoped
        } else {
            filtered = scoped.filter { note in
                if note.transcription.lowercased().contains(query) { return true }
                if note.otherTags.contains(where: { $0.lowercased().contains(query) }) { return true }
                return false
            }
        }
        return filtered.sorted { $0.createdAt > $1.createdAt }
    }

    /// 巡检中专用 search bar — placeholder 改成"搜索本次巡检"。
    /// 视觉与 searchBar 保持一致,只换 placeholder 文案。
    private var sessionSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Ink.fgDim)
            TextField(
                String(localized: "搜索本次巡检", locale: AppLanguageManager.currentLocale),
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
                if pendingNotes.isEmpty && doneNotes.isEmpty {
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

    /// 两段列表:待办(常显) + 已完成(可折叠)。
    private var twoSectionList: some View {
        List {
            // 待办段
            if !pendingNotes.isEmpty {
                Section {
                    ForEach(pendingNotes) { note in
                        noteRowItem(note)
                    }
                } header: {
                    sectionHeader(
                        title: String(localized: "待办", locale: AppLanguageManager.currentLocale),
                        count: pendingNotes.count,
                        foldable: false,
                        expanded: .constant(true)
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

    /// 单条 Note row + swipe actions。
    /// 视觉本体在 `NoteTimelineRow`,这里只包 NavigationLink + swipe / list inset。
    @ViewBuilder
    private func noteRowItem(_ note: Note) -> some View {
        NavigationLink(value: note) {
            NoteTimelineRow(note: note)
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

    /// Section header — 标题左 + 计数 chip + (可选)折叠 chevron。
    private func sectionHeader(
        title: String,
        count: Int,
        foldable: Bool,
        expanded: Binding<Bool>
    ) -> some View {
        Button {
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
                    .foregroundStyle(Ink.fgDim)
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Ink.fg2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Ink.card)
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
            siteTag: allNotes.first?.siteTag
        )
    }

    // MARK: - Hero (常驻,MIC 按钮节点稳定)

    private var heroButtons: some View {
        HeroButtons(viewModel: viewModel) {
            // Engineer 在 idle 态点 camera → 先开 session(必须归属一次巡检)
            if profileManager.current == .engineer && !sessionManager.isActive {
                showsStartSheet = true
            } else {
                isShowingCamera = true
            }
        }
    }

    // TODO: mic 按钮的拦截 — HeroButtons 用 DragGesture 实现录音,不走 callback。
    // 现状:Engineer idle 态长按 mic 仍会录,note 因没 sessionID 不进当前 session 列表(也不显示在 idle 帮助页)。
    // 短期上看是"丢失感",待 HeroButtons 暴露 onMicAttempt 拦截钩子后,改成弹 StartInspectionSheet。

    // MARK: - Undo toast

    private var undoToastOverlay: some View {
        UndoToast(
            message: viewModel.lastSave?.summary ?? "",
            secondsRemaining: viewModel.undoSecondsRemaining,
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
