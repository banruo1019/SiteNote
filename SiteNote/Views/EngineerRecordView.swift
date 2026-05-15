//
//  EngineerRecordView.swift
//  SiteNote
//
//  Engineer Profile 专属"记"主屏(M1 Linear 极简白)。
//
//  与 PM 的 RecordView 共享内核(HomeViewModel、MIC + CAM hero、AIStatusBar、
//  录音/拍照 staged UI、Undo Toast),但**简化主屏内容**:
//   - 不显示隐患 / 逾期 / 今天到期 / 待分类 / 工种到场 / AI 分类建议 etc.
//   - 只显示一段"最近记录"列表(@Query Note,createdAt desc,前 30 条)。
//   - 没有 stat row,没有 todoFilter,没有 Profile 切换 banner。
//
//  Engineer 的巡检入口在 4 Tab 中的「报告」Tab —— 这里只做「速记 + 浏览最近」。
//
//  保留 MIC 按钮 hero block 必须常驻的架构(DragGesture 节点稳定性),
//  详见 RecordView.swift 顶部注释。
//

import SwiftUI
import SwiftData
import UIKit

struct EngineerRecordView: View {
    @Environment(\.modelContext) private var modelContext

    /// 最近 30 条 Note(activeOnly,createdAt 倒序)。
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.createdAt,
        order: .reverse
    ) private var recentNotes: [Note]

    @State private var viewModel = HomeViewModel()

    @State private var isShowingCamera = false
    @State private var cameraCapturedImage: UIImage?
    @State private var editingStagedIndex: EngineerStagedIndex?

    @State private var navPath = NavigationPath()

    /// 顶部副标题用的天气/位置数据源,复用 PM 主屏的同一 provider。
    @State private var headerProvider = AppHeaderProvider.shared

    private let listVM = NoteListViewModel()

    private var todayDateLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEEE · d MMM"
        return f.string(from: Date())
    }

    /// 最近 30 条 — Engineer 主屏列表显示这一段。
    private var top30Recent: [Note] {
        Array(recentNotes.prefix(30))
    }

    // MARK: - Body

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack(path: $navPath) {
            ZStack(alignment: .bottom) {
                Ink.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    if !viewModel.isRecording && viewModel.stagedPhotos.isEmpty {
                        DiaryConversionBanner()
                    }
                    if viewModel.isRecording {
                        recordingTopArea
                    } else if !viewModel.stagedPhotos.isEmpty {
                        stagedPhotoFocusArea
                    } else {
                        idleTopArea
                    }
                    if viewModel.lastSave == nil {
                        if !viewModel.isRecording {
                            valuePropBar
                        }
                        heroButtons
                            .padding(.bottom, 20)
                    }
                }

                // Engineer 模式无 undo toast —— 保存后立即跳详情,
                // 反悔走详情页"删除"。详见 onChange(viewModel.lastSave) 处理。
            }
            .navigationBarHidden(true)
            .task {
                viewModel.setup(modelContext: modelContext)
                NotificationService.shared.rescheduleAll(notes: recentNotes)
                headerProvider.ensureFresh()
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraPicker(image: $cameraCapturedImage)
                    .ignoresSafeArea()
            }
            .onChange(of: cameraCapturedImage) { _, newImage in
                guard let img = newImage else { return }
                cameraCapturedImage = nil
                editingStagedIndex = EngineerStagedIndex(value: -1, image: img)
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
            .alert(
                String(localized: "出错了", locale: AppLanguageManager.currentLocale),
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 {
                        viewModel.errorMessage = nil
                        viewModel.showsPermissionSettingsButton = false
                    } }
                )
            ) {
                if viewModel.showsPermissionSettingsButton {
                    Button(String(localized: "打开设置", locale: AppLanguageManager.currentLocale)) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                        viewModel.errorMessage = nil
                        viewModel.showsPermissionSettingsButton = false
                    }
                    Button(String(localized: "取消", locale: AppLanguageManager.currentLocale), role: .cancel) {
                        viewModel.errorMessage = nil
                        viewModel.showsPermissionSettingsButton = false
                    }
                } else {
                    Button(String(localized: "知道了", locale: AppLanguageManager.currentLocale)) {
                        viewModel.errorMessage = nil
                    }
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: viewModel.lastSave?.noteID) { _, newID in
                // Engineer 模式:任何 commit(语音/拍照)落库后立刻跳详情。
                // 不显示 undo toast — 这是用户明确要求的工程师工作流(无"存日志/进详情"二选一)。
                guard newID != nil else { return }
                if let note = viewModel.fetchLastSavedNote() {
                    navPath.append(note)
                    viewModel.dismissToastManually()
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.lastSave?.noteID)
        }
    }

    // MARK: - Idle 顶区

    private var idleTopArea: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                AIStatusBar()
                titleBlock
                AIKeyHintBanner()
            }
            recentNotesList
        }
    }

    /// "今天"大标题 + 齿轮(对齐 PM RecordView 视觉风格)。
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "今天", locale: AppLanguageManager.currentLocale))
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
            subtitleRow
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

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

    // MARK: - 最近记录列表

    @ViewBuilder
    private var recentNotesList: some View {
        if top30Recent.isEmpty {
            emptyHint
        } else {
            List {
                Section {
                    ForEach(top30Recent) { note in
                        NavigationLink(value: note) {
                            NoteRow(note: note, urgency: listVM.urgency(for: note))
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Ink.bg)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                softDelete(note)
                            } label: {
                                Label(
                                    String(localized: "删除", locale: AppLanguageManager.currentLocale),
                                    systemImage: "trash"
                                )
                            }
                            .tint(Ink.red)
                        }
                    }
                } header: {
                    HStack {
                        Text(String(localized: "最近记录", locale: AppLanguageManager.currentLocale))
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Ink.fg)
                        Spacer()
                        Text("\(top30Recent.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.dim)
                    }
                    .textCase(nil)
                }
            }
            .listStyle(.plain)
            .industrialForm()
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Ink.line).frame(height: 1)
                .padding(.bottom, 20)
            Text(String(localized: "还没有记录", locale: AppLanguageManager.currentLocale))
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

    private func softDelete(_ note: Note) {
        NotificationService.shared.cancel(for: note)
        note.deletedAt = Date()
    }

    // MARK: - 拍照暂存"专注"模式(复用 PM 视觉)

    @ViewBuilder
    private var stagedPhotoFocusArea: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "刚拍 \(viewModel.stagedPhotos.count) 张", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(Ink.fg)
                Spacer()
                Button {
                    viewModel.clearStagedPhotos()
                } label: {
                    Text(String(localized: "丢弃", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.red)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

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
                            editingStagedIndex = EngineerStagedIndex(value: lastIdx, image: last)
                        }

                    deletePhotoButton {
                        viewModel.removeStagedPhoto(at: lastIdx)
                    }
                    .padding(10)
                }
                .padding(.horizontal, 24)
            }

            if viewModel.stagedPhotos.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(viewModel.stagedPhotos.dropLast().enumerated()), id: \.offset) { idx, image in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    editingStagedIndex = EngineerStagedIndex(value: idx, image: image)
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

            // Engineer:无 AI 分析、无"直接存 vs AI"二选一。
            // 单按钮"完成" → savePhotosOnly + 直接跳详情(由 onChange(lastSave) 兜底)。
            Button {
                viewModel.savePhotosOnly()
            } label: {
                Text(String(localized: "完成", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Ink.fg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

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
        .accessibilityLabel(String(localized: "删除这张照片", locale: AppLanguageManager.currentLocale))
    }

    // MARK: - Recording top area(简化版,无右上"双通道"小字)

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
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)

            AudioWaveformView(level: viewModel.currentAudioLevel)
                .frame(height: 48)
                .padding(.horizontal, 24)
                .padding(.top, 40)

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "转写", locale: AppLanguageManager.currentLocale))
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
                        EngineerBlinkingCursor()
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

    // MARK: - 价值主张 + Hero buttons

    private var valuePropBar: some View {
        HStack(spacing: 4) {
            Text(String(localized: "本周已记", locale: AppLanguageManager.currentLocale))
                .foregroundStyle(Ink.fgDim)
            Text("\(weekNotesCount)")
                .foregroundStyle(Ink.fg)
                .monospacedDigit()
            Text(String(localized: "条 · 可在「报告」Tab 导出 PDF", locale: AppLanguageManager.currentLocale))
                .foregroundStyle(Ink.fgDim)
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    private var weekNotesCount: Int {
        let cal = Calendar.current
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return recentNotes.filter { $0.createdAt >= startOfWeek }.count
    }

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
        .accessibilityLabel(String(localized: "录音", locale: AppLanguageManager.currentLocale))
        .accessibilityHint(String(localized: "长按开始录音,松手保存", locale: AppLanguageManager.currentLocale))
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
            .accessibilityLabel(String(localized: "拍照", locale: AppLanguageManager.currentLocale))
    }

}

// MARK: - Local helpers

/// 录音 partial transcription 光标。RecordView 里的 `BlinkingCursor` 是 fileprivate,
/// 这里复刻一份,避免跨文件 access 改动。
private struct EngineerBlinkingCursor: View {
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

private struct EngineerStagedIndex: Identifiable {
    let id: UUID = UUID()
    let value: Int
    let image: UIImage
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, ShareLog.self, configurations: config)
    return EngineerRecordView().modelContainer(container)
}
