//
//  NoteDetailView.swift
//  SiteNote
//
//  速记详情页。
//
//  布局(自顶向下):
//  1. titleBlock         — 大字转写内容(可编辑)+ AI 助手菜单入口
//  2. tagsRow            — 一排 chip:隐患 · 工地 · 子标签 · 已处理 · 模板 · 条款 · 指派 · 平面图
//  3. photosBlock        — 主图 240pt 大图 + 其余水平缩略图
//  4. addPhotoRow        — 全宽"加照片"虚线按钮
//  5. datesRow           — 创建时间 | 到期时间 两等分
//  6. audioDisclosure    — 录音(折叠)
//  7. floorPlanDisclosure— 平面图位置(折叠)
//  8. templateSection    — 巡检模板(若有)
//  9. otherMetaDisclosure— 位置/天气/上次分享(折叠)
//  10. actionButtonGroup — 处理/改期/分享/指派/隐患/删除
//

import SwiftUI
import SwiftData
import UIKit
import PhotosUI

struct NoteDetailView: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 关联的 LogEntry(用于 diary 模式的"类型"行)。
    @Query private var logEntries: [LogEntry]

    init(note: Note) {
        self.note = note
        let id = note.id
        _logEntries = Query(
            filter: #Predicate<LogEntry> {
                $0.sourceNoteID == id && $0.deletedAt == nil
            },
            sort: [SortDescriptor(\LogEntry.createdAt)]
        )
    }

    /// 是否日志模式:决定哪些 section 显示 / 隐藏 + 标题样式。
    private var isDiary: Bool { note.isDiaryRecord }

    /// diary 模式专属:已识别的类型 chip(派生自 LogEntries)。
    @ViewBuilder
    private var typeRow: some View {
        let kindOrder: [LogKind] = [.person, .plant, .delivery, .visitor, .event]
        let presentKinds = kindOrder.filter { k in logEntries.contains(where: { $0.kind == k }) }
        if !presentKinds.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
                Text("类型")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Ink.dim)
                ForEach(presentKinds, id: \.self) { k in
                    HStack(spacing: 3) {
                        Text(typeIcon(for: k))
                        Text(k.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Ink.fg)
                        Text("\(logEntries.filter { $0.kind == k }.count)")
                            .font(.system(size: 10))
                            .foregroundStyle(Ink.fgDim)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Ink.card, in: Capsule())
                }
                Spacer()
            }
        }
    }

    private func typeIcon(for k: LogKind) -> String {
        switch k {
        case .person: return "👥"
        case .plant: return "🚜"
        case .delivery: return "📦"
        case .visitor: return "🧑"
        case .event: return "⚠️"
        }
    }

    @State private var sharePDFURL: URL?
    @State private var isGeneratingShare: Bool = false
    @State private var showsRescheduleDialog: Bool = false
    @State private var fullscreenPhoto: FullscreenPhoto?
    @State private var showsOriginalTranscription: Bool = false
    @State private var isShowingFloorPlanMark: Bool = false
    @State private var editingDetailPhoto: DetailPhotoEdit?
    @State private var galleryRefreshID: UUID = UUID()
    @State private var showsContactPicker: Bool = false
    @State private var pendingAssignee: PendingAssignee?
    @State private var assignError: String?

    // 加照片相关
    @State private var showsPhotoSourceDialog: Bool = false
    @State private var showsCamera: Bool = false
    @State private var capturedImage: UIImage?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsLibraryPicker: Bool = false

    // AI 相关
    @State private var aiWorking: Bool = false
    @State private var aiError: String?
    @State private var polishPreview: PolishPreview?
    @State private var photoAnalyses: PhotoAnalysesSheet?

    // 标签选择
    @State private var showsTagPicker: Bool = false

    // 删除确认
    @State private var showsDeleteConfirm: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.medium) {
                titleBlock            // 1. 标题(diary 模式带"施工日记" badge)
                NoteClassificationCard(note: note) // 1.4 AI 分类建议(diary 已自动裁剪只剩 site+subTags)
                tagsRow               // 1.5 工地 + 子标签
                if isDiary && !logEntries.isEmpty {
                    typeRow           // 1.6 diary 专属:已识别的类型 chip(👥 人员 · 🚜 机械)
                }
                LogEntryChipSection(note: note)    // 2. AI 识别的结构化条目
                photosBlock           // 3. 照片
                addPhotoRow           // 4. 加照片
                if !isDiary {
                    datesRow          // 5. 截止时间(只普通 note)
                }
                audioDisclosure       // 6. 录音
                if !isDiary {
                    floorPlanDisclosure   // 7. 平面图(只普通 note,日志不需要)
                }
                if !isDiary, note.templateName != nil {
                    templateSection   // 8. 巡检模板(只普通 note)
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
            FullscreenPhotoView(image: photo.image)
        }
        .sheet(item: $editingDetailPhoto) { edit in
            PhotoEditorView(originalImage: edit.image) { newImage in
                writeEditedPhoto(newImage, toPath: edit.path)
                galleryRefreshID = UUID()
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
                    assignError = "该联系人没有电话号码"
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
                    // 同步到关联的 LogEntry(避免 DiaryView 工地过滤漏计)。
                    if let ctx = note.modelContext {
                        let noteID = note.id
                        let desc = FetchDescriptor<LogEntry>(
                            predicate: #Predicate<LogEntry> { $0.sourceNoteID == noteID }
                        )
                        let entries = (try? ctx.fetch(desc)) ?? []
                        for e in entries where e.siteTag != newTag {
                            e.siteTag = newTag
                        }
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
    }

    // MARK: - 1. 标题块(转写正文大字 + AI 助手)

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack {
                if isDiary {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("施工日记")
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
                aiMenu
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

    // MARK: - 2. 标签一排(工地 + 子标签 + 状态 + 模板 + 条款 + 指派 + 平面图 ref)

    private var tagsRow: some View {
        let chips = contextChips
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips) { c in
                    chipView(c)
                }
            }
        }
    }

    private var contextChips: [ContextChip] {
        var list: [ContextChip] = []
        // 颜色收敛:只有 隐患=红、子标签=各自颜色、工地=accent 是"强信号",
        // 其他辅助信息(已处理/模板/条款/指派/平面图)统一用 Ink.fgDim 灰调,
        // 避免满屏彩虹 chip 喧宾夺主。
        if note.isHazard {
            list.append(ContextChip(
                icon: "exclamationmark.triangle.fill",
                text: "隐患",
                color: Ink.red,
                kind: .hazard
            ))
        }
        let siteName = note.siteTag
        list.append(ContextChip(
            icon: siteName == nil ? "building.2" : "building.2.fill",
            text: siteName ?? "未命名工地",
            color: siteName == nil ? Ink.fgDim : Ink.accent,
            kind: .tag
        ))
        for tag in note.otherTags {
            let color = SubTagsStorage.color(name: tag)
            list.append(ContextChip(
                icon: "tag.fill",
                text: tag,
                color: color,
                kind: .tag
            ))
        }
        if note.isDone {
            list.append(ContextChip(
                icon: "checkmark.circle.fill",
                text: "已处理",
                color: Ink.green,
                kind: .other
            ))
        }
        if let template = note.templateName {
            list.append(ContextChip(
                icon: "checklist",
                text: template,
                color: Ink.fgDim,
                kind: .other
            ))
        }
        if let clause = note.contractClauseRef {
            list.append(ContextChip(
                icon: "doc.text",
                text: clause,
                color: Ink.fgDim,
                kind: .other
            ))
        }
        if let assignee = note.assignedTo {
            list.append(ContextChip(
                icon: "person.fill",
                text: assignee,
                color: Ink.fgDim,
                kind: .other
            ))
        }
        if let ref = note.floorPlanRef {
            list.append(ContextChip(
                icon: "map.fill",
                text: ref,
                color: Ink.fgDim,
                kind: .other
            ))
        }
        return list
    }

    @ViewBuilder
    private func chipView(_ c: ContextChip) -> some View {
        let body = HStack(spacing: 4) {
            Image(systemName: c.icon).font(.system(size: 11))
            Text(c.text).font(.system(size: 13, weight: .semibold))
            if c.kind == .tag {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(c.color)
        .background(c.color.opacity(0.15))
        .clipShape(Capsule())

        if c.kind == .tag {
            Button {
                showsTagPicker = true
            } label: {
                body
            }
        } else {
            body
        }
    }

    private var deadlinePill: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 12))
            Text(deadlineDisplay)
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
        }
        .foregroundStyle(deadlineColor)
    }

    private var deadlineColor: Color {
        if note.deadline == .archive { return .gray }
        if note.isDone { return .gray }
        if note.dueDate < Date() { return .red }
        if Calendar.current.isDateInToday(note.dueDate) { return Ink.red }
        return .primary
    }

    /// 这条 note 的图钉颜色。和 FloorPlanLookupView 的 pinColor 逻辑一致。
    private var pinColorForThisNote: Color {
        if note.isDone { return .gray }
        if note.isHazard { return .red }
        if let firstSub = note.otherTags.first {
            return SubTagsStorage.color(name: firstSub)
        }
        return .red
    }

    // MARK: - 3. 照片大图

    @ViewBuilder
    private var photosBlock: some View {
        if !note.photoPaths.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                HStack {
                    Text("照片")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(note.photoPaths.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                photoLayout
                    .id(galleryRefreshID)
            }
        }
    }

    /// 第一张大图占满宽度,其余小图水平滚动。单张就只有大图。
    @ViewBuilder
    private var photoLayout: some View {
        if let firstPath = note.photoPaths.first,
           let url = PhotoStorage.absoluteURL(forRelative: firstPath),
           let firstImage = UIImage(contentsOfFile: url.path) {
            VStack(spacing: DesignTokens.Spacing.small) {
                bigPhoto(path: firstPath, image: firstImage)

                if note.photoPaths.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DesignTokens.Spacing.small) {
                            ForEach(note.photoPaths.dropFirst(), id: \.self) { path in
                                photoThumbnail(for: path)
                            }
                        }
                    }
                }
            }
        }
    }

    private func bigPhoto(path: String, image: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            // 外层 RoundedRectangle 托底,图片作为 overlay。
            // contentShape 明确把可点区域锁在矩形内,避免 .scaledToFill 的原图溢出带来的幽灵点击
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.08))
                .frame(height: 240)
                .overlay(
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .clipped()
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .onTapGesture {
                    fullscreenPhoto = FullscreenPhoto(image: image)
                }

            Button {
                editingDetailPhoto = DetailPhotoEdit(path: path, image: image)
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, Color.black.opacity(0.6))
                    .padding(8)
            }
            .accessibilityLabel("标注此照片")
        }
    }

    // MARK: - 4. 加照片按钮(独立一行)

    private var addPhotoRow: some View {
        Button {
            showsPhotoSourceDialog = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                Text("加照片")
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                Spacer()
                Image(systemName: "camera.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.accentColor)
            .padding(DesignTokens.Spacing.medium)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 5. 创建 + 到期 日期并排

    private var datesRow: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            dateCell(
                icon: "clock",
                label: "创建",
                value: note.createdAt.formatted(date: .abbreviated, time: .shortened),
                tint: .secondary
            )
            dateCell(
                icon: "calendar",
                label: "到期",
                value: deadlineDisplay,
                tint: deadlineColor
            )
        }
    }

    private func dateCell(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Ink.card2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 6. 录音(折叠)

    @ViewBuilder
    private var audioDisclosure: some View {
        if let audioPath = note.audioFilePath {
            DisclosureGroup {
                AudioPlayerView(audioRelativePath: audioPath)
                    .padding(.top, DesignTokens.Spacing.small)
            } label: {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(.blue)
                    Text("录音")
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                }
            }
            .padding(DesignTokens.Spacing.medium)
            .background(Ink.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

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

            Button {
                runPhotoAnalysis()
            } label: {
                Label("分析照片", systemImage: "photo.badge.checkmark")
            }
            .disabled(!available || note.photoPaths.isEmpty)

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

                    Text(note.transcriptionOriginal.isEmpty ? "(无原始文本)" : note.transcriptionOriginal)
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

    @ViewBuilder
    private func photoThumbnail(for path: String) -> some View {
        if let url = PhotoStorage.absoluteURL(forRelative: path),
           let image = UIImage(contentsOfFile: url.path) {
            ZStack(alignment: .topTrailing) {
                // 用固定 frame 的容器 + overlay 图片,命中区限在 120×120 矩形内
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.08))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipped()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        fullscreenPhoto = FullscreenPhoto(image: image)
                    }
                Button {
                    editingDetailPhoto = DetailPhotoEdit(path: path, image: image)
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, Color.black.opacity(0.6))
                        .padding(4)
                }
                .accessibilityLabel("标注此照片")
            }
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 120, height: 120)
                .overlay(Image(systemName: "photo").font(.title))
        }
    }

    // MARK: - 3. 模板检查清单

    private var templateSection: some View {
        let templateItems = InspectionTemplatesStorage.load()
            .first(where: { $0.name == note.templateName })?.items ?? []
        let checkedSet = Set(note.checkedItems)

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack {
                Image(systemName: "checklist")
                Text("巡检模板: \(note.templateName ?? "")")
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
            }

            if templateItems.isEmpty {
                Text("(模板已被删除,检查清单不可用)")
                    .font(.system(size: DesignTokens.FontSize.body))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(templateItems, id: \.self) { item in
                    Button {
                        toggleChecked(item: item)
                    } label: {
                        HStack {
                            Image(systemName: checkedSet.contains(item) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(checkedSet.contains(item) ? Ink.fg : Ink.fgDim)
                            Text(item)
                                .font(.system(size: DesignTokens.FontSize.body))
                                .strikethrough(checkedSet.contains(item))
                                .foregroundStyle(checkedSet.contains(item) ? .secondary : .primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
                let unchecked = templateItems.count - checkedSet.count
                Text(unchecked == 0 ? "✓ 全部勾选完成" : "⚠️ \(unchecked) 项未勾选")
                    .font(.system(size: DesignTokens.FontSize.body))
                    .foregroundStyle(unchecked == 0 ? Ink.fg : Ink.red)
                    .padding(.top, 4)
            }
        }
        .padding(DesignTokens.Spacing.medium)
        .background(Ink.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 7. 平面图(折叠)

    @ViewBuilder
    private var floorPlanDisclosure: some View {
        let allPlans = FloorPlansStorage.load()
        if allPlans.isEmpty {
            EmptyView()
        } else {
            DisclosureGroup {
                floorPlanContent
                    .padding(.top, DesignTokens.Spacing.small)
            } label: {
                HStack {
                    Image(systemName: "map")
                        .foregroundStyle(Ink.fg)
                    Text(floorPlanDisclosureLabel)
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                }
            }
            .padding(DesignTokens.Spacing.medium)
            .background(Ink.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var floorPlanDisclosureLabel: String {
        if let name = note.floorPlanRef {
            return "平面图位置: \(name)"
        }
        return "平面图位置"
    }

    @ViewBuilder
    private var floorPlanContent: some View {
        if let planName = note.floorPlanRef,
           let x = note.floorPlanX,
           let y = note.floorPlanY,
           let plan = FloorPlansStorage.find(name: planName) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                FloorPlanDisplayView(plan: plan, x: x, y: y, pinColor: pinColorForThisNote)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button {
                    isShowingFloorPlanMark = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text("修改位置")
                    }
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                }
            }
        } else if note.floorPlanRef != nil {
            HStack {
                Text("平面图 \"\(note.floorPlanRef ?? "")\" 已被删除")
                    .font(.system(size: DesignTokens.FontSize.body))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("重新标记") { isShowingFloorPlanMark = true }
                    .font(.system(size: DesignTokens.FontSize.body))
            }
        } else {
            Button {
                isShowingFloorPlanMark = true
            } label: {
                HStack {
                    Image(systemName: "mappin.circle")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("在平面图上标位置")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("比 GPS 精细 10 倍")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(DesignTokens.Spacing.medium)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 8. 其他元数据(折叠,位置/天气/分享)

    private var otherMetaDisclosure: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                Divider()
                infoRow("位置", value: note.locationAddress ?? "未记录")
                Divider()
                infoRow("天气", value: note.weatherSummary ?? "未记录")
                if let sharedAt = note.lastSharedAt {
                    Divider()
                    infoRow("上次分享", value: sharedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
        } label: {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("其他详情(位置 · 天气 · 分享)")
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignTokens.Spacing.medium)
        .background(Ink.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: DesignTokens.FontSize.body))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Spacer(minLength: DesignTokens.Spacing.medium)
            Text(value)
                .font(.system(size: DesignTokens.FontSize.body))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, DesignTokens.Spacing.small)
    }

    private var deadlineDisplay: String {
        if note.deadline == .archive {
            return "归档"
        }
        let due = note.dueDate.formatted(date: .abbreviated, time: .omitted)
        return "\(note.deadline.displayName) · \(due)"
    }

    // MARK: - 6. 操作按钮

    /// 操作区:三排双等分按钮,颜色/分量统一。
    /// - 第 1 排:已处理 + 改期(常用主操作,填充色)
    /// - 第 2 排:分享 + 指派(中性 tonal)
    /// - 第 3 排:标记隐患 + 删除(描边 ghost,警示/危险)
    @ViewBuilder
    private var actionButtonGroup: some View {
        if isDiary {
            // 日志只保留:分享 + 删除。todo 类的(完成/改期/指派/标隐患)全部省去。
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
                            assignError = "当前设备不支持发送短信(可能是 iPad 或模拟器)"
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
            }
        }
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
                    .font(.system(size: 17, weight: .semibold))
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
                    .font(.system(size: 17, weight: .semibold))
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
        title: String,
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
        title: String,
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

    // MARK: - AI 操作

    private var aiLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: DesignTokens.Spacing.medium) {
                ProgressView().scaleEffect(1.4).tint(.white)
                Text("AI 处理中…")
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(DesignTokens.Spacing.large)
            .background(Color.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func runAIPolish() {
        let current = note.transcription
        guard !current.isEmpty else { return }
        aiWorking = true
        Task {
            do {
                let polished = try await AIService.shared.polishTranscription(current)
                if polished.trimmingCharacters(in: .whitespacesAndNewlines) == current.trimmingCharacters(in: .whitespacesAndNewlines) {
                    aiError = "润色后和原文相同,无需更新。"
                } else {
                    polishPreview = PolishPreview(before: current, after: polished)
                }
            } catch {
                aiError = "润色失败: \(error.localizedDescription)"
            }
            aiWorking = false
        }
    }

    private func polishPreviewSheet(_ preview: PolishPreview) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                    Text("AI 润色结果")
                        .font(.system(size: DesignTokens.FontSize.large, weight: .bold))

                    labeledBlock(title: "原文", text: preview.before, color: .secondary)
                    labeledBlock(title: "润色后", text: preview.after, color: Ink.fg)

                    HStack(spacing: DesignTokens.Spacing.small) {
                        Button("保留原文") {
                            polishPreview = nil
                        }
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: DesignTokens.ButtonSize.minTap)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            note.transcription = preview.after
                            polishPreview = nil
                        } label: {
                            Text("采用润色版")
                                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: DesignTokens.ButtonSize.minTap)
                                .background(Ink.fg)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("AI 润色")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func labeledBlock(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: DesignTokens.FontSize.large))
                .textSelection(.enabled)
                .padding(DesignTokens.Spacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Ink.card2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func runPhotoAnalysis() {
        let paths = note.photoPaths
        guard !paths.isEmpty else { return }
        aiWorking = true
        Task {
            var results: [PhotoAnalysisRow] = []
            for path in paths {
                guard let url = PhotoStorage.absoluteURL(forRelative: path),
                      let image = UIImage(contentsOfFile: url.path) else { continue }
                do {
                    let analysis = try await AIService.shared.analyzePhoto(image)
                    results.append(PhotoAnalysisRow(
                        path: path,
                        image: image,
                        description: analysis.description,
                        hazard: analysis.suggestedHazard,
                        action: analysis.suggestedAction
                    ))
                } catch {
                    results.append(PhotoAnalysisRow(
                        path: path,
                        image: image,
                        description: "分析失败: \(error.localizedDescription)",
                        hazard: false,
                        action: nil
                    ))
                }
            }
            aiWorking = false
            if results.isEmpty {
                aiError = "没有可分析的照片。"
            } else {
                photoAnalyses = PhotoAnalysesSheet(rows: results)
            }
        }
    }

    private func photoAnalysesSheet(_ sheet: PhotoAnalysesSheet) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                    let anyHazard = sheet.rows.contains { $0.hazard }
                    if anyHazard && !note.isHazard {
                        Button {
                            note.isHazard = true
                            NotificationService.shared.schedule(for: note)
                            photoAnalyses = nil
                        } label: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("AI 检测到隐患 · 标记这条为隐患")
                            }
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: DesignTokens.ButtonSize.minTap)
                            .background(Ink.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    ForEach(sheet.rows) { row in
                        photoAnalysisRowView(row)
                    }

                    Button {
                        let extras = sheet.rows
                            .map { "• \($0.description)" + ($0.action.map { "\n  建议: \($0)" } ?? "") }
                            .joined(separator: "\n")
                        let merged = [note.transcription, "", "[AI 照片分析]", extras]
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                        note.transcription = merged
                        photoAnalyses = nil
                    } label: {
                        HStack {
                            Image(systemName: "plus.bubble")
                            Text("把分析追加到转写")
                        }
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: DesignTokens.ButtonSize.minTap)
                        .background(Ink.fg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("AI 分析照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { photoAnalyses = nil }
                }
            }
        }
    }

    private func photoAnalysisRowView(_ row: PhotoAnalysisRow) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.medium) {
            Image(uiImage: row.image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                if row.hazard {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("疑似隐患")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.red)
                    }
                }
                Text(row.description)
                    .font(.system(size: DesignTokens.FontSize.body))
                if let action = row.action, !action.isEmpty {
                    Text("建议: \(action)")
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.small)
        .background(Ink.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions & helpers

    private func toggleChecked(item: String) {
        var set = Set(note.checkedItems)
        if set.contains(item) {
            set.remove(item)
        } else {
            set.insert(item)
        }
        note.checkedItems = Array(set)
    }

    private func reschedule(to newDeadline: Deadline) {
        note.deadline = newDeadline
        note.dueDate = newDeadline.dueDate(from: Date())
        NotificationService.shared.schedule(for: note)
    }

    /// 软删:打 deletedAt,取消推送,不碰文件。可在设置→垃圾桶里恢复或永久删除。
    private func softDeleteNote() {
        NotificationService.shared.cancel(for: note)
        note.deletedAt = Date()
        dismiss()
    }

    private func writeEditedPhoto(_ image: UIImage, toPath path: String) {
        guard let url = PhotoStorage.absoluteURL(forRelative: path),
              let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url)
    }

    /// 把一张新图保存到磁盘并加到当前 note。
    private func appendPhoto(_ image: UIImage) {
        let paths = PhotoStorage.save([image])
        guard !paths.isEmpty else { return }
        note.photoPaths = note.photoPaths + paths
        galleryRefreshID = UUID()
    }

    /// 点"分享"时生成单条 note 的 PDF(不带封面),含平面图+照片。
    /// 生成完成后设 `sharePDFURL` 触发 ShareSheet。
    private func generateSharePDF() {
        guard !isGeneratingShare else { return }
        isGeneratingShare = true
        // Note 是 SwiftData 模型,不是 Sendable,只能在 MainActor 上读。
        // 单条记录 PDF 生成很快(<1s),不阻塞感知。
        Task { @MainActor in
            do {
                let url = try PDFExportService.generatePDF(
                    notes: [note],
                    startDate: nil,
                    endDate: nil,
                    title: "SiteNote 记录",
                    includeCoverPage: false,
                    filenamePrefix: "SiteNote-Note"
                )
                sharePDFURL = url
                isGeneratingShare = false
            } catch {
                aiError = "分享 PDF 生成失败: \(error.localizedDescription)"
                isGeneratingShare = false
            }
        }
    }

    private func buildAssignMessage() -> String {
        let dateStr = note.createdAt.formatted(date: .abbreviated, time: .shortened)
        let loc = note.locationAddress.map { " · \($0)" } ?? ""
        let deadline = "截止: \(note.deadline.displayName)"
        let body = note.transcription.isEmpty ? "(见照片)" : note.transcription
        var lines: [String] = ["[SiteNote \(dateStr)\(loc)]", body]
        if let tag = note.siteTag { lines.append("工地: \(tag)") }
        if !note.otherTags.isEmpty { lines.append("类型: " + note.otherTags.joined(separator: " / ")) }
        if let planName = note.floorPlanRef { lines.append("位置: 平面图 \(planName)") }
        lines.append(deadline)
        lines.append("—— 请处理并回复。")
        return lines.joined(separator: "\n")
    }

    /// 收集要随指派短信发的图片:note 的照片 + 平面图(若有)。
    /// 数量限制 MMS 总大小,最多 5 张。
    private func loadNotePhotosForAssignment() -> [UIImage] {
        var images: [UIImage] = []

        // 原照片(最多 3 张,给 MMS 大小留余量)
        for path in note.photoPaths.prefix(3) {
            if let url = PhotoStorage.absoluteURL(forRelative: path),
               let img = UIImage(contentsOfFile: url.path) {
                images.append(img)
            }
        }

        // 平面图带图钉(如果有)
        if let planName = note.floorPlanRef,
           let x = note.floorPlanX,
           let y = note.floorPlanY,
           let plan = FloorPlansStorage.find(name: planName),
           let url = FloorPlansStorage.absoluteURL(forRelative: plan.imageRelativePath),
           let planImage = UIImage(contentsOfFile: url.path),
           let composited = renderFloorPlanWithPin(planImage, normalizedX: x, normalizedY: y, color: pinColorForThisNote) {
            images.append(composited)
        }

        return images
    }

    /// 把平面图和图钉合成一张 UIImage,用于短信附件。
    private func renderFloorPlanWithPin(
        _ image: UIImage,
        normalizedX: Double,
        normalizedY: Double,
        color: Color
    ) -> UIImage? {
        // 渲染到 1000×1000 bbox,图片 aspect fit 居中
        let canvasSize = CGSize(width: 1000, height: 1000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { _ in
            // 浅灰背景
            UIColor(white: 0.95, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()

            // Aspect fit
            let imgAspect = image.size.width / image.size.height
            let canvasAspect: CGFloat = 1.0
            let imgRect: CGRect
            if imgAspect > canvasAspect {
                let h = canvasSize.width / imgAspect
                imgRect = CGRect(x: 0, y: (canvasSize.height - h) / 2, width: canvasSize.width, height: h)
            } else {
                let w = canvasSize.height * imgAspect
                imgRect = CGRect(x: (canvasSize.width - w) / 2, y: 0, width: w, height: canvasSize.height)
            }
            image.draw(in: imgRect)

            // 图钉
            let pinX = imgRect.minX + imgRect.width * CGFloat(normalizedX)
            let pinY = imgRect.minY + imgRect.height * CGFloat(normalizedY)
            let dotRadius: CGFloat = 18
            let outerRadius: CGFloat = dotRadius + 4

            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(
                x: pinX - outerRadius,
                y: pinY - outerRadius,
                width: outerRadius * 2,
                height: outerRadius * 2
            )).fill()

            UIColor(color).setFill()
            UIBezierPath(ovalIn: CGRect(
                x: pinX - dotRadius,
                y: pinY - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )).fill()

            // 白色十字
            UIColor.white.setStroke()
            let cross = UIBezierPath()
            cross.move(to: CGPoint(x: pinX - 7, y: pinY))
            cross.addLine(to: CGPoint(x: pinX + 7, y: pinY))
            cross.move(to: CGPoint(x: pinX, y: pinY - 7))
            cross.addLine(to: CGPoint(x: pinX, y: pinY + 7))
            cross.lineWidth = 3
            cross.stroke()
        }
    }
}

// MARK: - Supporting types

private enum ContextChipKind {
    case tag     // 主标签:可点开 picker 改
    case hazard  // 隐患:展示用
    case other   // 模板 / 条款 / 指派 / 平面图 等:展示用
}

private struct ContextChip: Identifiable {
    let id: UUID = UUID()
    let icon: String
    let text: String
    let color: Color
    let kind: ContextChipKind
}

private struct SharePDFItem: Identifiable {
    let id: UUID = UUID()
    let url: URL
}

private struct FullscreenPhoto: Identifiable {
    let id: UUID = UUID()
    let image: UIImage
}

private struct DetailPhotoEdit: Identifiable {
    let id: UUID = UUID()
    let path: String
    let image: UIImage
}

private struct PendingAssignee: Identifiable {
    let id: UUID = UUID()
    let name: String
    let phone: String
}

private struct PolishPreview: Identifiable {
    let id: UUID = UUID()
    let before: String
    let after: String
}

private struct PhotoAnalysisRow: Identifiable {
    let id: UUID = UUID()
    let path: String
    let image: UIImage
    let description: String
    let hazard: Bool
    let action: String?
}

private struct PhotoAnalysesSheet: Identifiable {
    let id: UUID = UUID()
    let rows: [PhotoAnalysisRow]
}

/// 标签选择 sheet。
/// - 工地:单选 radio,列表来自 SiteTagsStorage
/// - 子标签:**单选** radio,全局共享,来自 SubTagsStorage
/// - 就地新建工地或子标签(新建子标签需要选颜色)
/// 工地 / 子标签 picker sheet。
struct TagPickerSheet: View {
    let currentSiteTag: String?
    let currentOtherTags: [String]
    let onSiteChange: (String?) -> Void
    let onOtherTagsChange: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var siteTags: [String] = SiteTagsStorage.load()
    @State private var subTags: [SubTag] = SubTagsStorage.load()

    @State private var selectedSite: String?
    /// 单选:最多一个子标签名。为 nil 表示未选。
    @State private var selectedSubName: String?

    @State private var showsAddSite: Bool = false
    @State private var showsAddSub: Bool = false
    @State private var newSiteName: String = ""

    var body: some View {
        NavigationStack {
            List {
                siteSection
                subTagSection
            }
            .navigationTitle("选标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .bold()
                }
            }
            .onAppear {
                selectedSite = currentSiteTag
                selectedSubName = currentOtherTags.first
                subTags = SubTagsStorage.load()
            }
            .sheet(isPresented: $showsAddSub) {
                NewSubTagSheet { tag in
                    subTags = SubTagsStorage.add(tag)
                    setSubTag(tag.name)
                }
            }
            .alert("新建工地标签", isPresented: $showsAddSite) {
                TextField("工地名(如 悉尼 Olympic Park)", text: $newSiteName)
                Button("添加") {
                    let trimmed = newSiteName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    siteTags = SiteTagsStorage.add(trimmed)
                    setSite(trimmed)
                    newSiteName = ""
                }
                Button("取消", role: .cancel) { newSiteName = "" }
            }
        }
    }

    // MARK: - Sections

    private var siteSection: some View {
        Section {
            radioRow(
                text: "不设工地(未命名)",
                icon: "building.2",
                tint: .gray,
                selected: selectedSite == nil,
                action: { setSite(nil) }
            )
            ForEach(siteTags, id: \.self) { tag in
                radioRow(
                    text: tag,
                    icon: "building.2.fill",
                    tint: Ink.fg,
                    selected: selectedSite == tag,
                    action: { setSite(tag) }
                )
            }
            Button {
                newSiteName = ""
                showsAddSite = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                    Text("新建工地标签")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Ink.fg)
            }
            .buttonStyle(.plain)
        } header: {
            Text("工地(单选)")
        }
    }

    @ViewBuilder
    private var subTagSection: some View {
        Section {
            radioRow(
                text: "不设子标签",
                icon: "tag",
                tint: .gray,
                selected: selectedSubName == nil,
                action: { setSubTag(nil) }
            )
            ForEach(subTags) { sub in
                subTagRadioRow(sub: sub)
            }
            Button {
                showsAddSub = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                    Text("新建子标签")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        } header: {
            Text("子标签(单选)")
        } footer: {
            Text("子标签是全局的类型分类,如 RFI、缺陷、施工、开会、紧急。平面图图钉按子标签颜色显示。")
                .font(.system(size: 12))
        }
    }

    // MARK: - Rows

    private func radioRow(
        text: String,
        icon: String,
        tint: Color,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(text)
                    .foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.bold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subTagRadioRow(sub: SubTag) -> some View {
        let selected = selectedSubName == sub.name
        return Button {
            setSubTag(sub.name)
        } label: {
            HStack {
                Circle()
                    .fill(sub.color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
                    .frame(width: 24)
                Text(sub.name)
                    .foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.bold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func setSite(_ name: String?) {
        selectedSite = name
        onSiteChange(name)
    }

    private func setSubTag(_ name: String?) {
        selectedSubName = name
        if let name {
            onOtherTagsChange([name])
        } else {
            onOtherTagsChange([])
        }
    }
}

/// 新建子标签 sheet。名字 + 颜色,单独一个 sheet 避免和 Form 里的 Button 打架。
struct NewSubTagSheet: View {
    let onAdded: (SubTag) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var colorName: String = "blue"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                    // 名字
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text("名字")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("如 RFI、缺陷、施工、开会、紧急", text: $name)
                            .font(.system(size: DesignTokens.FontSize.body))
                            .padding(DesignTokens.Spacing.medium)
                            .background(Ink.card2)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // 颜色选择 (独立 ZStack / VStack,不在 Form Section 里,避免整行被吞 tap)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text("颜色")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                            spacing: 14
                        ) {
                            ForEach(SubTag.availableColorNames, id: \.self) { c in
                                colorSwatch(colorName: c)
                            }
                        }
                    }

                    // 预览
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text("预览")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(SubTag.color(from: colorName))
                                .frame(width: 10, height: 10)
                            Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(名字)" : name)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(SubTag.color(from: colorName))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(SubTag.color(from: colorName).opacity(0.15))
                        .clipShape(Capsule())
                    }

                    Text("这个颜色也会用在平面图图钉上,方便一眼分辨。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("新建子标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onAdded(SubTag(name: trimmed, colorName: colorName))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .bold()
                }
            }
        }
    }

    /// 单个颜色圆按钮。用 buttonStyle(.plain) 保证 tap 命中自己而不是周围容器。
    private func colorSwatch(colorName c: String) -> some View {
        Button {
            colorName = c
        } label: {
            Circle()
                .fill(SubTag.color(from: c))
                .frame(width: 42, height: 42)
                .overlay(
                    Circle()
                        .strokeBorder(
                            colorName == c ? Color.primary : Color.black.opacity(0.15),
                            lineWidth: colorName == c ? 3 : 1
                        )
                )
                .overlay {
                    if colorName == c {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

private struct FullscreenPhotoView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1, min(value, 4))
                        }
                        .onEnded { _ in
                            withAnimation { scale = max(1, scale) }
                        }
                )
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white, Color.black.opacity(0.5))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}
