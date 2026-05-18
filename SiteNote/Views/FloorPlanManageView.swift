//
//  FloorPlanManageView.swift
//  SiteNote
//
//  设置 → 工地平面图:按工地分组展示,每个工地下可添加多个楼层。
//  支持从相册导入图片或从 PDF 文件选一页作为楼层图。
//

import SwiftUI
import SwiftData
import PhotosUI
import PDFKit
import UIKit
import UniformTypeIdentifiers

struct FloorPlanManageView: View {
    /// 锁定工地。非 nil 时:只显示该 site 的楼层 + 上传按钮直接 attach 到此 site,
    /// 不再弹"选哪个工地"的 Menu。从「工地详情」入口进来必传;
    /// nil = 老的全局模式(总览/Settings 顶层入口用)。
    let lockedSite: String?

    init(lockedSite: String? = nil) {
        self.lockedSite = lockedSite
    }

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Note> { $0.deletedAt == nil }) private var allNotesAllRoles: [Note]

    /// v1.5:只显示当前角色的 note(historical nil → PM)。
    private var allNotes: [Note] {
        allNotesAllRoles.filter { $0.belongsToCurrentRole }
    }
    @State private var plans: [FloorPlan] = FloorPlansStorage.load()
    @State private var siteTags: [String] = SiteTagsStorage.load()
    @State private var pendingDelete: PendingDelete?

    private struct PendingDelete: Identifiable {
        let id = UUID()
        let plan: FloorPlan
        let referencingCount: Int
    }

    /// 当前正在上传的目标工地。用 `.sheet(item:)` 驱动 sheet,
    /// 保证 sheet 创建时一定拿到正确的工地名(避免原 isPresented + 单独 state 的时序竞态)。
    @State private var uploadTarget: UploadTarget?

    /// 分组后的一节:一个工地名(nil = 未分类)+ 它名下的平面图。
    /// 用 struct 而不是 tuple,方便 `ForEach` 走 KeyPath id。
    private struct SiteGroup: Identifiable {
        let site: String?
        let plans: [FloorPlan]
        var id: String { site ?? "__unassigned__" }
    }

    /// 所有带有楼层的工地 + "未分类"。
    /// 必须从 `@State plans` 派生,直接读 UserDefaults 的版本不会随上传后的 `plans = load()` 刷新,
    /// 因为 SwiftUI 不知道这个计算属性依赖存储。
    /// lockedSite 模式下:只返回该工地的一段,屏蔽"未分类"和其它工地。
    private var groupedSections: [SiteGroup] {
        let grouped = Dictionary(grouping: plans, by: { $0.siteTag })
        if let locked = lockedSite {
            let onlyThis = grouped[locked] ?? []
            return onlyThis.isEmpty ? [] : [SiteGroup(site: locked, plans: onlyThis)]
        }
        var result: [SiteGroup] = []
        for site in siteTags {
            if let group = grouped[site], !group.isEmpty {
                result.append(SiteGroup(site: site, plans: group))
            }
        }
        if let unassigned = grouped[nil], !unassigned.isEmpty {
            result.append(SiteGroup(site: nil, plans: unassigned))
        }
        return result
    }

    var body: some View {
        Form {
            if groupedSections.isEmpty {
                Section {
                    if lockedSite != nil {
                        Text("这个工地还没有上传平面图。")
                            .font(.system(size: DesignTokens.FontSize.body))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("还没有上传任何平面图。")
                            .font(.system(size: DesignTokens.FontSize.body))
                            .foregroundStyle(.secondary)
                        Text("先在设置「工地标签」里建一个工地,再到这里上传该工地的楼层图纸。")
                            .font(.system(size: DesignTokens.FontSize.body))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(groupedSections) { group in
                    siteSection(site: group.site, plans: group.plans)
                }
            }

            Section {
                if let locked = lockedSite {
                    // 工地内入口:直接 attach 到当前 site,免 picker。
                    Button {
                        uploadTarget = UploadTarget(siteTag: locked)
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("上传新平面图")
                                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                } else if siteTags.isEmpty {
                    Text("请先到「设置 → 工地资源 → 工地标签」建一个工地,然后才能上传它的平面图。")
                        .font(.system(size: DesignTokens.FontSize.body))
                        .foregroundStyle(Ink.red)
                } else {
                    Menu {
                        ForEach(siteTags, id: \.self) { site in
                            Button(site) {
                                uploadTarget = UploadTarget(siteTag: site)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("上传新平面图")
                                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }
            } footer: {
                Text("支持图片和 PDF。PDF 会让你选其中一页作为楼层图。")
                    .font(.system(size: DesignTokens.FontSize.body))
            }
        }
        .navigationTitle(lockedSite.map { String(localized: "\($0) 平面图", locale: AppLanguageManager.currentLocale) } ?? String(localized: "工地平面图", locale: AppLanguageManager.currentLocale))
        .navigationBarTitleDisplayMode(.inline)
        .industrialForm()
        .onAppear {
            plans = FloorPlansStorage.load()
            siteTags = SiteTagsStorage.load()
        }
        .alert(
            String(localized: "删除平面图?", locale: AppLanguageManager.currentLocale),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { item in
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("继续删除", role: .destructive) {
                clearReferences(to: item.plan)
                FloorPlansStorage.remove(id: item.plan.id)
                plans = FloorPlansStorage.load()
                pendingDelete = nil
            }
        } message: { item in
            Text("有 \(item.referencingCount) 条速记引用了「\(item.plan.name)」。继续删除会清除这些速记的图纸定位(其他内容保留)。")
        }
        .sheet(item: $uploadTarget) { target in
            UploadFloorSheet(
                siteTag: target.siteTag,
                onCancel: { uploadTarget = nil },
                onPicked: { image, name in
                    FloorPlansStorage.add(image: image, name: name, siteTag: target.siteTag)
                    plans = FloorPlansStorage.load()
                    uploadTarget = nil
                }
            )
        }
    }

    /// `.sheet(item:)` 用的 Identifiable 包装。保证 sheet 初始化时就拿到工地名,
    /// 不会被"先设 showingUploadSheet 再改 selectedSiteForUpload"的时序错漏。
    struct UploadTarget: Identifiable {
        let id = UUID()
        let siteTag: String
    }

    @ViewBuilder
    private func siteSection(site: String?, plans: [FloorPlan]) -> some View {
        let header = site ?? String(localized: "未分类", locale: AppLanguageManager.currentLocale)
        Section {
            ForEach(plans) { plan in
                HStack {
                    if let url = FloorPlansStorage.absoluteURL(forRelative: plan.imageRelativePath),
                       let img = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(plan.name)
                        .font(.system(size: DesignTokens.FontSize.body))
                    Spacer()
                }
            }
            .onDelete { offsets in
                guard let idx = offsets.first else { return }
                let plan = plans[idx]
                // P2 #187:引用计数按 ID 优先(老数据没 ID 走 name fallback)
                let refs = allNotes.filter {
                    $0.floorPlanID == plan.id || ($0.floorPlanID == nil && $0.floorPlanRef == plan.name)
                }.count
                if refs > 0 {
                    pendingDelete = PendingDelete(plan: plan, referencingCount: refs)
                } else {
                    FloorPlansStorage.remove(id: plan.id)
                    self.plans = FloorPlansStorage.load()
                }
            }
        } header: {
            HStack {
                Image(systemName: site == nil ? "questionmark.folder" : "building.2")
                Text(header)
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
            }
        }
    }

    /// 删图前清掉所有引用此图的 note 的 floorPlanRef + ID + X/Y,避免 dangling 引用。
    /// P2 #187:同时按 ID 和 name 匹配(老数据没 ID)。
    private func clearReferences(to plan: FloorPlan) {
        for note in allNotes where note.floorPlanID == plan.id || (note.floorPlanID == nil && note.floorPlanRef == plan.name) {
            note.floorPlanRef = nil
            note.floorPlanID = nil
            note.floorPlanX = nil
            note.floorPlanY = nil
        }
        try? modelContext.save()
    }

}

// MARK: - Upload sheet

/// 上传楼层 sheet。支持两种来源:相册图片 或 PDF 中的某一页。
struct UploadFloorSheet: View {
    let siteTag: String?
    let onCancel: () -> Void
    let onPicked: (UIImage, String) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var floorName: String = ""

    @State private var showsPhotosPicker: Bool = false
    @State private var showsPDFImporter: Bool = false
    @State private var loadedPDF: PDFDocumentRef?
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                    // 工地
                    VStack(alignment: .leading, spacing: 6) {
                        Text("工地")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(siteTag ?? String(localized: "未分类", locale: AppLanguageManager.currentLocale))
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                            .padding(DesignTokens.Spacing.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // 楼层名
                    VStack(alignment: .leading, spacing: 6) {
                        Text("楼层名")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("如 3 楼、地下室、东区机房", text: $floorName)
                            .font(.system(size: DesignTokens.FontSize.body))
                            .padding(DesignTokens.Spacing.medium)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // 来源二选一(都是纯 Button,避免 Form 行吞 tap)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("来源")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: DesignTokens.Spacing.small) {
                            Button {
                                showsPhotosPicker = true
                            } label: {
                                sourceButton(
                                    icon: "photo.on.rectangle",
                                    title: "相册选图",
                                    tint: .blue
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                showsPDFImporter = true
                            } label: {
                                sourceButton(
                                    icon: "doc.richtext",
                                    title: "PDF 选页",
                                    tint: .purple
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        Text("PDF 选完会跳出页面预览,点哪一页就把那一页转成图片。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    // 预览
                    if let img = pickedImage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("预览")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: 240)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green, .white)
                                        .font(.system(size: 26))
                                        .padding(8)
                                }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("添加楼层")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let img = pickedImage {
                            let name = floorName.trimmingCharacters(in: .whitespacesAndNewlines)
                            onPicked(img, name.isEmpty ? String(localized: "未命名楼层", locale: AppLanguageManager.currentLocale) : name)
                        }
                    }
                    .disabled(pickedImage == nil || floorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .bold()
                }
            }
            .photosPicker(isPresented: $showsPhotosPicker, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, newItem in
                Task {
                    if let item = newItem,
                       let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        pickedImage = img
                    }
                }
            }
            .fileImporter(
                isPresented: $showsPDFImporter,
                allowedContentTypes: [UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                handlePDFImport(result)
            }
            .sheet(item: $loadedPDF) { ref in
                PDFPageSelectorSheet(document: ref.document) { image in
                    pickedImage = image
                }
            }
            .alert("导入出错", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("知道了") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func sourceButton(icon: String, title: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
            Text(title)
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func handlePDFImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importError = String(localized: "系统拒绝访问该文件。", locale: AppLanguageManager.currentLocale)
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let data = try? Data(contentsOf: url) else {
                importError = String(localized: "无法读取 PDF 文件。", locale: AppLanguageManager.currentLocale)
                return
            }
            guard let doc = PDFDocument(data: data), doc.pageCount > 0 else {
                importError = String(localized: "PDF 无效或没有页面。", locale: AppLanguageManager.currentLocale)
                return
            }
            loadedPDF = PDFDocumentRef(document: doc)
        case .failure(let err):
            importError = err.localizedDescription
        }
    }
}

/// PDFDocument 不是 Identifiable,包一层给 `.sheet(item:)` 用。
private struct PDFDocumentRef: Identifiable {
    let id: UUID = UUID()
    let document: PDFDocument
}

// MARK: - PDF 页面选择器

/// 把 PDF 所有页渲染成缩略图网格,用户点一页 → 回调 UIImage。
struct PDFPageSelectorSheet: View {
    let document: PDFDocument
    let onPick: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectingIndex: Int?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<document.pageCount, id: \.self) { idx in
                        pageTile(index: idx)
                    }
                }
                .padding()
            }
            .navigationTitle("选一页作为平面图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .overlay {
                if selectingIndex != nil {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().scaleEffect(1.4).tint(.white)
                            Text("正在转换页面…")
                                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(DesignTokens.Spacing.large)
                        .background(Color.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pageTile(index: Int) -> some View {
        if let page = document.page(at: index) {
            Button {
                selectPage(index: index, page: page)
            } label: {
                VStack(spacing: 6) {
                    ZStack {
                        Color.white
                        Image(uiImage: thumbnail(page: page, size: CGSize(width: 260, height: 360)))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                    .frame(height: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.gray.opacity(0.4), lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text("第 \(index + 1) 页")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .disabled(selectingIndex != nil)
        }
    }

    /// 缩略图(小尺寸,快速渲染)。
    private func thumbnail(page: PDFPage, size: CGSize) -> UIImage {
        page.thumbnail(of: size, for: .mediaBox)
    }

    /// 用户点页 → 高分辨率渲染成图 → 回调 + 关闭。
    private func selectPage(index: Int, page: PDFPage) {
        selectingIndex = index
        Task { @MainActor in
            // 让 overlay 出现再去干重活(否则闪一下)
            try? await Task.sleep(nanoseconds: 80_000_000)
            let image = highResRender(page: page)
            onPick(image)
            selectingIndex = nil
            dismiss()
        }
    }

    /// 高分辨率渲染:3× 缩放,长边封顶 2400px。
    /// F7 (R4-P2-17):从 4000 降到 2400——A0 大图 4000² × 4 byte/px ≈ 64 MB UIImage,
    /// 老 iPhone 后台容易 OOM。2400² ≈ 23 MB,清晰度对楼层图标记+导出 PDF 仍够用。
    private func highResRender(page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let longer = max(bounds.width, bounds.height)
        let maxDim: CGFloat = 2400
        let scale: CGFloat = min(3.0, maxDim / longer)
        let targetSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
        return page.thumbnail(of: targetSize, for: .mediaBox)
    }
}
