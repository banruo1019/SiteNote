//
//  ContentView.swift
//  SiteNote
//
//  App 的根视图。
//  - Phase 9:直接承载 MainTabView。
//  - iPad R2:改走 AdaptiveRootView,按 horizontalSizeClass 路由:
//    Compact → MainTabView(iPhone / iPad 多窗口窄分屏)
//    Regular → IPadRootView(NavigationSplitView 三栏)
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        AdaptiveRootView()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, ShareLog.self, configurations: config)
    return ContentView().modelContainer(container)
}
