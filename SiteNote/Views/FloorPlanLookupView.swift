//
//  FloorPlanLookupView.swift
//  SiteNote
//
//  反向查找:选工地 → 选楼层 → 看图上所有 note 的 pin。
//
//  手势:
//  - 双指 pinch 缩放图纸(0.5× - 5×)
//  - 单指拖动平移
//  - 双击复位
//  - 点 pin 弹 sheet 显示完整 note 详情页
//

import SwiftUI
import SwiftData

struct FloorPlanLookupView: View {
    /// 当从"具体工地"context 进入时锁定该 site —— 隐藏 site 选择条。
    /// `nil` 时保持原 free-select 行为(从设置 / 总览入口进入)。
    let lockedSite: String?

    init(lockedSite: String? = nil) {
        self.lockedSite = lockedSite
    }

    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.createdAt,
        order: .reverse
    ) private var allNotes: [Note]

    @State private var siteTags: [String] = SiteTagsStorage.load()
    @State private var selectedSite: String?
    @State private var selectedPlan: FloorPlan?

    // 缩放 / 平移状态
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // 点 pin 后的选中 note —— 非空即弹 sheet
    @State private var selectedNote: Note?

    private var plansForSelectedSite: [FloorPlan] {
        FloorPlansStorage.load(for: selectedSite)
    }

    private var notesOnSelectedPlan: [Note] {
        guard let plan = selectedPlan else { return [] }
        return allNotes.filter { note in
            note.floorPlanRef == plan.name
                && note.floorPlanX != nil
                && note.floorPlanY != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if lockedSite != nil {
                // 锁定 site:跳过 siteTags.isEmpty 检查 + 隐藏 siteSelector
                if plansForSelectedSite.isEmpty {
                    Spacer()
                    Text(selectedSite.map { String(localized: "\($0) 还没有楼层", locale: AppLanguageManager.currentLocale) } ?? String(localized: "暂无楼层", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    planSelector
                    Divider()
                    if let plan = selectedPlan {
                        planCanvas(plan: plan)
                    }
                }
            } else if siteTags.isEmpty {
                noSitesState
            } else {
                siteSelector
                Divider()
                if plansForSelectedSite.isEmpty {
                    Spacer()
                    Text(selectedSite.map { String(localized: "\($0) 还没有楼层", locale: AppLanguageManager.currentLocale) } ?? String(localized: "选一个工地", locale: AppLanguageManager.currentLocale))
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    planSelector
                    Divider()
                    if let plan = selectedPlan {
                        planCanvas(plan: plan)
                    }
                }
            }
        }
        .navigationTitle(lockedSite.map { String(localized: "\($0) 平面图", locale: AppLanguageManager.currentLocale) } ?? String(localized: "平面图查看", locale: AppLanguageManager.currentLocale))
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .toolbar {
            if scale != 1.0 || offset != .zero {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        resetTransform()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel(String(localized: "复位缩放"))
                }
            }
        }
        .onAppear {
            siteTags = SiteTagsStorage.load()
            if let locked = lockedSite {
                selectedSite = locked
            } else if selectedSite == nil {
                selectedSite = siteTags.first
            }
            syncSelection()
        }
        .onChange(of: selectedSite) { _, _ in
            syncSelection()
            resetTransform()
        }
        .onChange(of: selectedPlan?.id) { _, _ in
            resetTransform()
        }
        .sheet(item: $selectedNote) { note in
            NavigationStack {
                NoteDetailView(note: note)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { selectedNote = nil }
                        }
                    }
            }
        }
    }

    // MARK: - Empty & Selectors

    private var noSitesState: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "building.2")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("还没有工地")
                .font(.system(size: DesignTokens.FontSize.large, weight: .semibold))
            Text("请先到「设置 → 工地标签」建一个工地。")
                .font(.system(size: DesignTokens.FontSize.body))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    private var siteSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.small) {
                ForEach(siteTags, id: \.self) { site in
                    chip(title: site, isSelected: selectedSite == site) {
                        selectedSite = site
                    }
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
    }

    private var planSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.small) {
                ForEach(plansForSelectedSite) { plan in
                    chip(title: plan.name, isSelected: selectedPlan?.id == plan.id) {
                        selectedPlan = plan
                    }
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
    }

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

    // MARK: - 可缩放平移的图纸 + pin

    @ViewBuilder
    private func planCanvas(plan: FloorPlan) -> some View {
        GeometryReader { geo in
            ZStack {
                Color.gray.opacity(0.08)
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.25)) { resetTransform() }
                    }

                if let url = FloorPlansStorage.absoluteURL(forRelative: plan.imageRelativePath),
                   let uiImage = UIImage(contentsOfFile: url.path) {
                    let imageRect = FloorPlanGeometry.displayRect(
                        imageSize: uiImage.size,
                        in: geo.size
                    )
                    // 把图和 pin 包一起,同步缩放平移
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)

                        ForEach(notesOnSelectedPlan) { note in
                            if let nx = note.floorPlanX, let ny = note.floorPlanY {
                                pinFor(note: note)
                                    .scaleEffect(1.0 / max(scale, 0.1))
                                    .position(
                                        x: imageRect.minX + imageRect.width * CGFloat(nx),
                                        y: imageRect.minY + imageRect.height * CGFloat(ny)
                                    )
                                    .onTapGesture {
                                        selectedNote = note
                                    }
                            }
                        }
                    }
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        magnificationGesture.simultaneously(with: panGesture)
                    )
                } else {
                    Text("无法加载图片")
                        .foregroundStyle(.red)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Text("\(notesOnSelectedPlan.count) 个图钉 · 双指缩放 · 拖动平移 · 双击复位")
                .font(.system(size: DesignTokens.FontSize.body))
                .foregroundStyle(.secondary)
                .padding(8)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 12)
        }
    }

    /// 图钉(缩小到 18pt,过大挡视野)。颜色按状态区分。
    private func pinFor(note: Note) -> some View {
        let (fg, bg) = pinColor(for: note)
        return Image(systemName: note.isHazard ? "exclamationmark.triangle.fill" : "mappin.circle.fill")
            .font(.system(size: 18))
            .foregroundStyle(fg, bg)
            .shadow(radius: 1.5)
            // 扩大点击区域但视觉不变
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }

    /// 图钉色优先级:
    /// 1. 已完成 → 灰
    /// 2. 隐患 → 红
    /// 3. 有分类 → 用第一个分类的颜色(按工地查)
    /// 4. 默认 → 蓝
    private func pinColor(for note: Note) -> (Color, Color) {
        if note.isDone { return (.white, .gray) }
        if note.isHazard { return (.white, .red) }
        if let firstSub = note.otherTags.first {
            let color = SubTagsStorage.color(name: firstSub)
            return (.white, color)
        }
        return (.white, .blue)
    }

    // MARK: - 缩放 / 平移手势

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(0.5, min(lastScale * value, 5.0))
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func resetTransform() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }

    private func syncSelection() {
        if let current = selectedPlan, !plansForSelectedSite.contains(where: { $0.id == current.id }) {
            selectedPlan = plansForSelectedSite.first
        } else if selectedPlan == nil {
            selectedPlan = plansForSelectedSite.first
        }
    }
}
