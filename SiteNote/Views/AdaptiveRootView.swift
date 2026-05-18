//
//  AdaptiveRootView.swift
//  SiteNote
//
//  iPad 适配根 view(R2 — 骨架)。
//
//  设计原则(见 `IPAD_PLAN.md`):
//  - **唯一 size class 路由器** — 全 app 只在这里判 horizontalSizeClass
//  - Compact(iPhone / iPad 多窗口窄分屏)→ 走 `MainTabView`(iPhone 原路径,零改动)
//  - Regular(iPad 全屏 / 大尺寸 Stage Manager 窗口)→ 走 `IPadRootView`(NavigationSplitView)
//
//  **不要**在共用 view 内部再判 size class — 共用 view 维持 Compact 行为,
//  iPad 走 wrapper(`IPadRootView` 内的 detail 复用现有 view)。
//
//  **iPhone 体验不退化** — 任何 iPad 改动必须 size class gated。
//

import SwiftUI

struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            IPadRootView()
        } else {
            MainTabView()
        }
    }
}
