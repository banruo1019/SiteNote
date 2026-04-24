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

    /// 天气 + 位置数据源(@Observable,属性变化会驱动 body 刷新)
    @State private var headerProvider = AppHeaderProvider.shared

    private let listVM = NoteListViewModel()

    enum TodoFilter: Hashable {
        case all, overdue, today, inbox, hazard
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

    private var todayDateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
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
                        if !viewModel.isRecording {
                            valuePropBar
                        }
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
                _ = await VoiceCaptureService.requestPermissions()
                _ = await NotificationService.shared.requestAuthorization()
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
            .alert("出错了", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("知道了") { viewModel.errorMessage = nil }
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
                TodayBriefButton()
                NavigationLink(value: SettingsDestination()) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Ink.fgDim)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
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

    /// 4 档 stat 切换:逾期 / 今天 / 待分类 / 隐患。点击某个就筛到那类,再点还原。
    /// 选中态:数字放大 + 色块底 + label 加粗。
    private var statsRow: some View {
        HStack(spacing: 6) {
            statCell(
                filter: .overdue,
                count: overdueNotes.count,
                label: "逾期",
                color: Ink.red
            )
            statCell(
                filter: .today,
                count: todayNotes.count,
                label: "今天",
                color: Ink.fg
            )
            statCell(
                filter: .inbox,
                count: inboxNotes.count,
                label: "待分类",
                color: Ink.fgDim
            )
            statCell(
                filter: .hazard,
                count: hazardNotes.count,
                label: "隐患",
                color: Ink.red,
                icon: "exclamationmark.triangle.fill"
            )
        }
        .padding(.horizontal, 24)   // 对齐标题 / subtitle / 列表的 24pt 左右边距
        .padding(.bottom, 10)
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
    @ViewBuilder
    private var todoListArea: some View {
        if overdueNotes.isEmpty && todayNotes.isEmpty
            && inboxNotes.isEmpty && hazardNotes.isEmpty {
            emptyHint
        } else {
            List {
                if showSection(.hazard), !hazardNotes.isEmpty {
                    foldableTodoSection(
                        title: "隐患",
                        color: Ink.red,
                        notes: hazardNotes,
                        expanded: $hazardExpanded
                    )
                }
                if showSection(.overdue), !overdueNotes.isEmpty {
                    foldableTodoSection(
                        title: "逾期",
                        color: Ink.red,
                        notes: overdueNotes,
                        expanded: $overdueExpanded
                    )
                }
                if showSection(.today), !todayNotes.isEmpty {
                    foldableTodoSection(
                        title: "今天到期",
                        color: Ink.fg,
                        notes: todayNotes,
                        expanded: $todayExpanded
                    )
                }
                if showSection(.inbox), !inboxNotes.isEmpty {
                    foldableTodoSection(
                        title: "待分类",
                        color: Ink.fgDim,
                        notes: inboxNotes,
                        expanded: $inboxExpanded
                    )
                }
            }
            .listStyle(.plain)
            .industrialForm()
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    /// 当前过滤下该 section 是否显示。
    private func showSection(_ filter: TodoFilter) -> Bool {
        todoFilter == .all || todoFilter == filter
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
                    Text(recordingDurationLabel)
                        .font(.system(size: 40, weight: .medium))
                        .tracking(-1.2)
                        .foregroundStyle(Ink.fg)
                        .monospacedDigit()
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

    private var recordingDurationLabel: String {
        // 简化:显示音量估算的计时(真实秒数的 API 可以后续接)
        return "●:●●"
    }

    // MARK: - 首屏价值主张

    /// mic 上方一行小字。本周动态 N + 可导 3 份 PDF(对应当前 PDFHubView 的 3 入口:巡检日志/本周报告/EOT)。
    private var valuePropBar: some View {
        HStack(spacing: 4) {
            Text("本周已记")
                .foregroundStyle(Ink.fgDim)
            Text("\(weekNotesCount)")
                .foregroundStyle(Ink.fg)
                .monospacedDigit()
            Text("条 · 可导 3 份 PDF 报告")
                .foregroundStyle(Ink.fgDim)
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    private var weekNotesCount: Int {
        let cal = Calendar.current
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return allNotes.filter { $0.createdAt >= startOfWeek }.count
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
    }

    // MARK: - Undo toast

    private var undoToastOverlay: some View {
        UndoToast(
            message: viewModel.lastSave?.summary ?? "",
            secondsRemaining: viewModel.undoSecondsRemaining,
            onMarkHazard: { viewModel.markLastSaveAsHazard() },
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
                viewModel.errorMessage = (error as? LocalizedError)?.errorDescription ?? "AI 分析失败"
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
