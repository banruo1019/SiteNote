//
//  NoteDetailView+Sections.swift
//  SiteNote
//
//  NoteDetailView 的纯展示 section:tags / dates / audio / floor plan / other meta。
//  从主文件抽出,extension 形式。
//

import SwiftUI

extension NoteDetailView {

    // MARK: - 2. 标签一排(工地 + 分类 + 状态 + 条款 + 指派 + 平面图 ref)

    var tagsRow: some View {
        let chips = contextChips
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips) { c in
                    chipView(c)
                }
            }
        }
    }

    var contextChips: [ContextChip] {
        var list: [ContextChip] = []
        if note.isHazard {
            list.append(ContextChip(
                icon: "exclamationmark.triangle.fill",
                text: String(localized: "隐患", locale: AppLanguageManager.currentLocale),
                color: Ink.red,
                kind: .hazard
            ))
        }
        let siteName = note.siteTag
        list.append(ContextChip(
            icon: siteName == nil ? "building.2" : "building.2.fill",
            text: siteName ?? String(localized: "未命名工地", locale: AppLanguageManager.currentLocale),
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
                text: String(localized: "已处理", locale: AppLanguageManager.currentLocale),
                color: Ink.green,
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
    func chipView(_ c: ContextChip) -> some View {
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

    var deadlinePill: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 12))
            Text(deadlineDisplay)
                .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
        }
        .foregroundStyle(deadlineColor)
    }

    var deadlineColor: Color {
        if note.deadline == .archive { return .gray }
        if note.isDone { return .gray }
        if note.dueDate < Date() { return .red }
        if Calendar.current.isDateInToday(note.dueDate) { return Ink.red }
        return .primary
    }

    // MARK: - 5. 创建 + 到期 日期并排

    var datesRow: some View {
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

    func dateCell(icon: String, label: LocalizedStringKey, value: String, tint: Color) -> some View {
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
    var audioDisclosure: some View {
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

    // MARK: - 7. 平面图(折叠)

    @ViewBuilder
    var floorPlanDisclosure: some View {
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

    var floorPlanDisclosureLabel: String {
        if let name = note.floorPlanRef {
            return String(localized: "平面图位置: \(name)", locale: AppLanguageManager.currentLocale)
        }
        return String(localized: "平面图位置", locale: AppLanguageManager.currentLocale)
    }

    @ViewBuilder
    var floorPlanContent: some View {
        // P2 #187:优先 floorPlanID,fallback floorPlanRef 名字
        if let x = note.floorPlanX,
           let y = note.floorPlanY,
           let plan = FloorPlansStorage.resolve(id: note.floorPlanID, name: note.floorPlanRef) {
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

    // MARK: - 8. 其他元数据(折叠)

    var otherMetaDisclosure: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                Divider()
                infoRow("位置", value: note.locationAddress ?? String(localized: "未记录", locale: AppLanguageManager.currentLocale))
                Divider()
                infoRow("天气", value: note.weatherSummary ?? String(localized: "未记录", locale: AppLanguageManager.currentLocale))
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
    func infoRow(_ label: LocalizedStringKey, value: String) -> some View {
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

    var deadlineDisplay: String {
        if note.deadline == .archive {
            return String(localized: "归档", locale: AppLanguageManager.currentLocale)
        }
        let due = note.dueDate.formatted(date: .abbreviated, time: .omitted)
        return "\(note.deadline.displayName) · \(due)"
    }
}
