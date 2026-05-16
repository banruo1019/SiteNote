//
//  NoteDetailView.swift
//  SiteNote
//
//  速记详情页。
//
//  布局(自顶向下):
//  1. titleBlock         — 大字转写内容(可编辑)+ AI 助手菜单入口
//  2. tagsRow            — 一排 chip:隐患 · 工地 · 分类 · 已处理 · 条款 · 指派 · 平面图
//  3. photosBlock        — 主图 240pt 大图 + 其余水平缩略图
//  4. addPhotoRow        — 全宽"加照片"虚线按钮
//  5. datesRow           — 创建时间 | 到期时间 两等分
//  6. audioDisclosure    — 录音(折叠)
//  7. floorPlanDisclosure— 平面图位置(折叠)
//  8. otherMetaDisclosure— 位置/天气/上次分享(折叠)
//  9. actionButtonGroup  — 处理/改期/分享/指派/隐患/删除(Engineer 视角下隐藏 PM 专属按钮)
//
//  本文件只保留主 body + 各 section computed vars。
//  AI 操作 → NoteDetailView+AI.swift
//  Actions & helpers → NoteDetailView+Actions.swift
//  TagPickerSheet / NewSubTagSheet / Supporting types → NoteDetailSheets.swift
//  FullscreenPhotoView → Components/FullscreenPhotoView.swift
//

import SwiftUI
import SwiftData
import UIKit
import PhotosUI

struct NoteDetailView: View {
    @Bindable var note: Note
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    /// Engineer 视角下隐藏所有 PM 专属的操作按钮 + 分类建议卡 + AI 照片分析,
    /// 详情页退化为纯查看 / 编辑 transcription / 编辑工地标签 / 标注照片。
    @State private var profileManager = UserProfileManager.shared
    var isEngineerProfile: Bool { profileManager.current == .engineer }

    /// 是否日志模式:决定哪些 section 显示 / 隐藏 + 标题样式。
    private var isDiary: Bool { note.isDiaryRecord }

    @State var sharePDFURL: URL?
    @State var isGeneratingShare: Bool = false
    @State var obsidianMessage: String?
    @State private var showsRescheduleDialog: Bool = false
    @State var fullscreenPhoto: FullscreenPhoto?
    @State var showsOriginalTranscription: Bool = false
    @State var isShowingFloorPlanMark: Bool = false
    @State var editingDetailPhoto: DetailPhotoEdit?
    /// 标注保存/加载失败时的提示文案。非 nil = 显示 alert。
    @State private var photoAnnotationError: String?
    @State var galleryRefreshID: UUID = UUID()
    @State private var showsContactPicker: Bool = false
    @State private var pendingAssignee: PendingAssignee?
    @State private var assignError: String?

    // 加照片相关
    @State var showsPhotoSourceDialog: Bool = false
    @State private var showsCamera: Bool = false
    @State private var capturedImage: UIImage?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsLibraryPicker: Bool = false

    // AI 相关
    @State var aiWorking: Bool = false
    @State var aiError: String?
    @State var polishPreview: PolishPreview?
    @State var photoAnalyses: PhotoAnalysesSheet?
    /// E1.2:当前正在跑的 AI Task 句柄。取消按钮 → task?.cancel()。
    /// 可能是 polish / photo analysis 中的任一种。
    @State var currentAITask: Task<Void, Never>?

    // 标签选择
    @State var showsTagPicker: Bool = false

    // 删除确认
    @State private var showsDeleteConfirm: Bool = false
    @State private var showsConvertConfirm: Bool = false

    var body: some View {
        // 防御性 guard:note 已被硬删 / 已脱离 context 时立即 dismiss,
        // 不能再读它的任何属性(包括 photoPaths/transcription),否则 SwiftData 抛
        // "backing data was detached from a context without resolving attribute faults" → 崩溃。
        // 触发场景:用户在详情页停留时,从别处(垃圾桶清空、清空所有数据、AI 转换链等)
        // 把这条 note 删掉了或它的 ModelContext 失效了。
        if note.isDeleted || note.modelContext == nil {
            Color.clear
                .task { dismiss() }
        } else {
            mainBody
        }
    }

    /// 主体 ScrollView。只在 note 仍然有效时才会被 evaluate;所有读 note 属性的 sheet/overlay 都挂这里。
    @ViewBuilder
    private var mainBody: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.medium) {
                titleBlock            // 1. 标题(diary 模式带"施工日记" badge)
                if !isEngineerProfile {
                    NoteClassificationCard(note: note) // 1.4 AI 分类建议(diary 已自动裁剪只剩 site+subTags)
                }
                tagsRow               // 1.5 工地 + 分类
                photosBlock           // 3. 照片
                addPhotoRow           // 4. 加照片
                if !isDiary && !isEngineerProfile {
                    datesRow          // 5. 到期时间(Engineer / 日志 都不显示——没有 deadline 概念)
                }
                audioDisclosure       // 6. 录音
                if !isDiary {
                    floorPlanDisclosure   // 7. 平面图(只普通 note,日志不需要;Engineer 保留——核心功能)
                }
                otherMetaDisclosure   // 9. 位置/天气/分享(两种都有)
                actionButtonGroup     // 10. 操作按钮(diary 只显示 删除)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle(isDiary ? "日志" : "详情")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // 用户离开详情页 = 可能刚改过 transcription / siteTag / otherTags / 模板等。
            // 让语义搜索 cache 失效,下次搜索时按新内容重算 embedding。
            // **note 已脱离 context 时 skip**——读 note.id 也可能崩。
            guard !note.isDeleted, note.modelContext != nil else { return }
            SemanticSearchService.shared.invalidate(noteID: note.id)
        }
        .overlay {
            if aiWorking {
                aiLoadingOverlay
            }
        }
        .sheet(item: Binding(
            get: { sharePDFURL.map { SharePDFItem(url: $0) } },
            set: { _ in sharePDFURL = nil }
        )) { item in
            ShareSheet(items: [item.url]) {
                note.lastSharedAt = Date()
            }
        }
        .sheet(isPresented: $isShowingFloorPlanMark) {
            FloorPlanMarkView(
                preferredSiteTag: note.siteTag,
                pinColor: pinColorForThisNote
            ) { result in
                note.floorPlanRef = result.planName
                note.floorPlanX = result.x
                note.floorPlanY = result.y
            }
        }
        .sheet(item: $fullscreenPhoto) { photo in
            FullscreenPhotoView(
                image: photo.image,
                onAnnotate: photo.path.map { path in
                    { editingDetailPhoto = DetailPhotoEdit(path: path, image: photo.image) }
                }
            )
        }
        .sheet(item: $editingDetailPhoto) { edit in
            PhotoEditorView(originalImage: edit.image) { newImage in
                if writeEditedPhoto(newImage, toPath: edit.path) {
                    galleryRefreshID = UUID()
                } else {
                    photoAnnotationError = String(
                        localized: "标注保存失败,原图保留",
                        locale: AppLanguageManager.currentLocale
                    )
                }
            }
        }
        .sheet(isPresented: $showsContactPicker) {
            ContactPicker { name, phone in
                if let phone {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        pendingAssignee = PendingAssignee(name: name, phone: phone)
                    }
                } else {
                    assignError = String(localized: "该联系人没有电话号码", locale: AppLanguageManager.currentLocale)
                }
            }
        }
        .sheet(item: $pendingAssignee) { assignee in
            MessageComposer(
                recipient: assignee.phone,
                body: buildAssignMessage(),
                attachmentImages: loadNotePhotosForAssignment()
            ) { sent in
                if sent {
                    note.assignedTo = assignee.name
                    note.lastSharedAt = Date()
                }
            }
        }
        .sheet(item: $polishPreview) { preview in
            polishPreviewSheet(preview)
        }
        .sheet(item: $photoAnalyses) { sheet in
            photoAnalysesSheet(sheet)
        }
        .sheet(isPresented: $showsOriginalTranscription) {
            originalTranscriptionSheet
        }
        .sheet(isPresented: $showsTagPicker) {
            TagPickerSheet(
                currentSiteTag: note.siteTag,
                currentOtherTags: note.otherTags,
                onSiteChange: { newTag in
                    note.siteTag = newTag
                    // 喂给 Phase A 学习:用户手动确定工地,把当前坐标记进中心点。
                    if let tag = newTag,
                       let lat = note.latitude, let lng = note.longitude {
                        SiteCentroidsStorage.observe(siteName: tag, latitude: lat, longitude: lng)
                    }
                },
                onOtherTagsChange: { note.otherTags = $0 }
            )
        }
        .confirmationDialog(
            "改期到什么时候?",
            isPresented: $showsRescheduleDialog,
            titleVisibility: .visible
        ) {
            Button("今天") { reschedule(to: .today) }
            Button("3 天内") { reschedule(to: .threeDays) }
            Button("本周内") { reschedule(to: .thisWeek) }
            Button("归档 (不再提醒)") { reschedule(to: .archive) }
            Button("取消", role: .cancel) {}
        }
        .alert(
            "删除这条速记?",
            isPresented: $showsDeleteConfirm
        ) {
            Button("删除", role: .destructive) { softDeleteNote() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会放到垃圾桶,之后可以在「设置 → 数据与关于 → 垃圾桶」恢复或永久删除。")
        }
        .alert(
            isDiary ? "转为普通记录?" : "转为施工日志?",
            isPresented: $showsConvertConfirm
        ) {
            Button(isDiary ? "转为记录" : "转为日志") { performModeConvert() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(isDiary
                 ? "到期会改为「待分类」。"
                 : "会归档为只记录(不推送提醒)。")
        }
        .alert("加照片", isPresented: $showsPhotoSourceDialog) {
            Button("📸 拍照") { showsCamera = true }
            Button("🖼 从相册选") { showsLibraryPicker = true }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showsCamera) {
            CameraPicker(image: $capturedImage)
                .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showsLibraryPicker,
            selection: $pickerItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: capturedImage) { _, newImage in
            if let img = newImage {
                appendPhoto(img)
                capturedImage = nil
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var loaded: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        loaded.append(img)
                    }
                }
                await MainActor.run {
                    for img in loaded { appendPhoto(img) }
                    pickerItems = []
                }
            }
        }
        .alert("无法指派", isPresented: Binding(
            get: { assignError != nil },
            set: { if !$0 { assignError = nil } }
        )) {
            Button("知道了") { assignError = nil }
        } message: {
            Text(assignError ?? "")
        }
        .alert("AI 出错", isPresented: Binding(
            get: { aiError != nil },
            set: { if !$0 { aiError = nil } }
        )) {
            Button("知道了") { aiError = nil }
        } message: {
            Text(aiError ?? "")
        }
        .alert("标注提示", isPresented: Binding(
            get: { photoAnnotationError != nil },
            set: { if !$0 { photoAnnotationError = nil } }
        )) {
            Button("知道了") { photoAnnotationError = nil }
        } message: {
            Text(photoAnnotationError ?? "")
        }
    }

    // MARK: - 1. 标题块(转写正文大字 + AI 助手)

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack {
                if isDiary {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("施工日志")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.5)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(Ink.accentBlue)
                } else {
                    Text("内容")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if hasOriginalDivergence {
                    Button {
                        showsOriginalTranscription = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "text.quote")
                            Text("查看原文")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                    }
                }
                if !isEngineerProfile {
                    aiMenu
                }
            }

            TextField("(空内容)", text: $note.transcription, axis: .vertical)
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(2...)
                .padding(DesignTokens.Spacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Ink.card2)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }


    /// 这条 note 的图钉颜色。和 FloorPlanLookupView 的 pinColor 逻辑一致。
    var pinColorForThisNote: Color {
        if note.isDone { return .gray }
        if note.isHazard { return .red }
        if let firstSub = note.otherTags.first {
            return SubTagsStorage.color(name: firstSub)
        }
        return .red
    }

    // MARK: - 3. 照片大图

    // photosBlock / photoLayout / bigPhoto / addPhotoRow → NoteDetailView+Photos.swift

    // MARK: - 5. 创建 + 到期 日期并排



    @ViewBuilder
    private var aiMenu: some View {
        let available = AIService.isLanguageModelAvailable
        Menu {
            Button {
                runAIPolish()
            } label: {
                Label("润色转写", systemImage: "text.badge.checkmark")
            }
            .disabled(!available || note.transcription.isEmpty)

            // Engineer 视角下不提供 AI 照片分析(任务 3:Engineer 不调照片 AI)。
            if !isEngineerProfile {
                Button {
                    runPhotoAnalysis()
                } label: {
                    Label("分析照片", systemImage: "photo.badge.checkmark")
                }
                .disabled(!available || note.photoPaths.isEmpty)
            }

            if !available {
                Divider()
                Text("请先在设置 → 录入与 AI 配置引擎")
                    .font(.system(size: 12))
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("AI 助手")
            }
            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
            .foregroundStyle(available ? Ink.fg : Ink.fgDim)
        }
    }

    // (transcriptionBlock 已合并入 titleBlock)

    private var hasOriginalDivergence: Bool {
        !note.transcriptionOriginal.isEmpty
            && note.transcriptionOriginal != note.transcription
    }

    private var originalTranscriptionSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                    Text("⚠️ 这是语音识别的原始文本,作为法律证据永不修改。当前显示的内容可能被 AI 修复或你手动编辑过。")
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(.secondary)
                        .padding(DesignTokens.Spacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Ink.card)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text(note.transcriptionOriginal.isEmpty ? String(localized: "(无原始文本)", locale: AppLanguageManager.currentLocale) : note.transcriptionOriginal)
                        .font(.system(size: DesignTokens.FontSize.large))
                        .textSelection(.enabled)
                        .padding(DesignTokens.Spacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Ink.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("原文")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { showsOriginalTranscription = false }
                }
            }
        }
    }

    // (photoGallery 和 addPhotoTile 已合并入 photosBlock + addPhotoRow)

    // photoThumbnail → NoteDetailView+Photos.swift



    // MARK: - 6. 操作按钮

    /// 操作区:三排双等分按钮,颜色/分量统一。
    /// - 第 1 排:已处理 + 改期(常用主操作,填充色)
    /// - 第 2 排:分享 + 指派(中性 tonal)
    /// - 第 3 排:标记隐患 + 删除(描边 ghost,警示/危险)
    ///
    /// Engineer 视角下:隐藏 完成 / 改期 / 指派 / 标隐患 这些 todo 性质的按钮,
    /// 只保留 分享 + 删除 + 转换模式 + Obsidian 导出。详情页定位为"查看/编辑"。
    @ViewBuilder
    private var actionButtonGroup: some View {
        if isDiary || isEngineerProfile {
            // 日志 / Engineer:都不需要 todo 类的(完成/改期/指派/标隐患)按钮。
            // Engineer 也不要"转为施工日志" / Obsidian 导出 —— 工程师工作流以 InspectionReport 为出口。
            VStack(spacing: DesignTokens.Spacing.small) {
                HStack(spacing: DesignTokens.Spacing.small) {
                    tonalActionButton(
                        icon: isGeneratingShare ? "hourglass" : "square.and.arrow.up",
                        title: isGeneratingShare ? "生成中…" : "分享",
                        tint: Ink.fg,
                        bg: Ink.card
                    ) { generateSharePDF() }

                    ghostActionButton(
                        icon: "trash",
                        title: "删除",
                        tint: Ink.red
                    ) { showsDeleteConfirm = true }
                }
                if !isEngineerProfile {
                    convertModeButton
                }
            }
        } else {
            VStack(spacing: DesignTokens.Spacing.small) {
                HStack(spacing: DesignTokens.Spacing.small) {
                    doneButton
                    rescheduleButton
                }
                HStack(spacing: DesignTokens.Spacing.small) {
                    tonalActionButton(
                        icon: isGeneratingShare ? "hourglass" : "square.and.arrow.up",
                        title: isGeneratingShare ? "生成中…" : "分享",
                        tint: Ink.fg,
                        bg: Ink.card
                    ) { generateSharePDF() }

                    tonalActionButton(
                        icon: note.assignedTo == nil ? "person.fill.badge.plus" : "person.fill",
                        title: note.assignedTo == nil ? "指派" : "重派",
                        tint: Ink.fg,
                        bg: Ink.card
                    ) {
                        if MessageComposer.canSendMessages {
                            showsContactPicker = true
                        } else {
                            assignError = String(localized: "当前设备不支持发送短信(可能是 iPad 或模拟器)", locale: AppLanguageManager.currentLocale)
                        }
                    }
                }
                HStack(spacing: DesignTokens.Spacing.small) {
                    ghostActionButton(
                        icon: note.isHazard ? "exclamationmark.triangle.fill" : "exclamationmark.triangle",
                        title: note.isHazard ? "取消隐患" : "标记隐患",
                        tint: Ink.amber
                    ) {
                        note.isHazard.toggle()
                        NotificationService.shared.schedule(for: note)
                    }

                    ghostActionButton(
                        icon: "trash",
                        title: "删除",
                        tint: Ink.red
                    ) { showsDeleteConfirm = true }
                }
                convertModeButton
            }
        }
    }

    /// 记录 ↔ 施工日志 切换(录错模式时修正)。
    private var convertModeButton: some View {
        VStack(spacing: DesignTokens.Spacing.small) {
            Button {
                showsConvertConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(isDiary ? "转为普通记录" : "转为施工日志")
                }
                .font(.system(size: DesignTokens.FontSize.body, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            obsidianExportButton
        }
    }

    /// 一键导出当前 note 到 Obsidian vault（需先在设置里配置文件夹）。
    private var obsidianExportButton: some View {
        Button {
            exportThisNoteToObsidian()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up.on.square")
                Text("导出到 Obsidian")
            }
            .font(.system(size: DesignTokens.FontSize.body, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .alert("Obsidian 导出", isPresented: Binding(
            get: { obsidianMessage != nil },
            set: { if !$0 { obsidianMessage = nil } }
        )) {
            Button("知道了") { obsidianMessage = nil }
        } message: {
            Text(obsidianMessage ?? "")
        }
    }

    private func exportThisNoteToObsidian() {
        do {
            try ObsidianExportService.exportSingleNote(note)
            obsidianMessage = "✓ 已导出。Mac 上的 vault 几秒后通过 iCloud 同步可见。"
        } catch {
            obsidianMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 执行模式切换。diary↔note:切 deadline + 重排推送。
    private func performModeConvert() {
        if isDiary {
            note.isDiaryRecord = false
            note.deadline = .inbox  // 回到待分类,让用户重选到期
            note.dueDate = Deadline.inbox.dueDate(from: note.createdAt)
        } else {
            // 记录 → 日志:归档不推送。
            note.isDiaryRecord = true
            note.deadline = .archive
            note.dueDate = Deadline.archive.dueDate(from: note.createdAt)
        }
        // 触发重排:isDiaryRecord 变了之后,schedule 会自动决定排或不排(guard 把日志短路)。
        NotificationService.shared.schedule(for: note)
    }

    private var doneButton: some View {
        Button {
            note.isDone.toggle()
            if note.isDone {
                NotificationService.shared.cancel(for: note)
            } else {
                NotificationService.shared.schedule(for: note)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: note.isDone ? "arrow.uturn.left.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text(note.isDone ? "未完成" : "已处理")
                    .font(.system(size: DesignTokens.FontSize.body, weight: .bold))
            }
            .foregroundStyle(Ink.bg)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(note.isDone ? Ink.dim : Ink.green)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: note.isDone)
    }

    private var rescheduleButton: some View {
        Button {
            showsRescheduleDialog = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 18, weight: .semibold))
                Text("改期")
                    .font(.system(size: DesignTokens.FontSize.body, weight: .bold))
            }
            .foregroundStyle(Ink.bg)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Ink.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// Tonal 次级按钮:纯灰调,不抢主色。
    private func tonalActionButton(
        icon: String,
        title: LocalizedStringKey,
        tint: Color,
        bg: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Ink.line, lineWidth: 1)
            )
        }
    }

    /// Ghost 三级按钮:描边样式。
    private func ghostActionButton(
        icon: String,
        title: LocalizedStringKey,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(tint.opacity(0.5), lineWidth: 1)
            )
        }
    }
}
