//
//  SiteTeamSiteEditorView.swift
//  SiteNote
//
//  v1.5 PM 角色专用「工地」管理 — 简化版,只暴露 3 个字段:
//   1. 工地名(必填,= SitePreset.siteTag)
//   2. 地址(可选,= SitePreset.address)
//   3. 平面图(复用 FloorPlanManageView(lockedSite:))
//
//  数据 model 和 storage 与 Engineer 版完全共用(SitePreset @Model /
//  SitePresetStorage),只是 PM 看到的字段子集更小。Engineer 端额外字段
//  (projectName / projectNo / clientName / defaultAttn / defaultInspectionType /
//  linkedContactIDs 等)在 PM 创建/编辑时保留原值(初次默认空),不破坏 Engineer 路径。
//
//  视觉与 SiteTeamSettingsRoot 一致:Ink palette + 白底卡片 + 描边,navRow / 卡片容器
//  的私有 builder 在本文件单独复刻一份(SwiftUI private helper 不能跨 file 复用)。
//

import SwiftUI
import SwiftData

struct SiteTeamSiteEditorView: View {
    /// 当前工地预设列表(只看未软删的)。@State 触发刷新。
    @State private var presets: [SitePreset] = SitePresetStorage.load()

    /// 平面图全量 — 用来给每张卡片右下角显示 floor plan 数量 badge。
    /// SitePresetStorage.load() 之后再读一次,保持与列表同步。
    @State private var allFloorPlans: [FloorPlan] = FloorPlansStorage.load()

    /// 进入编辑 sheet 的目标(新建 / 编辑某条)。
    @State private var editing: SiteTeamSiteEditingTarget? = nil

    /// 删除确认 dialog 的目标。
    @State private var pendingDelete: SitePreset? = nil

    /// 通用 alert(超上限等)。
    @State private var alertMessage: String? = nil

    private var locale: Locale { AppLanguageManager.currentLocale }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if presets.isEmpty {
                    emptyState
                } else {
                    ForEach(presets) { preset in
                        siteCard(preset)
                    }
                }
                footerNote
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "工地", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard presets.count < SitePresetStorage.maxItems else {
                        alertMessage = String(
                            localized: "已达 \(SitePresetStorage.maxItems) 条上限,删一些再加。",
                            locale: locale
                        )
                        return
                    }
                    editing = .new
                } label: {
                    Label(String(localized: "新建", locale: locale), systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
        .sheet(item: $editing) { target in
            SiteTeamSiteEditSheet(
                target: target,
                onSave: { draft in handleSave(draft, target: target) }
            )
        }
        .confirmationDialog(
            String(localized: "删除工地?", locale: locale),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button(String(localized: "删除", locale: locale), role: .destructive) {
                remove(item)
                pendingDelete = nil
            }
            Button(String(localized: "取消", locale: locale), role: .cancel) {
                pendingDelete = nil
            }
        } message: { item in
            Text(String(
                localized: "确认删除「\(item.siteTag)」?平面图保留在「我的平面图」里,但与该工地的关联会解除。",
                locale: locale
            ))
        }
        .alert(
            String(localized: "无法继续", locale: locale),
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button(String(localized: "知道了", locale: locale), role: .cancel) {
                alertMessage = nil
            }
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear {
            reload()
        }
    }

    // MARK: - 列表态:卡片

    /// 单个工地卡:工地名 + 地址副标 + 右侧平面图数量 badge,整张可点。
    @ViewBuilder
    private func siteCard(_ preset: SitePreset) -> some View {
        Button {
            editing = .edit(preset)
        } label: {
            HStack(spacing: 12) {
                iconBox(systemName: "building.2")

                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.siteTag.isEmpty
                         ? String(localized: "(未命名工地)", locale: locale)
                         : preset.siteTag)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                        .lineLimit(1)
                    if !preset.address.isEmpty {
                        Text(preset.address)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.fgDim)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                let count = floorPlanCount(for: preset.siteTag)
                if count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "map")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(count)")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Ink.fg2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Ink.line.opacity(0.6))
                    )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.dim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Ink.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Ink.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = preset
            } label: {
                Label(String(localized: "删除", locale: locale), systemImage: "trash")
            }
        }
    }

    /// 空态卡 — 同样白底圆角描边,引导先建一个。
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                iconBox(systemName: "building.2")
                Text(String(localized: "还没有工地", locale: locale))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Ink.fg)
            }
            Text(String(localized: "点右上角「+ 新建」加一个工地。每条速记可以挂到工地下,导 PDF 时按工地筛。", locale: locale))
                .font(.system(size: 12))
                .foregroundStyle(Ink.fgDim)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Ink.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Ink.line, lineWidth: 1)
        )
    }

    /// 底部提示。
    private var footerNote: some View {
        Text(String(
            localized: "工地用来分类速记和平面图,只 3 个字段:名字、地址、图纸。",
            locale: locale
        ))
        .font(.system(size: 11))
        .foregroundStyle(Ink.fgDim)
        .padding(.horizontal, 4)
        .lineSpacing(2)
    }

    // MARK: - Helpers

    /// 行首小图标方块 — 与 SiteTeamSettingsRoot 视觉一致(灰描边 + 黑 icon)。
    private func iconBox(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Ink.fg)
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Ink.line2, lineWidth: 1)
            )
    }

    private func floorPlanCount(for siteTag: String) -> Int {
        guard !siteTag.isEmpty else { return 0 }
        return allFloorPlans.filter { $0.siteTag == siteTag }.count
    }

    private func reload() {
        presets = SitePresetStorage.load()
        allFloorPlans = FloorPlansStorage.load()
    }

    // MARK: - Actions

    private func remove(_ preset: SitePreset) {
        SitePresetStorage.remove(id: preset.id)
        // 同步从 SiteTagsStorage 删,避免下次 syncFromSiteTagsStorage 复活孤儿。
        // Note.siteTag 历史引用不动 — 那是预期的(报告会归到原工地名)。
        if !preset.siteTag.isEmpty {
            _ = SiteTagsStorage.remove(preset.siteTag)
        }
        reload()
    }

    @discardableResult
    private func handleSave(_ draft: SitePreset, target: SiteTeamSiteEditingTarget) -> Bool {
        switch target {
        case .new:
            guard presets.count < SitePresetStorage.maxItems else {
                alertMessage = String(
                    localized: "已达 \(SitePresetStorage.maxItems) 条上限,删一些再加。",
                    locale: locale
                )
                return false
            }
            if SitePresetStorage.add(draft) == nil {
                alertMessage = String(localized: "保存失败:工地名不能为空。", locale: locale)
                return false
            }
            // 写一份 SiteTagsStorage,让 autocomplete / 历史 picker 立刻看到。
            SiteTagsStorage.add(draft.siteTag.trimmingCharacters(in: .whitespacesAndNewlines))
        case .edit:
            if !SitePresetStorage.update(draft) {
                alertMessage = String(localized: "保存失败:找不到原条目。", locale: locale)
                return false
            }
        }
        reload()
        editing = nil
        return true
    }
}

// MARK: - 编辑目标

/// PM 简化编辑流的目标 — 与 Engineer 端 SitePresetEditingTarget 独立,避免互相耦合。
enum SiteTeamSiteEditingTarget: Identifiable {
    case new
    case edit(SitePreset)

    var id: String {
        switch self {
        case .new: return "pm.new"
        case .edit(let p): return "pm.edit.\(p.id.uuidString)"
        }
    }

    /// 拿到初始 entity 用来填字段。新建时返回一个临时空 SitePreset(不会 insert)。
    var initial: SitePreset {
        switch self {
        case .new: return SitePreset()
        case .edit(let p): return p
        }
    }
}

// MARK: - 编辑 sheet

/// PM 角色专用的简化编辑 sheet。
/// 只 3 个字段:工地名(siteTag)/ 地址(address)/ 平面图(走 FloorPlanManageView(lockedSite:))。
/// 其他 SitePreset 字段保留原值,save 时直接回写(避免清空 Engineer 已填好的项目信息 / 联系人)。
private struct SiteTeamSiteEditSheet: View {
    let target: SiteTeamSiteEditingTarget
    let onSave: (SitePreset) -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var siteTag: String
    @State private var address: String
    @State private var errorMessage: String?

    /// 跟踪保存状态 — 与 SitePresetEditorView 同款 R6#4 修:Cancel 时清掉
    /// FloorPlanManageView.onAppear 提前写入的 orphan tag。
    @State private var hasSavedSuccessfully: Bool = false

    private var locale: Locale { AppLanguageManager.currentLocale }

    init(target: SiteTeamSiteEditingTarget, onSave: @escaping (SitePreset) -> Bool) {
        self.target = target
        self.onSave = onSave
        let initial = target.initial
        _siteTag = State(initialValue: initial.siteTag)
        _address = State(initialValue: initial.address)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    nameSection
                    addressSection
                    floorPlansSection
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.red)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Ink.bg.ignoresSafeArea())
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "取消", locale: locale)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "保存", locale: locale)) {
                        attemptSave()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .disabled(!canSave)
                }
            }
            .onDisappear {
                // R6#4 同款:新建模式 Cancel 时清掉 orphan tag(FloorPlan 入口的副作用)。
                if case .new = target, !hasSavedSuccessfully {
                    let leaked = effectiveSiteTag
                    if !leaked.isEmpty, SitePresetStorage.find(siteTag: leaked) == nil {
                        _ = SiteTagsStorage.remove(leaked)
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        groupBlock(
            header: String(localized: "工地名", locale: locale),
            footer: String(localized: "必填。例如「ABC 工地」「希尔顿翻新」「华联仓库」。", locale: locale)
        ) {
            cardContainer {
                fieldRow(
                    placeholder: String(localized: "如 ABC 工地", locale: locale),
                    text: $siteTag,
                    capitalization: .words
                )
            }
        }
    }

    private var addressSection: some View {
        groupBlock(
            header: String(localized: "地址", locale: locale),
            footer: String(localized: "可选。输入时会自动联想真实地址,选一条会自动填详细字段。", locale: locale)
        ) {
            cardContainer {
                // 用跟 Engineer 同款的 MKLocalSearchCompletion 自动补全 — 不再是普通 TextField。
                AddressAutocompleteField(
                    text: $address,
                    placeholder: LocalizedStringKey(
                        String(localized: "搜地址,例 123 Sample St Sydney", locale: locale)
                    )
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    /// 平面图段 — 复用 Engineer 端同款 FloorPlanManageView(lockedSite:) 入口。
    /// 工地名空时 disable 入口(还没法 attach 到合法 site)。
    private var floorPlansSection: some View {
        groupBlock(
            header: String(localized: "平面图", locale: locale),
            footer: String(localized: "在图上标位置比 GPS 精确 10 倍。支持照片或 PDF 选页。", locale: locale)
        ) {
            cardContainer {
                if effectiveSiteTag.isEmpty {
                    HStack(spacing: 12) {
                        iconBox(systemName: "map")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "平面图", locale: locale))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Ink.fgDim)
                            Text(String(localized: "先填工地名再上传图纸", locale: locale))
                                .font(.system(size: 11))
                                .foregroundStyle(Ink.fgDim)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                } else {
                    NavigationLink {
                        FloorPlanManageView(lockedSite: effectiveSiteTag)
                            .onAppear {
                                // 新建模式 SitePreset 还没存,先把 tag 写 SiteTagsStorage,
                                // 否则上传完图纸 = 孤儿。.onDisappear 里如果 Cancel 会清掉。
                                SiteTagsStorage.add(effectiveSiteTag)
                            }
                    } label: {
                        HStack(spacing: 12) {
                            iconBox(systemName: "map")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "管理平面图", locale: locale))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Ink.fg)
                                Text(floorPlanSubtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Ink.fgDim)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Ink.dim)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 平面图副标 — 已有图就显示数量,没图就提示「上传」。
    private var floorPlanSubtitle: String {
        let count = FloorPlansStorage.load().filter { $0.siteTag == effectiveSiteTag }.count
        if count == 0 {
            return String(localized: "还没图纸,点进去上传", locale: locale)
        }
        return String(localized: "已上传 \(count) 张", locale: locale)
    }

    // MARK: - 字段行

    /// 标准 TextField 行 — 与 settings 卡片视觉一致:卡内,左右各 14pt,统一字号。
    @ViewBuilder
    private func fieldRow(
        placeholder: String,
        text: Binding<String>,
        capitalization: TextInputAutocapitalization
    ) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 14))
            .foregroundStyle(Ink.fg)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
    }

    // MARK: - 视觉 helpers(与 SiteTeamSettingsRoot 风格保持一致,本地私有复刻)

    @ViewBuilder
    private func groupBlock<Content: View>(
        header: String,
        footer: String?,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Ink.fgDim)
                .padding(.horizontal, 4)
            content()
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
                    .padding(.horizontal, 4)
                    .lineSpacing(2)
            }
        }
    }

    @ViewBuilder
    private func cardContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Ink.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Ink.line, lineWidth: 1)
        )
    }

    private func iconBox(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Ink.fg)
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Ink.line2, lineWidth: 1)
            )
    }

    // MARK: - Save

    private var navTitle: String {
        switch target {
        case .new: return String(localized: "新建工地", locale: locale)
        case .edit: return String(localized: "编辑工地", locale: locale)
        }
    }

    private var trimmedSiteTag: String {
        siteTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 实际写入的 siteTag — PM 简化版:工地名就是 siteTag,所见即所得。
    /// (Engineer 版用 address 当 siteTag — 不同的产品决定,两边各自一份)。
    private var effectiveSiteTag: String { trimmedSiteTag }

    private var canSave: Bool {
        !effectiveSiteTag.isEmpty
    }

    private func attemptSave() {
        let finalTag = effectiveSiteTag
        guard !finalTag.isEmpty else {
            errorMessage = String(localized: "请输入工地名。", locale: locale)
            return
        }

        // 复用 target.initial(编辑时 = 现有 entity,新建时 = 临时空 SitePreset),
        // 只写本 view 暴露的 3 个字段,其他字段保留 — Engineer 端历史填的项目信息不丢。
        let draft = target.initial
        draft.siteTag = finalTag
        draft.address = trimmedAddress
        // updatedAt 由 Storage 层在 add / update 路径里写。

        guard onSave(draft) else { return }
        hasSavedSuccessfully = true
        dismiss()
    }
}

#Preview {
    NavigationStack {
        SiteTeamSiteEditorView()
    }
}
