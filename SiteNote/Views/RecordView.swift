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

    @State private var isShowingCamera = false
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
        }
    }

    // MARK: - Idle top area

    private var idleTopArea: some View {
        VStack(spacing: 0) {
            titleBlock
            siteGroupedList
        }
    }

    /// "记" 大标题 + 齿轮 + Search。
    private var titleBlock: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "记", locale: AppLanguageManager.currentLocale))
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
            EngineerSiteFilterBar(
                allTags: engineerAllSiteTags,
                selection: $engineerSiteFilter,
                countFor: { tag in
                    if let tag {
                        return liveNotes.filter { $0.siteTag == tag }.count
                    }
                    return liveNotes.count
                }
            )
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
            isShowingCamera = true
        }
    }

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
