//
//  ContentView.swift
//  SiteNote
//
//  App 的根视图。Phase 9 后直接承载 MainTabView。
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, ShareLog.self, configurations: config)
    return ContentView().modelContainer(container)
}
