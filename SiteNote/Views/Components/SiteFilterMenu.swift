//
//  SiteFilterMenu.swift
//  SiteNote
//
//  M1 共享组件 — 工地过滤胶囊菜单。原本在 PMCalendarView /
//  EngineerScheduleView / ReportsView 三处复制粘贴(~40 行 × 3)。
//
//  视觉:building.2 icon + 当前选中工地名 + chevron.down,圆 capsule 灰底。
//  交互:点开 Menu,首项"全部工地"(nil),分隔线,然后每个 tag 一项。
//  当前选中项 prefix 一个 checkmark Label。
//

import SwiftUI

struct SiteFilterMenu: View {
    /// 所有已知工地标签(顺序由 caller 决定,通常 sorted)。
    let allTags: [String]
    /// 当前选中(nil = 全部工地)。
    @Binding var selection: String?

    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                if selection == nil {
                    Label(
                        String(localized: "全部工地", locale: AppLanguageManager.currentLocale),
                        systemImage: "checkmark"
                    )
                } else {
                    Text(String(localized: "全部工地", locale: AppLanguageManager.currentLocale))
                }
            }
            Divider()
            ForEach(allTags, id: \.self) { tag in
                Button {
                    selection = tag
                } label: {
                    if selection == tag {
                        Label(tag, systemImage: "checkmark")
                    } else {
                        Text(tag)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "building.2")
                    .font(.system(size: 11, weight: .semibold))
                Text(selection ?? String(localized: "全部工地", locale: AppLanguageManager.currentLocale))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Ink.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Ink.card))
        }
    }
}
