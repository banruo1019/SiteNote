//
//  SiteNoteApp.swift
//  SiteNote
//
//  Created by Banruo on 20/4/2026.
//

import SwiftUI
import SwiftData

@main
struct SiteNoteApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Note.self,
            LogEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .tint(Ink.accent)
                .task {
                    // 启动时请求通知权限。系统只弹一次对话框，之后直接读之前的选择。
                    _ = await NotificationService.shared.requestAuthorization()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
