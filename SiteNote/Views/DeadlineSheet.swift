//
//  DeadlineSheet.swift
//  SiteNote
//
//  录音完成后的弹窗:工地标签 + 照片 + 隐患开关 + 巡检模板 + 合同条款 + 截止。
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
    let templateName: String?
    let checkedItems: [String]
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

    @State private var availableTemplates: [InspectionTemplate] = []
    @State private var selectedTemplate: InspectionTemplate?
    @State private var checkedItems: Set<String> = []

    @State private var availableClauseRefs: [String] = []
    @State private var selectedClauseRef: String?

    @State private var availableFloorPlans: [FloorPlan] = []
    @State private var floorPlanMark: FloorPlanMarkResult?
    @State private var isShowingFloorPlan: Bool = false

    /// AI 自动标签的解释,非空时在顶部显示。
    @State private var aiReasoning: String?

    /// 高级选项(隐患/模板/条款/平面图)是否展开。默认折叠,保持速记速度。
    @State private var showsAdvanced: Bool = false

    private let maxPhotos = 5

    var body: some View {
        VStack(spacing: 0) {
            Text("什么时候前要处理完?")
                .font(.system(size: DesignTokens.FontSize.large, weight: .semibold))
                .padding(.vertical, DesignTokens.Spacing.medium)

            Divider()

            ScrollView {
                VStack(spacing: DesignTokens.Spacing.medium) {
                    // ========= 主要区(常用)=========
                    transcriptionPreview

                    if let reasoning = aiReasoning {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.purple)
                            Text(reasoning)
                                .font(.system(size: DesignTokens.FontSize.body))
                                .foregroundStyle(.purple)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.small)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.purple.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                    }

                    if let locationLabel {
                        HStack {
                            Image(systemName: "location")
                            Text(locationLabel)
                                .font(.system(size: DesignTokens.FontSize.body))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !availableTags.isEmpty {
                        siteTagPicker
                    }

                    // 平面图入口:有平面图就直接放出来,不藏在"更多选项"里。
                    if !availableFloorPlans.isEmpty {
                        floorPlanButton
                    }

                    photoRow

                    // ========= Deadline 按钮(主行动,前置)=========
                    Divider().padding(.vertical, DesignTokens.Spacing.small)
                    deadlineButtons

                    // ========= 更多选项(折叠)=========
                    advancedToggleButton

                    if showsAdvanced {
                        VStack(spacing: DesignTokens.Spacing.medium) {
                            hazardToggle

                            if !availableTemplates.isEmpty {
                                templatePicker
                            }

                            if !availableClauseRefs.isEmpty {
                                clauseRefPicker
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    }
                }
                .padding(DesignTokens.Spacing.medium)
                .animation(.easeInOut(duration: 0.25), value: showsAdvanced)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(true)
        .onAppear {
            availableTags = SiteTagsStorage.load()
            availableTemplates = InspectionTemplatesStorage.load()
            availableClauseRefs = ClauseRefsStorage.load()
            availableFloorPlans = FloorPlansStorage.load()
            runAutoTagSuggestion()
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

    /// AI 自动标签推断,只在用户还没手选时生效。
    private func runAutoTagSuggestion() {
        let enabled = UserDefaults.standard.object(forKey: "settings.aiAutoTagEnabled") as? Bool ?? true
        guard enabled,
              !transcription.isEmpty,
              selectedSiteTag == nil,
              selectedTemplate == nil,
              selectedClauseRef == nil
        else { return }

        let suggestion = AIService.shared.suggestTags(
            transcription: transcription,
            availableSites: availableTags,
            availableTemplates: availableTemplates,
            availableClauses: availableClauseRefs
        )
        if let site = suggestion.suggestedSiteTag {
            selectedSiteTag = site
        }
        if let templateName = suggestion.suggestedTemplateName,
           let tpl = availableTemplates.first(where: { $0.name == templateName }) {
            selectedTemplate = tpl
        }
        if let clause = suggestion.suggestedClauseRef {
            selectedClauseRef = clause
        }
        aiReasoning = suggestion.reasoning
    }

    // MARK: - Transcription

    @ViewBuilder
    private var transcriptionPreview: some View {
        let text = transcription.isEmpty ? "(无转写,仅保存录音)" : transcription
        Text(text)
            .font(.system(size: DesignTokens.FontSize.body))
            .foregroundStyle(transcription.isEmpty ? .tertiary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignTokens.Spacing.medium)
            .background(Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 展开/折叠高级选项的按钮。点了就切换。
    private var advancedToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                showsAdvanced.toggle()
            }
        } label: {
            HStack {
                Image(systemName: showsAdvanced ? "chevron.up.circle" : "chevron.down.circle")
                Text(showsAdvanced ? "收起高级选项" : "更多选项(隐患 / 模板 / 条款 / 平面图)")
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
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
                    chip(title: "未分类", isSelected: selectedSiteTag == nil) {
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

    // MARK: - Template picker

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("巡检模板")
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.small) {
                    chip(title: "无模板", isSelected: selectedTemplate == nil) {
                        selectedTemplate = nil
                        checkedItems.removeAll()
                    }
                    ForEach(availableTemplates) { template in
                        chip(title: template.name, isSelected: selectedTemplate?.id == template.id) {
                            selectedTemplate = template
                            checkedItems.removeAll()
                        }
                    }
                }
            }

            if let template = selectedTemplate {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(template.items, id: \.self) { item in
                        templateCheckRow(item: item)
                    }
                    if template.items.contains(where: { !checkedItems.contains($0) }) {
                        Text("⚠️ 还有 \(template.items.count - checkedItems.count) 项未勾选")
                            .font(.system(size: DesignTokens.FontSize.body))
                            .foregroundStyle(.orange)
                            .padding(.top, 4)
                    } else if !template.items.isEmpty {
                        Text("✓ 全部勾选完成")
                            .font(.system(size: DesignTokens.FontSize.body))
                            .foregroundStyle(.green)
                            .padding(.top, 4)
                    }
                }
                .padding(DesignTokens.Spacing.small)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func templateCheckRow(item: String) -> some View {
        Button {
            if checkedItems.contains(item) {
                checkedItems.remove(item)
            } else {
                checkedItems.insert(item)
            }
        } label: {
            HStack {
                Image(systemName: checkedItems.contains(item) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checkedItems.contains(item) ? .green : .secondary)
                Text(item)
                    .font(.system(size: DesignTokens.FontSize.body))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    // MARK: - Clause ref picker

    private var clauseRefPicker: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("引用合同条款")
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.small) {
                    chip(title: "无", isSelected: selectedClauseRef == nil) {
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
                    Text(floorPlanMark == nil ? "在平面图上标位置(可选)" : "已标位置: \(floorPlanMark!.planName)")
                        .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let mark = floorPlanMark {
                        Text(String(format: "x=%.2f y=%.2f(点击修改)", mark.x, mark.y))
                            .font(.system(size: DesignTokens.FontSize.body))
                            .foregroundStyle(.secondary)
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
                    .accessibilityLabel("编辑第 \(idx + 1) 张照片")
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
        .accessibilityLabel("加照片")
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

    private func styleFor(_ deadline: Deadline) -> ButtonStyleKind {
        if deadline == primaryDeadline { return .primary }
        if deadline == .archive { return .tertiary }
        return .secondary
    }

    private var deadlineButtons: some View {
        VStack(spacing: DesignTokens.Spacing.small) {
            if let suggestedDeadline {
                Text("💡 语音里提到「\(suggestedDeadline.displayName)」,已预选")
                    .font(.system(size: DesignTokens.FontSize.body))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
            }
            deadlineButton(.today, style: styleFor(.today))
            deadlineButton(.threeDays, style: styleFor(.threeDays))
            deadlineButton(.thisWeek, style: styleFor(.thisWeek))
            deadlineButton(.archive, style: styleFor(.archive))
        }
    }

    private enum ButtonStyleKind {
        case primary, secondary, tertiary

        var backgroundColor: Color {
            switch self {
            case .primary: return Color.accentColor
            case .secondary: return Color.gray.opacity(0.3)
            case .tertiary: return Color.gray.opacity(0.15)
            }
        }

        var textColor: Color {
            switch self {
            case .primary: return .white
            case .secondary: return .primary
            case .tertiary: return .secondary
            }
        }

        var fontWeight: Font.Weight {
            self == .primary ? .bold : .semibold
        }
    }

    private func deadlineButton(_ deadline: Deadline, style: ButtonStyleKind) -> some View {
        Button {
            let result = DeadlineSheetResult(
                deadline: deadline,
                photos: images,
                siteTag: selectedSiteTag,
                isHazard: isHazard,
                templateName: selectedTemplate?.name,
                checkedItems: Array(checkedItems),
                contractClauseRef: selectedClauseRef,
                floorPlanRef: floorPlanMark?.planName,
                floorPlanX: floorPlanMark?.x,
                floorPlanY: floorPlanMark?.y
            )
            onCommit(result)
        } label: {
            Text(deadline.displayName + (deadline == primaryDeadline ? " (默认)" : ""))
                .font(.system(size: DesignTokens.FontSize.large, weight: style.fontWeight))
                .foregroundStyle(style.textColor)
                .frame(maxWidth: .infinity)
                .frame(height: DesignTokens.ButtonSize.minTap)
                .background(style.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
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
        locationLabel: "Willoughby, NSW"
    ) { result in
        print("Committed:", result)
    }
}
