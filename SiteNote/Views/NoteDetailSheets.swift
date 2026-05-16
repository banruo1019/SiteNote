//
//  NoteDetailSheets.swift
//  SiteNote
//
//  从 NoteDetailView.swift 拆分出来的:
//  - 支撑类型 (ContextChip / FullscreenPhoto / DetailPhotoEdit / PendingAssignee /
//             SharePDFItem / PolishPreview / PhotoAnalysisRow / PhotoAnalysesSheet
//             以及 ContextChipKind 枚举)
//  - 标签选择 sheet:TagPickerSheet
//  - 新建分类 sheet:NewSubTagSheet
//

import SwiftUI
import UIKit

// MARK: - Supporting types (NoteDetailView 跨文件使用)

enum ContextChipKind {
    case tag     // 主标签:可点开 picker 改
    case hazard  // 隐患:展示用
    case other   // 模板 / 条款 / 指派 / 平面图 等:展示用
}

struct ContextChip: Identifiable {
    let id: UUID = UUID()
    let icon: String
    let text: String
    let color: Color
    let kind: ContextChipKind
}

struct SharePDFItem: Identifiable {
    let id: UUID = UUID()
    let url: URL
}

struct FullscreenPhoto: Identifiable {
    let id: UUID = UUID()
    let image: UIImage
    /// 关联的相对路径(可空)。有值时全屏视图会显示"标注"按钮,
    /// 点击后关闭全屏并触发详情页的 PhotoEditorView。
    var path: String? = nil
}

struct DetailPhotoEdit: Identifiable {
    let id: UUID = UUID()
    let path: String
    let image: UIImage
}

struct PendingAssignee: Identifiable {
    let id: UUID = UUID()
    let name: String
    let phone: String
}

struct PolishPreview: Identifiable {
    let id: UUID = UUID()
    let before: String
    let after: String
}

// MARK: - TagPickerSheet

/// 标签选择 sheet。
/// - 工地:单选 radio,列表来自 SiteTagsStorage
/// - 分类:**单选** radio,全局共享,来自 SubTagsStorage
/// - 就地新建工地或分类(新建分类需要选颜色)
/// 工地 / 分类 picker sheet。
struct TagPickerSheet: View {
    let currentSiteTag: String?
    let currentOtherTags: [String]
    let onSiteChange: (String?) -> Void
    let onOtherTagsChange: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var siteTags: [String] = SiteTagsStorage.load()
    @State private var subTags: [SubTag] = SubTagsStorage.load()

    @State private var selectedSite: String?
    /// 单选:最多一个分类名。为 nil 表示未选。
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
                text: String(localized: "不设工地(未命名)", locale: AppLanguageManager.currentLocale),
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
                text: String(localized: "不设分类", locale: AppLanguageManager.currentLocale),
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
                    Text("新建分类")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        } header: {
            Text("分类(单选)")
        } footer: {
            Text("分类是全局的类型分类,如 RFI、缺陷、施工、开会、紧急。平面图图钉按分类颜色显示。")
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

// MARK: - NewSubTagSheet

/// 新建分类 sheet。名字 + 颜色,单独一个 sheet 避免和 Form 里的 Button 打架。
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
                            Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "(名字)", locale: AppLanguageManager.currentLocale) : name)
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
            .navigationTitle("新建分类")
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
