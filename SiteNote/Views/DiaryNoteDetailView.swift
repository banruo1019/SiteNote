//
//  DiaryNoteDetailView.swift
//  SiteNote
//
//  **日志模式** note 的精简详情页。
//
//  定位:保留做工地日记必要的字段(工地 / 子标签 / 照片 / 录音 / AI 识别),
//       **去掉 todo 类字段**(deadline / 隐患 / 模板 / 条款 / 指派 / 平面图)。
//

import SwiftUI
import SwiftData
import UIKit
import PhotosUI

struct DiaryNoteDetailView: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 这条 note 的所有 LogEntry(反向通过 sourceNoteID 拉)。用于"类型"行展示。
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

    @State private var showsDeleteConfirm = false
    @State private var fullscreenPhoto: DiaryFullscreenPhoto?
    @State private var isAudioExpanded = false

    @State private var showsTagPicker = false

    // 加照片相关(用 alert 居中展示)
    @State private var showsPhotoSourceAlert = false
    @State private var showsCamera = false
    @State private var capturedImage: UIImage?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsLibraryPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.medium) {
                titleBlock
                NoteClassificationCard(note: note)  // AI 的工地/子标签建议(自动裁剪)
                tagsRow                             // 工地 + 子标签 picker
                if !logEntries.isEmpty {
                    typeRow                         // 已识别的类型 chip(人员/机械/送达/访客/事件)
                }
                LogEntryChipSection(note: note)     // AI 识别的结构化条目
                photosBlock
                addPhotoRow
                metadataBlock
                audioBlock
                deleteButton
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle("日志")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $fullscreenPhoto) { photo in
            DiaryFullscreenPhotoView(image: photo.image)
        }
        .sheet(isPresented: $showsTagPicker) {
            TagPickerSheet(
                currentSiteTag: note.siteTag,
                currentOtherTags: note.otherTags,
                onSiteChange: { newTag in
                    note.siteTag = newTag
                    if let tag = newTag,
                       let lat = note.latitude, let lng = note.longitude {
                        SiteCentroidsStorage.observe(siteName: tag, latitude: lat, longitude: lng)
                    }
                    // 同步 LogEntry 的 siteTag
                    if let ctx = note.modelContext {
                        let id = note.id
                        let desc = FetchDescriptor<LogEntry>(
                            predicate: #Predicate<LogEntry> { $0.sourceNoteID == id }
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
        .sheet(isPresented: $showsCamera) {
            CameraPicker(image: $capturedImage)
                .ignoresSafeArea()
        }
        .onChange(of: capturedImage) { _, newImage in
            guard let img = newImage else { return }
            capturedImage = nil
            attachPhoto(img)
        }
        .photosPicker(isPresented: $showsLibraryPicker, selection: $pickerItems, matching: .images)
        .onChange(of: pickerItems) { _, items in
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        attachPhoto(img)
                    }
                }
                pickerItems = []
            }
        }
        .alert("加照片", isPresented: $showsPhotoSourceAlert) {
            Button("拍照") { showsCamera = true }
            Button("从相册选") { showsLibraryPicker = true }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选一种加照片的方式")
        }
        .alert("删除这条日志?", isPresented: $showsDeleteConfirm) {
            Button("删除", role: .destructive) {
                NotificationService.shared.cancel(for: note)
                note.deletedAt = Date()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会一并软删这条 note 和它 AI 识别出的所有条目。可以去垃圾桶恢复。")
        }
    }

    // MARK: - Title: 可编辑转写

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.accentBlue)
                Text("施工日记")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Ink.accentBlue)
            }
            TextEditor(text: $note.transcription)
                .font(.system(size: 16))
                .foregroundStyle(Ink.fg)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60)
                .padding(8)
                .background(Ink.card, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Tags row(工地 + 子标签)

    private var tagsRow: some View {
        Button {
            showsTagPicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "tag")
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.fgDim)
                if let site = note.siteTag, !site.isEmpty {
                    tagChip(text: site, color: Ink.green)
                } else {
                    Text("选工地")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.fgDim)
                }
                ForEach(note.otherTags, id: \.self) { t in
                    tagChip(text: t, color: SubTagsStorage.color(name: t))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Ink.dim)
            }
            .padding(10)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Type row(已识别类型)

    /// 列出这条 note 的所有 LogEntry 涉及的 kind(人员 / 机械 / 送达 / 访客 / 事件)。
    /// 多种类型混合记录时(如"水工 4 个 + 挖机到了")会并列显示。
    private var typeRow: some View {
        let kindOrder: [LogKind] = [.person, .plant, .delivery, .visitor, .event]
        let presentKinds = kindOrder.filter { k in
            logEntries.contains(where: { $0.kind == k })
        }
        return HStack(spacing: 6) {
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
                    Text(iconFor(kind: k))
                    Text(k.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Ink.fg)
                    Text("\(countFor(kind: k))")
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

    private func iconFor(kind: LogKind) -> String {
        switch kind {
        case .person: return "👥"
        case .plant: return "🚜"
        case .delivery: return "📦"
        case .visitor: return "🧑"
        case .event: return "⚠️"
        }
    }

    private func countFor(kind: LogKind) -> Int {
        logEntries.filter { $0.kind == kind }.count
    }

    private func tagChip(text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Ink.fg)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Photos

    @ViewBuilder
    private var photosBlock: some View {
        if !note.photoPaths.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(note.photoPaths, id: \.self) { path in
                        if let url = PhotoStorage.absoluteURL(forRelative: path),
                           let img = UIImage(contentsOfFile: url.path) {
                            Button {
                                fullscreenPhoto = DiaryFullscreenPhoto(image: img)
                            } label: {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// "+ 加照片"按钮。tap → 弹居中 alert(拍照/相册)
    private var addPhotoRow: some View {
        Button {
            showsPhotoSourceAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                Text("加照片")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Ink.fgDim)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Ink.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
    }

    private func attachPhoto(_ img: UIImage) {
        let paths = PhotoStorage.save([img])
        note.photoPaths.append(contentsOf: paths)
    }

    // MARK: - Metadata(小字一行:时间 · 天气 · 位置)

    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                metaChip(icon: "clock", text: createdLabel)
                if let w = note.weatherSummary, !w.isEmpty {
                    metaChip(icon: "cloud", text: w)
                }
            }
            if let loc = note.locationAddress, !loc.isEmpty {
                metaChip(icon: "location", text: loc)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metaChip(icon: String, text: String, tint: Color = Ink.fgDim) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
    }

    private var createdLabel: String {
        let f = DateFormatter()
        f.dateFormat = "M 月 d 日 HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: note.createdAt)
    }

    // MARK: - Audio(折叠)

    @ViewBuilder
    private var audioBlock: some View {
        if let path = note.audioFilePath {
            DisclosureGroup(isExpanded: $isAudioExpanded) {
                // 用共享的 AudioPlayerView,内部处理了 AVAudioSession 的 .playback 切换——
                // 自己卷一个 AVAudioPlayer 会因为 session 还停在 .record 而无声。
                AudioPlayerView(audioRelativePath: path)
                    .padding(.top, 8)
            } label: {
                HStack {
                    Image(systemName: "waveform")
                    Text("录音")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Ink.fgDim)
            }
            .padding(12)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button(role: .destructive) {
            showsDeleteConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("删除日志")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Ink.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Ink.red.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}

private struct DiaryFullscreenPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct DiaryFullscreenPhotoView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale = max(1, min($0, 4)) }
                )
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white, .black.opacity(0.4))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

