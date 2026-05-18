//
//  DeadlineSheet.swift
//  SiteNote
//
//  录音完成后的弹窗:工地标签 + 照片 + 隐患开关 + 合同条款 + 到期。
//  选 deadline 即保存。
//

import SwiftUI
import PhotosUI
import UIKit

/// DeadlineSheet 回调时带回的全部用户选择。
struct DeadlineSheetResult {
    let deadline: Deadline
    let photos: [UIImage]
    let siteTag: String?
    let isHazard: Bool
    let contractClauseRef: String?
    let floorPlanRef: String?
    let floorPlanX: Double?
    let floorPlanY: Double?
}

/// 录音后的选项卡。
struct DeadlineSheet: View {

    let transcription: String
    let locationLabel: String?
    /// 任务 14:从语音推断的 deadline,作为默认高亮。nil 时默认 threeDays。
    var suggestedDeadline: Deadline?
    let onCommit: (DeadlineSheetResult) -> Void

    @State private var images: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var capturedImage: UIImage?
    @State private var isShowingSourceDialog = false
    @State private var isShowingCamera = false
    @State private var isShowingLibrary = false
    @State private var editingIndex: EditingImageIndex?

    /// 用户编辑过标注的照片索引,显示"已标注"角标。
    @State private var editedPhotoIndexes: Set<Int> = []

    @State private var selectedSiteTag: String?
    @State private var availableTags: [String] = []

    @State private var isHazard: Bool = false

    @State private var availableClauseRefs: [String] = []
    @State private var selectedClauseRef: String?

    @State private var availableFloorPlans: [FloorPlan] = []
    @State private var floorPlanMark: FloorPlanMarkResult?
    @State private var isShowingFloorPlan: Bool = false

    /// 高级选项(隐患/模板/条款/平面图)是否展开。默认折叠,保持速记速度。
    @State private var showsAdvanced: Bool = false

    private let maxPhotos = 5

    var body: some View {
        VStack(spacing: 0) {
            // 居中标题
            Text(String(localized: "什么时候前要处理完?", locale: AppLanguageManager.currentLocale))
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.2)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 16) {
                    transcriptionPreview

                    // 主操作:4 个 deadline 按钮并排
                    deadlineButtonRow

                    // 副选项行:工地 chip + 照片 chip + 更多选项
                    secondaryOptionsRow

                    if !availableFloorPlans.isEmpty {
                        floorPlanButton
                    }

                    if showsAdvanced {
                        VStack(spacing: 12) {
                            photoRow
                            hazardToggle
                            if !availableClauseRefs.isEmpty {
                                clauseRefPicker
                            }
                            if let locationLabel {
                                HStack(spacing: 6) {
                                    Image(systemName: "location")
                                        .font(.system(size: 12))
                                    Text(locationLabel)
                                        .font(.system(size: 12))
                                }
                                .foregroundStyle(Ink.fgDim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.25), value: showsAdvanced)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(true)
        .onAppear {
            availableTags = SiteTagsStorage.load()
            availableClauseRefs = ClauseRefsStorage.load()
            availableFloorPlans = FloorPlansStorage.load()
        }
        .sheet(isPresented: $isShowingFloorPlan) {
            FloorPlanMarkView(preferredSiteTag: selectedSiteTag) { result in
                floorPlanMark = result
            }
        }
        .onChange(of: capturedImage) { _, newImage in
            if let img = newImage {
                images.append(img)
                capturedImage = nil
            }
        }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        images.append(img)
                    }
                }
                pickerItems = []
            }
        }
    }

    // MARK: - Transcription

    @ViewBuilder
    private var transcriptionPreview: some View {
        let text = transcription.isEmpty ? String(localized: "(无转写,仅保存录音)", locale: AppLanguageManager.currentLocale) : transcription
        Text(text)
            .font(.system(size: 14))
            .lineSpacing(4)
            .foregroundStyle(transcription.isEmpty ? Ink.fgDim : Ink.fg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Ink.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// 副选项行:工地 chip + 照片 chip(总数 summary)+ 更多选项 chevron。
    private var secondaryOptionsRow: some View {
        HStack(spacing: 8) {
            siteChipSummary
            photoSummaryChip
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showsAdvanced.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(String(
                        localized: showsAdvanced ? "收起" : "更多选项",
                        locale: AppLanguageManager.currentLocale
                    ))
                        .font(.system(size: 12))
                    Image(systemName: showsAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Ink.fgDim)
            }
            .buttonStyle(.plain)
        }
    }

    /// 单 chip 表示当前选中工地;点开 menu 切换。
    /// 空 tags 时仍显示一个 disabled 占位 chip,保持行视觉对齐,提示用户去 settings 建工地。
    @ViewBuilder
    private var siteChipSummary: some View {
        if availableTags.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "building.2")
                    .font(.system(size: 10, weight: .semibold))
                Text(String(localized: "未建工地", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Ink.fgDim)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Ink.bg))
            .overlay(Capsule().stroke(Ink.line, lineWidth: 1))
        } else {
            Menu {
                Button {
                    selectedSiteTag = nil
                } label: {
                    if selectedSiteTag == nil {
                        Label(String(localized: "未分类", locale: AppLanguageManager.currentLocale), systemImage: "checkmark")
                    } else {
                        Text(String(localized: "未分类", locale: AppLanguageManager.currentLocale))
                    }
                }
                Divider()
                ForEach(availableTags, id: \.self) { tag in
                    Button {
                        selectedSiteTag = tag
                    } label: {
                        if selectedSiteTag == tag {
                            Label(tag, systemImage: "checkmark")
                        } else {
                            Text(tag)
                        }
                    }
                }
            } label: {
                let isPicked = selectedSiteTag != nil
                HStack(spacing: 5) {
                    Image(systemName: "building.2")
                        .font(.system(size: 10, weight: .semibold))
                    Text(selectedSiteTag ?? String(localized: "选工地", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(isPicked ? Ink.bg : Ink.fg)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Capsule().fill(isPicked ? Ink.fg : Ink.bg))
                .overlay(Capsule().stroke(isPicked ? Color.clear : Ink.line, lineWidth: 1))
            }
        }
    }

    /// 显示当前照片数量的 chip(点开 = 展开 advanced 让用户加 / 改照片)。
    @ViewBuilder
    private var photoSummaryChip: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                showsAdvanced = true
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "photo")
                    .font(.system(size: 10, weight: .semibold))
                Text(images.isEmpty
                    ? String(localized: "加照片", locale: AppLanguageManager.currentLocale)
                    : String(localized: "\(images.count) 张照片", locale: AppLanguageManager.currentLocale)
                )
                .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Ink.fg)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Ink.bg))
            .overlay(Capsule().stroke(Ink.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hazard

    private var hazardToggle: some View {
        Toggle(isOn: $isHazard) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(isHazard ? .red : .orange)
                Text("标记为隐患")
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
            }
        }
        .tint(.red)
        .padding(DesignTokens.Spacing.small)
        .background(isHazard ? Color.red.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .sensoryFeedback(.warning, trigger: isHazard)
    }

    // MARK: - Site tag picker

    private var siteTagPicker: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("工地")
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.small) {
                    chip(title: String(localized: "未分类", locale: AppLanguageManager.currentLocale), isSelected: selectedSiteTag == nil) {
                        selectedSiteTag = nil
                    }
                    ForEach(availableTags, id: \.self) { tag in
                        chip(title: tag, isSelected: selectedSiteTag == tag) {
                            selectedSiteTag = tag
                        }
                    }
                }
            }
        }
    }

    // MARK: - Clause ref picker

    private var clauseRefPicker: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("引用合同条款")
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.small) {
                    chip(title: String(localized: "无", locale: AppLanguageManager.currentLocale), isSelected: selectedClauseRef == nil) {
                        selectedClauseRef = nil
                    }
                    ForEach(availableClauseRefs, id: \.self) { ref in
                        chip(title: ref, isSelected: selectedClauseRef == ref) {
                            selectedClauseRef = ref
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared chip

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: DesignTokens.FontSize.body, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, DesignTokens.Spacing.medium)
                .padding(.vertical, DesignTokens.Spacing.small)
                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                .clipShape(Capsule())
        }
    }

    // MARK: - Floor plan

    private var floorPlanButton: some View {
        Button {
            isShowingFloorPlan = true
        } label: {
            HStack {
                Image(systemName: floorPlanMark == nil ? "map" : "mappin.circle.fill")
                    .foregroundStyle(floorPlanMark == nil ? Color.accentColor : .red)
                VStack(alignment: .leading, spacing: 2) {
                    if let mark = floorPlanMark {
                        Text("已标位置: \(mark.planName)")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            .foregroundStyle(.primary)
                        let coords = String(format: "x=%.2f y=%.2f", mark.x, mark.y)
                        Text("\(coords)(点击修改)")
                            .font(.system(size: DesignTokens.FontSize.body))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("在平面图上标位置(可选)")
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(DesignTokens.Spacing.medium)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Photo row

    private var photoRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.small) {
                // 用 enumerated() + snapshot,把 UIImage 按值捕获,避免数组缩减的瞬间
                // ForEach 用旧 index 越界崩溃(Swift ContiguousArrayBuffer:692)。
                ForEach(Array(images.enumerated()), id: \.offset) { idx, image in
                    Button {
                        editingIndex = EditingImageIndex(value: idx)
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            // 右下角:已编辑角标(如果这张被标注过)
                            if editedPhotoIndexes.contains(idx) {
                                HStack(spacing: 2) {
                                    Image(systemName: "pencil.tip.crop.circle.fill")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("已标注")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .clipShape(Capsule())
                                .offset(x: -4, y: 60)
                            }

                            // 右上角:编辑入口图标
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white, Color.black.opacity(0.6))
                                .padding(3)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "编辑第 \(idx + 1) 张照片", locale: AppLanguageManager.currentLocale))
                }
                if images.count < maxPhotos {
                    addPhotoButton
                }
            }
        }
        .sheet(item: $editingIndex) { ei in
            PhotoEditorView(originalImage: images[ei.value]) { edited in
                if ei.value < images.count {
                    images[ei.value] = edited
                    editedPhotoIndexes.insert(ei.value)
                }
            }
        }
    }

    private var addPhotoButton: some View {
        Button {
            isShowingSourceDialog = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                Text("加照片")
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 80, height: 80)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(String(localized: "加照片"))
        .confirmationDialog("加照片", isPresented: $isShowingSourceDialog, titleVisibility: .hidden) {
            Button("📸 拍照") { isShowingCamera = true }
            Button("🖼 从相册选") { isShowingLibrary = true }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraPicker(image: $capturedImage)
                .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $isShowingLibrary,
            selection: $pickerItems,
            maxSelectionCount: max(1, maxPhotos - images.count),
            matching: .images
        )
    }

    // MARK: - Deadline buttons

    private var primaryDeadline: Deadline {
        suggestedDeadline ?? .threeDays
    }

    /// 4 个 deadline 主操作并排,推荐项 = 黑底白字。
    private var deadlineButtonRow: some View {
        VStack(spacing: 10) {
            if let suggestedDeadline {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(localized: "语音里提到「\(suggestedDeadline.displayName)」,已预选",
                                locale: AppLanguageManager.currentLocale))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Ink.fgDim)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                deadlineMiniButton(.today, sub: deadlineSubLabel(for: .today))
                deadlineMiniButton(.threeDays, sub: deadlineSubLabel(for: .threeDays))
                deadlineMiniButton(.thisWeek, sub: deadlineSubLabel(for: .thisWeek))
                deadlineMiniButton(.archive, sub: deadlineSubLabel(for: .archive))
            }
        }
    }

    private func deadlineSubLabel(for deadline: Deadline) -> String {
        switch deadline {
        case .today: return String(localized: "18:00 前", locale: AppLanguageManager.currentLocale)
        case .threeDays: return String(localized: "3 天内", locale: AppLanguageManager.currentLocale)
        case .thisWeek: return String(localized: "本周日前", locale: AppLanguageManager.currentLocale)
        case .archive: return String(localized: "不提醒", locale: AppLanguageManager.currentLocale)
        case .inbox: return ""
        }
    }

    private func deadlineMiniButton(_ deadline: Deadline, sub: String) -> some View {
        let isPrimary = deadline == primaryDeadline
        return Button {
            let result = DeadlineSheetResult(
                deadline: deadline,
                photos: images,
                siteTag: selectedSiteTag,
                isHazard: isHazard,
                contractClauseRef: selectedClauseRef,
                floorPlanRef: floorPlanMark?.planName,
                floorPlanX: floorPlanMark?.x,
                floorPlanY: floorPlanMark?.y
            )
            onCommit(result)
        } label: {
            VStack(spacing: 3) {
                Text(deadline.displayName)
                    .font(.system(size: 15, weight: .semibold))
                Text(sub)
                    .font(.system(size: 11))
                    .opacity(0.65)
            }
            .foregroundStyle(isPrimary ? Ink.bg : Ink.fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isPrimary ? Ink.fg : Ink.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isPrimary ? Color.clear : Ink.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(deadline.displayName)
    }
}

private struct EditingImageIndex: Identifiable {
    let id: UUID = UUID()
    let value: Int
}

#Preview {
    DeadlineSheet(
        transcription: "3 楼钢筋没到货下午 2 点前解决",
        locationLabel: "Sydney, NSW"
    ) { result in
        _ = result  // preview no-op
    }
}
