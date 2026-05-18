//
//  FloorPlanMarkView.swift
//  SiteNote
//
//  在平面图上标位置。
//  交互:
//  - 轻点图片区域:放针
//  - 双指捏合:缩放(0.5× - 5×),放大了再点 = 精细定位
//  - 单指拖动:平移
//  - 双击:复位
//
//  坐标说明:存的是"图片内"的归一化 (0-1),不是 frame 归一化。
//  这样不同 frame 大小 / letterbox 情况下回显都对得齐。
//

import SwiftUI
import UIKit

struct FloorPlanMarkResult {
    let planName: String
    let siteTag: String?
    let x: Double
    let y: Double
}

/// 平面图显示几何。共享给 Mark / Lookup / Display 三处用,保证坐标口径一致。
enum FloorPlanGeometry {
    /// `.scaledToFit()` 后,图片在 frame 内的实际显示矩形(letterbox 居中)。
    static func displayRect(imageSize: CGSize, in frame: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              frame.width > 0, frame.height > 0 else { return .zero }
        let imgAspect = imageSize.width / imageSize.height
        let frameAspect = frame.width / frame.height
        if imgAspect > frameAspect {
            let h = frame.width / imgAspect
            return CGRect(x: 0, y: (frame.height - h) / 2, width: frame.width, height: h)
        } else {
            let w = frame.height * imgAspect
            return CGRect(x: (frame.width - w) / 2, y: 0, width: w, height: frame.height)
        }
    }
}

struct FloorPlanMarkView: View {
    let preferredSiteTag: String?
    /// 图钉颜色。调用方通常传 note 的第一个分类颜色,让用户看到的图钉=真实渲染颜色。
    var pinColor: Color = .red
    let onSave: (FloorPlanMarkResult) -> Void

    @Environment(\.dismiss) private var dismiss

    // 工地选择(只在 preferredSiteTag == nil 时用)
    @State private var userPickedSite: Bool = false
    @State private var chosenSite: String? = nil

    @State private var selectedPlan: FloorPlan?

    /// 图片坐标系下的归一化位置 (0-1)。
    @State private var markNormalized: CGPoint?

    @State private var currentImage: UIImage?

    // 缩放 / 平移
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    /// 实际生效的工地:外部固定优先,否则用用户在本页选的。
    private var effectiveSite: String? {
        preferredSiteTag ?? chosenSite
    }

    /// 是否需要先展示工地选择界面。
    private var needsSitePick: Bool {
        preferredSiteTag == nil && !userPickedSite
    }

    /// 所有"有平面图"的工地标签(含未分类)。nil 代表未分类,排最后。
    private var sitesWithPlans: [String?] {
        let all = FloorPlansStorage.load()
        let unique = Array(Set(all.map { $0.siteTag }))
        return unique.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case (nil, _): return false
            case (_, nil): return true
            case (let a?, let b?): return a < b
            }
        }
    }

    private var candidatePlans: [FloorPlan] {
        guard let s = effectiveSite else { return [] }
        return FloorPlansStorage.load(for: s)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if sitesWithPlans.isEmpty {
                    emptyStateNoPlansAtAll
                } else if needsSitePick {
                    sitePickerView
                } else if candidatePlans.isEmpty {
                    emptyStateNoPlansForSite
                } else {
                    if preferredSiteTag == nil {
                        chosenSiteBar
                    }
                    planPicker
                    Divider()
                    if let plan = selectedPlan {
                        markingArea(plan: plan)
                    } else {
                        Spacer()
                        Text("请选一个楼层开始标位置")
                            .foregroundStyle(.secondary)
                            .font(.system(size: DesignTokens.FontSize.body))
                        Spacer()
                    }
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if scale != 1.0 || offset != .zero {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { resetTransform() }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .accessibilityLabel(String(localized: "复位缩放"))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { commit() }
                        .disabled(selectedPlan == nil || markNormalized == nil)
                        .bold()
                }
            }
            .onChange(of: selectedPlan?.id) { _, _ in
                markNormalized = nil
                resetTransform()
                loadImage()
            }
        }
    }

    private var navigationTitleText: String {
        if let preferredSiteTag {
            return String(localized: "\(preferredSiteTag) · 标位置", locale: AppLanguageManager.currentLocale)
        }
        if needsSitePick {
            return String(localized: "选工地", locale: AppLanguageManager.currentLocale)
        }
        if let site = chosenSite {
            return String(localized: "\(site) · 标位置", locale: AppLanguageManager.currentLocale)
        }
        return String(localized: "平面图标位置", locale: AppLanguageManager.currentLocale)
    }

    // MARK: - 工地选择(仅当外部没传 preferredSiteTag)

    private var sitePickerView: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.medium) {
                VStack(spacing: 4) {
                    Image(systemName: "building.2")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("先选一个工地")
                        .font(.system(size: DesignTokens.FontSize.large, weight: .semibold))
                    Text("然后再选具体楼层")
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                VStack(spacing: DesignTokens.Spacing.small) {
                    ForEach(sitesWithPlans, id: \.self) { site in
                        Button {
                            chosenSite = site
                            userPickedSite = true
                            selectedPlan = nil
                            markNormalized = nil
                        } label: {
                            HStack {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(Color.accentColor)
                                Text(site ?? String(localized: "未分类", locale: AppLanguageManager.currentLocale))
                                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(FloorPlansStorage.load(for: site).count) 张")
                                    .font(.system(size: DesignTokens.FontSize.body))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer(minLength: 32)
            }
        }
    }

    /// 已选工地栏 + 换工地按钮。只在 preferredSiteTag == nil 时出现。
    private var chosenSiteBar: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(Color.accentColor)
            Text(chosenSite ?? String(localized: "未分类", locale: AppLanguageManager.currentLocale))
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
            Spacer()
            Button {
                userPickedSite = false
                chosenSite = nil
                selectedPlan = nil
                markNormalized = nil
                resetTransform()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.left.arrow.right")
                    Text("换工地")
                }
                .font(.system(size: DesignTokens.FontSize.body))
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .padding(.vertical, DesignTokens.Spacing.small)
        .background(Color.gray.opacity(0.08))
    }

    // MARK: - 空态

    private var emptyStateNoPlansAtAll: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "map")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("还没有工地平面图")
                .font(.system(size: DesignTokens.FontSize.large, weight: .semibold))
            Text("请先在「设置 → 工地资源 → 工地平面图」上传。")
                .font(.system(size: DesignTokens.FontSize.body))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    private var emptyStateNoPlansForSite: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "map")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("\(effectiveSite ?? String(localized: "未分类", locale: AppLanguageManager.currentLocale)) 还没有楼层")
                .font(.system(size: DesignTokens.FontSize.large, weight: .semibold))
            Text("请先在「设置 → 工地资源 → 工地平面图」为此工地添加一个楼层。")
                .font(.system(size: DesignTokens.FontSize.body))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if preferredSiteTag == nil {
                Button("换工地") {
                    userPickedSite = false
                    chosenSite = nil
                }
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                .padding(.top, 8)
            }
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    private var planPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.small) {
                ForEach(candidatePlans) { plan in
                    Button {
                        selectedPlan = plan
                    } label: {
                        Text(plan.name)
                            .font(.system(
                                size: DesignTokens.FontSize.body,
                                weight: selectedPlan?.id == plan.id ? .bold : .regular
                            ))
                            .foregroundStyle(selectedPlan?.id == plan.id ? .white : .primary)
                            .padding(.horizontal, DesignTokens.Spacing.medium)
                            .padding(.vertical, DesignTokens.Spacing.small)
                            .background(selectedPlan?.id == plan.id ? Color.accentColor : Color.gray.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - 可缩放 / 平移的标位置区

    @ViewBuilder
    private func markingArea(plan: FloorPlan) -> some View {
        GeometryReader { geo in
            ZStack {
                Color.gray.opacity(0.08)

                if let uiImage = currentImage {
                    let imageRect = FloorPlanGeometry.displayRect(
                        imageSize: uiImage.size,
                        in: geo.size
                    )

                    // 关键:tap 挂在 Image 自身上,location 就是图片 frame 内坐标,
                    // 和 imageRect 同坐标系,不受外层 scaleEffect 影响。
                    ZStack {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { location in
                                if let n = normalizePoint(location, in: imageRect) {
                                    markNormalized = n
                                }
                            }

                        if let norm = markNormalized {
                            pin()
                                .scaleEffect(1.0 / max(scale, 0.1))
                                .position(
                                    x: imageRect.minX + imageRect.width * norm.x,
                                    y: imageRect.minY + imageRect.height * norm.y
                                )
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(pinchGesture.simultaneously(with: panGesture))
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.25)) { resetTransform() }
                    }
                } else {
                    Text("无法加载平面图")
                        .foregroundStyle(.red)
                }
            }
            .clipped()
        }
        .overlay(alignment: .bottom) {
            Text("轻点放针 · 双指缩放放大后再点精准 · 双击复位")
                .font(.system(size: DesignTokens.FontSize.body))
                .foregroundStyle(.secondary)
                .padding(8)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 12)
        }
    }

    private func pin() -> some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 22))
            .foregroundStyle(Color.white, pinColor)
            .shadow(radius: 2)
    }

    // MARK: - 手势

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(0.5, min(lastScale * value, 5.0))
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 10)
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

    // MARK: - 工具方法

    private func loadImage() {
        guard let plan = selectedPlan,
              let url = FloorPlansStorage.absoluteURL(forRelative: plan.imageRelativePath),
              let img = UIImage(contentsOfFile: url.path) else {
            currentImage = nil
            return
        }
        currentImage = img
    }

    private func normalizePoint(_ p: CGPoint, in imageRect: CGRect) -> CGPoint? {
        guard imageRect.width > 0, imageRect.height > 0 else { return nil }
        let x = (p.x - imageRect.minX) / imageRect.width
        let y = (p.y - imageRect.minY) / imageRect.height
        if x < -0.05 || x > 1.05 || y < -0.05 || y > 1.05 { return nil }
        return CGPoint(x: min(1, max(0, x)), y: min(1, max(0, y)))
    }

    private func resetTransform() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }

    private func commit() {
        guard let plan = selectedPlan, let n = markNormalized else { return }
        onSave(FloorPlanMarkResult(
            planName: plan.name,
            siteTag: plan.siteTag,
            x: Double(n.x),
            y: Double(n.y)
        ))
        dismiss()
    }
}

// MARK: - 详情页只读展示

struct FloorPlanDisplayView: View {
    let plan: FloorPlan
    let x: Double
    let y: Double
    /// 图钉颜色。默认红。调用方通常用 note 的第一个分类颜色。
    var pinColor: Color = .red

    var body: some View {
        GeometryReader { geo in
            if let url = FloorPlansStorage.absoluteURL(forRelative: plan.imageRelativePath),
               let uiImage = UIImage(contentsOfFile: url.path) {
                let imageRect = FloorPlanGeometry.displayRect(
                    imageSize: uiImage.size,
                    in: geo.size
                )
                ZStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.white, pinColor)
                        .shadow(radius: 2)
                        .position(
                            x: imageRect.minX + imageRect.width * CGFloat(x),
                            y: imageRect.minY + imageRect.height * CGFloat(y)
                        )
                }
            }
        }
    }
}
