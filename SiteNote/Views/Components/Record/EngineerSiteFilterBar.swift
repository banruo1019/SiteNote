//
//  EngineerSiteFilterBar.swift
//  SiteNote
//
//  Engineer 视角主屏顶部 — 水平滚动的工地 chip 行(单选)。
//  - "全部" chip 在最前,显示总数
//  - 其余 chip 按 allTags 顺序,显示该工地的 Note 计数
//  - 选中态:Ink.fg 黑底白字 / 未选:白底 1px Ink.line 描边
//
//  从 RecordView 提取出来。tags 计算和 selection 留在 parent,
//  本 view 只渲染 + 触发 selection 变化。
//

import SwiftUI

struct EngineerSiteFilterBar: View {
    /// 所有已知工地标签,顺序由 caller 决定。
    let allTags: [String]
    /// 当前选中的工地(nil = 全部)。
    @Binding var selection: String?
    /// 计算某个 tag 对应的 Note 条数;nil tag = 全部计数。
    let countFor: (String?) -> Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, label: String(localized: "全部", locale: AppLanguageManager.currentLocale))
                ForEach(allTags, id: \.self) { tag in
                    chip(tag, label: tag)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private func chip(_ tag: String?, label: String) -> some View {
        let isOn = selection == tag
        let count = countFor(tag)
        return Button {
            selection = tag
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? Ink.bg : Ink.fg)
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isOn ? Ink.bg.opacity(0.7) : Ink.fgDim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isOn ? Ink.fg : Ink.bg)
            )
            .overlay(
                Capsule().stroke(isOn ? Color.clear : Ink.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
