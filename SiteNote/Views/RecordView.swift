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

    /// 每个工地大组的折叠状态(siteTag → expanded)。默认全部展开。
    @State private var siteExpansion: [String: Bool] = [:]
    /// 已归档项目段的折叠状态(默认折叠)。
    @State private var archivedSectionExpanded: Bool = false

    /// 数据源:UserDefaults 里归档的工地 tag set。@State 同步触发 view 刷新,
    /// SiteResourcesSettingsView 切换后回到主屏会 reload。
    @State private var archivedSiteTags: Set<String> = SiteArchiveStorage.loadArchived()

    @State private var headerProvider = AppHeaderProvider.shared
    @State private var profileManager = UserProfileManager.shared

    private let listVM = NoteListViewModel()

    // MARK: - Derived data

    /// 所有未删除的 Note(用作分组源)。
    private var liveNotes: [Note] {
        allNotes.filter { $0.deletedAt == nil }
    }

    /// 已知工地 tag 列表(从 Note + SiteTagsStorage 合并 + 去重)。
    /// 保证用户配置的工地即使没 Note 也会显示(用户可以归档空工地)。
    private var allSiteTags: [String] {
        let fromNotes = Set(liveNotes.compactMap { $0.siteTag })
        let configured = Set(SiteTagsStorage.load())
        let merged = fromNotes.union(configured)
        return Array(merged).sorted()
    }

    /// 活跃(未归档)工地 + 这些工地的 Note。
    private var activeSiteGroups: [(siteTag: String, notes: [Note])] {
        allSiteTags
            .filter { !archivedSiteTags.contains($0) }
            .map { tag in
                let notes = liveNotes.filter { $0.siteTag == tag }
                return (siteTag: tag, notes: notes)
            }
    }

    /// 无工地的 Note(siteTag == nil 或空)。**单独一组** 渲染在最上面。
    private var orphanNotes: [Note] {
        liveNotes.filter { ($0.siteTag ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// 已归档工地组 + 这些工地的 Note。
    private var archivedSiteGroups: [(siteTag: String, notes: [Note])] {
        allSiteTags
            .filter { archivedSiteTags.contains($0) }
            .map { tag in
                let notes = liveNotes.filter { $0.siteTag == tag }
                return (siteTag: tag, notes: notes)
            }
    }

    /// 一个工地内按 otherTags 分子组。
    /// - 同时拥有多个 tag 的 Note 会在每个 tag 子组都出现一次(避免漏看)。
    /// - 无 tag 的 Note 进 "未标分类" 子组。
    private func subGroups(for notes: [Note]) -> [(tagName: String, color: Color?, notes: [Note])] {
        let subTagsDef = SubTagsStorage.load()
        let subTagColorByName = Dictionary(uniqueKeysWithValues: subTagsDef.map { ($0.name, $0.color) })

        var byTag: [String: [Note]] = [:]
        var untagged: [Note] = []
        for note in notes {
            if note.otherTags.isEmpty {
                untagged.append(note)
            } else {
                for tag in note.otherTags {
                    byTag[tag, default: []].append(note)
                }
            }
        }
        var result: [(tagName: String, color: Color?, notes: [Note])] = byTag
            .map { (tagName: $0.key, color: subTagColorByName[$0.key], notes: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.tagName < $1.tagName }
        if !untagged.isEmpty {
            result.append((tagName: String(localized: "未标分类", locale: AppLanguageManager.currentLocale),
                           color: nil,
                           notes: untagged.sorted { $0.createdAt > $1.createdAt }))
        }
        return result
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
        if liveNotes.isEmpty && activeSiteGroups.isEmpty {
            emptyHint
        } else {
            List {
                // 无工地的 Note(放在最顶)
                if !orphanNotes.isEmpty {
                    foldableSiteSection(
                        siteTag: String(localized: "未指定工地", locale: AppLanguageManager.currentLocale),
                        notes: orphanNotes
                    )
                }

                // 活跃工地
                ForEach(activeSiteGroups, id: \.siteTag) { group in
                    if !group.notes.isEmpty {
                        foldableSiteSection(siteTag: group.siteTag, notes: group.notes)
                    }
                }

                // 已归档项目段(独立大 section,默认折叠)
                if !archivedSiteGroups.isEmpty {
                    archivedProjectsSection
                }
            }
            .listStyle(.plain)
            .industrialForm()
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    /// 单个工地的可折叠大组,内部按 otherTags 子组。
    private func foldableSiteSection(siteTag: String, notes: [Note]) -> some View {
        let expanded = Binding<Bool>(
            get: { siteExpansion[siteTag] ?? true },
            set: { siteExpansion[siteTag] = $0 }
        )
        let subgroups = subGroups(for: notes)

        return Section {
            if expanded.wrappedValue {
                ForEach(subgroups, id: \.tagName) { sub in
                    subGroupRows(sub: sub)
                }
            }
        } header: {
            siteHeader(siteTag: siteTag, count: notes.count, expanded: expanded)
        }
    }

    /// 子组内的几行 Note rows(默认全部展示,不再折叠 — 一层折叠就够了)。
    @ViewBuilder
    private func subGroupRows(sub: (tagName: String, color: Color?, notes: [Note])) -> some View {
        // 子组小 header
        HStack(spacing: 8) {
            if let c = sub.color {
                Circle().fill(c).frame(width: 8, height: 8)
            }
            Text(sub.tagName)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(Ink.fgDim)
            Spacer()
            Text("\(sub.notes.count)")
                .font(.system(size: 11))
                .foregroundStyle(Ink.dim)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Ink.bg)

        ForEach(sub.notes) { note in
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

    /// 工地大组的可点 header(folding affordance)。
    private func siteHeader(siteTag: String, count: Int, expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                Text(siteTag)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Ink.fg)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Ink.fgDim)
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.dim)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }

    /// 已归档项目段:折叠 + 内部仍按工地大组显示。
    private var archivedProjectsSection: some View {
        Section {
            if archivedSectionExpanded {
                ForEach(archivedSiteGroups, id: \.siteTag) { group in
                    foldableSiteSection(siteTag: group.siteTag, notes: group.notes)
                }
            }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    archivedSectionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.fgDim)
                    Text(String(localized: "已归档项目", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Ink.fgDim)
                    Spacer()
                    Text("\(archivedSiteGroups.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.dim)
                    Image(systemName: archivedSectionExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Ink.dim)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)
                .overlay(alignment: .top) {
                    Rectangle().fill(Ink.line).frame(height: 1)
                        .padding(.horizontal, 24)
                }
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
