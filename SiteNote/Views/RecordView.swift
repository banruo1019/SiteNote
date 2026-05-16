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

    /// 当前激活的 chip filter(单选)。
    @State private var chipFilter: ChipFilter = .all
    /// 当前排序方式。
    @State private var sortMode: SortMode = .createdAt
    /// 归档工地 set,SettingsView 改完返回时 task 重新拉。
    @State private var archivedSiteTags: Set<String> = SiteArchiveStorage.loadArchived()

    @State private var headerProvider = AppHeaderProvider.shared
    @State private var profileManager = UserProfileManager.shared

    private let listVM = NoteListViewModel()

    /// 顶部 chip 过滤条件。除了固定几条,还会动态生成每个工地的 chip。
    enum ChipFilter: Hashable {
        case all
        case today
        case hazard
        case archived              // 已归档工地的 Note
        case site(String)          // 单个工地
    }

    /// 排序方式。
    enum SortMode: String, CaseIterable, Identifiable {
        case createdAt = "创建时间"
        case dueDate = "到期日期"
        case site = "工地"
        case tag = "标签"
        var id: String { rawValue }
        var displayName: String {
            String(localized: String.LocalizationValue(rawValue), locale: AppLanguageManager.currentLocale)
        }
    }

    // MARK: - Derived data

    /// 所有未删除的 Note。
    private var liveNotes: [Note] {
        allNotes.filter { $0.deletedAt == nil }
    }

    /// 已知工地 tag 列表(从 Note + SiteTagsStorage 合并 + 去重)。
    private var allSiteTags: [String] {
        let fromNotes = Set(liveNotes.compactMap { $0.siteTag })
        let configured = Set(SiteTagsStorage.load())
        return Array(fromNotes.union(configured)).sorted()
    }

    /// 应用 filter 后的 Note。
    private var filteredNotes: [Note] {
        let pool: [Note]
        switch chipFilter {
        case .all:
            // 默认隐藏归档工地里的 Note
            pool = liveNotes.filter { note in
                guard let site = note.siteTag else { return true }
                return !archivedSiteTags.contains(site)
            }
        case .today:
            let cal = Calendar.current
            pool = liveNotes.filter { cal.isDateInToday($0.dueDate) && !$0.isDone }
        case .hazard:
            pool = liveNotes.filter { $0.isHazard }
        case .archived:
            pool = liveNotes.filter { note in
                guard let site = note.siteTag else { return false }
                return archivedSiteTags.contains(site)
            }
        case .site(let tag):
            pool = liveNotes.filter { $0.siteTag == tag }
        }
        return applySort(pool)
    }

    private func applySort(_ notes: [Note]) -> [Note] {
        switch sortMode {
        case .createdAt:
            return notes.sorted { $0.createdAt > $1.createdAt }
        case .dueDate:
            return notes.sorted { $0.dueDate < $1.dueDate }
        case .site:
            return notes.sorted {
                let a = $0.siteTag ?? ""
                let b = $1.siteTag ?? ""
                if a == b { return $0.createdAt > $1.createdAt }
                return a < b
            }
        case .tag:
            return notes.sorted {
                let a = $0.otherTags.sorted().first ?? ""
                let b = $1.otherTags.sorted().first ?? ""
                if a == b { return $0.createdAt > $1.createdAt }
                return a < b
            }
        }
    }

    /// 各 chip 的计数(给数字徽章)。
    private var chipCounts: [ChipFilter: Int] {
        let cal = Calendar.current
        var counts: [ChipFilter: Int] = [:]
        // all = 非归档工地 + 无工地
        counts[.all] = liveNotes.filter { note in
            guard let s = note.siteTag else { return true }
            return !archivedSiteTags.contains(s)
        }.count
        counts[.today] = liveNotes.filter { cal.isDateInToday($0.dueDate) && !$0.isDone }.count
        counts[.hazard] = liveNotes.filter { $0.isHazard }.count
        counts[.archived] = liveNotes.filter { note in
            guard let s = note.siteTag else { return false }
            return archivedSiteTags.contains(s)
        }.count
        for tag in allSiteTags where !archivedSiteTags.contains(tag) {
            counts[.site(tag)] = liveNotes.filter { $0.siteTag == tag }.count
        }
        return counts
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

    @ViewBuilder
    private var siteGroupedList: some View {
        VStack(spacing: 0) {
            chipRow
            sortBar
            if filteredNotes.isEmpty {
                emptyHint
            } else {
                flatList
            }
        }
    }

    /// 顶部 chip 行(水平滚动,单选)。
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.all, label: String(localized: "全部", locale: AppLanguageManager.currentLocale))
                chip(.today, label: String(localized: "今天", locale: AppLanguageManager.currentLocale))
                chip(.hazard, label: String(localized: "隐患", locale: AppLanguageManager.currentLocale))
                ForEach(allSiteTags.filter { !archivedSiteTags.contains($0) }, id: \.self) { tag in
                    chip(.site(tag), label: tag)
                }
                if (chipCounts[.archived] ?? 0) > 0 {
                    chip(.archived, label: String(localized: "已归档", locale: AppLanguageManager.currentLocale))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private func chip(_ kind: ChipFilter, label: String) -> some View {
        let isOn = chipFilter == kind
        let count = chipCounts[kind] ?? 0
        return Button {
            chipFilter = kind
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(isOn ? Ink.bg : Ink.fgDim)
                }
            }
            .foregroundStyle(isOn ? Ink.bg : Ink.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isOn ? Ink.fg : Ink.card)
            )
        }
        .buttonStyle(.plain)
    }

    /// Sort 行:右侧 menu。
    private var sortBar: some View {
        HStack {
            Text("\(filteredNotes.count) 条")
                .font(.system(size: 11))
                .foregroundStyle(Ink.fgDim)
            Spacer()
            Menu {
                ForEach(SortMode.allCases) { mode in
                    Button {
                        sortMode = mode
                    } label: {
                        if sortMode == mode {
                            Label(mode.displayName, systemImage: "checkmark")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text(sortMode.displayName)
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Ink.fgDim)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    /// Flat 列表(Notion 风)。
    private var flatList: some View {
        List {
            ForEach(filteredNotes) { note in
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
        .listStyle(.plain)
        .industrialForm()
        .environment(\.defaultMinListRowHeight, 0)
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

            AudioWaveformView(level: viewModel.currentAudioLevel)
                .frame(height: 48)
                .padding(.horizontal, 24)
                .padding(.top, 40)

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
            cameraButton
                .opacity(viewModel.isRecording ? 0 : 1)
                .allowsHitTesting(!viewModel.isRecording)
            micButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var micButton: some View {
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

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, ShareLog.self, configurations: config)
    return RecordView().modelContainer(container)
}
