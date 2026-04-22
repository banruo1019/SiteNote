//
//  IndustrialTheme.swift
//  SiteNote
//
//  M1 Linear 风 Form / List 基础样式。
//  - `.industrialForm()` — 把 Form/List 的默认灰底换成 Ink.bg 纯白,更贴 M1 审美
//  - `SectionHeader(_:)` / `SectionFooter(_:)` — 11pt 600 大写 Ink.fgDim
//

import SwiftUI

struct IndustrialListBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Ink.bg.ignoresSafeArea())
    }
}

extension View {
    func industrialForm() -> some View {
        modifier(IndustrialListBackground())
    }
}

/// 11pt 600 大写 Ink.fgDim 的 section header。
struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Ink.fgDim)
    }
}

/// 11pt Ink.fgDim 的 section footer。
struct SectionFooter: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Ink.fgDim)
    }
}
