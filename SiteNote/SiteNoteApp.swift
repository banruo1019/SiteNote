//
//  SiteNoteApp.swift
//  SiteNote
//
//  Created by Banruo on 20/4/2026.
//
//  入口。负责 ModelContainer 初始化——**失败不再 fatalError**,
//  改成走 DatabaseRecoveryView,让用户能导出诊断包或重置后重试。
//  原因:工地用户冷启动崩溃 = 灾难,且经常无网无法重装。
//

import SwiftUI
import SwiftData

@main
struct SiteNoteApp: App {
    init() {
        CrashReporter.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .preferredColorScheme(.light)
                .tint(Ink.accent)
                // P2 改:取消启动就请求通知权限。改为"用户首次设到期或开每日汇总"时才请求,
                // 减少冷启动时的弹窗轰炸。
        }
    }
}

/// 顶层 root view:负责 ModelContainer 创建,失败时显示恢复界面。
private struct RootContainerView: View {
    @State private var state: InitState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                LoadingView()
                    .task { initContainer() }
            case .ready(let container):
                ContentView()
                    .modelContainer(container)
            case .failed(let error):
                DatabaseRecoveryView(error: error) {
                    state = .loading
                }
            }
        }
    }

    private func initContainer() {
        let schema = Schema([
            Note.self,
            LogEntry.self,
            ShareLog.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            state = .ready(container)
        } catch {
            print("[SiteNote] ModelContainer 创建失败: \(error.localizedDescription)")
            state = .failed(error)
        }
    }

    enum InitState {
        case loading
        case ready(ModelContainer)
        case failed(Error)
    }
}

/// 极简加载视图。容器初始化通常 < 50ms,用户感知不到。
private struct LoadingView: View {
    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()
            ProgressView()
                .controlSize(.large)
        }
    }
}
