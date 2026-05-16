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
        // E3.11:删 App 再装回会把 sandbox 文件清掉,但 Keychain 默认幸存。
        // 用 UserDefaults 上的"首次启动 flag"判定:不存在 = 新装/重装,主动清掉残留的 OpenAI Key。
        // (Keychain 是 device-only,转手他人/卖机时残留更危险。)
        let firstLaunchFlag = "app.firstLaunchDoneV1"
        if !UserDefaults.standard.bool(forKey: firstLaunchFlag) {
            KeychainStorage.delete(for: KeychainKeys.openAIAPIKey)
            UserDefaults.standard.set(true, forKey: firstLaunchFlag)
        }

        // P0 隐私 bug 修复迁移:
        // 旧版 UI 上"自动推断标签" toggle 写的是 aiAutoTagEnabled,
        // 但分类管线(HomeViewModel)实际读的是 aiOmniClassifyEnabled —— toggle 形同虚设。
        // 修复后改成 UI 直接绑 aiOmniClassifyEnabled。为不丢老用户已经关掉过的状态,
        // 一次性把旧 key 的值复制到两个新 key 上(把"关掉所有 AI 推断"语义带过来)。
        // - aiLogExtractEnabled 之前根本没 UI 入口,默认 true;但既然用户当年是"想关 AI 推断",
        //   就把 log 抽取也按用户意图关掉,保持最小惊讶。
        let aiKeyMigrationFlag = "app.aiKeyMigrationV1Done"
        if !UserDefaults.standard.bool(forKey: aiKeyMigrationFlag) {
            let defaults = UserDefaults.standard
            let legacyKey = SettingsKeys.aiAutoTagEnabled
            let newClassifyKey = SettingsKeys.aiOmniClassifyEnabled
            let newExtractKey = SettingsKeys.aiLogExtractEnabled

            if let legacyValue = defaults.object(forKey: legacyKey) as? Bool {
                // 只在用户从未显式设置过新 key 时迁(避免覆盖已经迁过/新装用户的默认值)。
                if defaults.object(forKey: newClassifyKey) == nil {
                    defaults.set(legacyValue, forKey: newClassifyKey)
                }
                if defaults.object(forKey: newExtractKey) == nil {
                    defaults.set(legacyValue, forKey: newExtractKey)
                }
            }
            defaults.set(true, forKey: aiKeyMigrationFlag)
        }

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
    @State private var languageManager = AppLanguageManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch state {
            case .loading:
                LoadingView()
                    .task { initContainer() }
            case .ready(let container):
                ContentView()
                    .modelContainer(container)
                    // E3.5:时区变化(用户出差跨区)→ 老 dueDate/trigger 必须按新区重算。
                    // 监听 .NSSystemTimeZoneDidChange + scenePhase active 双保险:
                    // 系统通知有时不及时;前台回归时也补一刀。
                    .onReceive(NotificationCenter.default.publisher(
                        for: .NSSystemTimeZoneDidChange
                    )) { _ in
                        rescheduleAllNotes(in: container.mainContext)
                    }
            case .failed(let error):
                DatabaseRecoveryView(error: error) {
                    state = .loading
                }
            }
        }
        .environment(\.locale, languageManager.locale)
        .onChange(of: scenePhase) { _, newPhase in
            // 进入前台:补一次 reschedule。如果没切区就是无害的全量重算,
            // SwiftUI 的 scenePhase 也覆盖了"App 长时间挂后台又回来"的场景。
            guard newPhase == .active, case .ready(let container) = state else { return }
            rescheduleAllNotes(in: container.mainContext)
        }
    }

    private func initContainer() {
        // E3.2:启动时把老路径下的内部目录搬到 Caches。只跑一次,失败静默。
        BackupService.migrateLegacyDirectories()
        CrashReporter.migrateLegacyDirectory()

        // Schema:v1.1 范围 + v1.2 加 SiteVisitSchedule。
        // Team / TeamMember 暂不加入主 Schema(方案 C):
        //   - v1.2 先上 iCloud 备份(单人多设备 sync)
        //   - 团队功能 prototype 阶段,等 v1.3 写 VersionedSchema + MigrationPlan 一起接入
        //   - 避免老用户从 v1.0/v1.1 升级时 schema migration 失败
        let schema = Schema([
            Note.self,
            LogEntry.self,
            ShareLog.self,
            InspectionReport.self,
            SiteVisitSchedule.self,
        ])

        // ⚠️ iCloud sync 由 ICloudSyncConfig.shared.isEnabled feature flag 控制(默认 false)。
        // - false → 本地 only ModelConfiguration(等同 v1.1 行为,零变化)
        // - true  → CloudKit private DB,SwiftData 自动 sync 到 iCloud
        // 用户在 设置 → 数据 → 启用 iCloud 同步 toggle 切换(后续 UI 添加)。
        // 切换后需要重启 App 生效(SwiftData 当前不支持 hot-swap configuration)。
        let modelConfiguration: ModelConfiguration
        if ICloudSyncConfig.shared.isEnabled {
            modelConfiguration = ICloudSyncConfig.cloudKitConfiguration(schema: schema)
        } else {
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            // B2: 启动时清理孤儿 .m4a。录音中被杀的进程会留下永久不被引用的音频文件,
            // 长期累积可能占满磁盘。同步执行,失败不阻塞。
            VoiceCaptureService.cleanupOrphanAudio(modelContext: container.mainContext)
            // E3.1:启动时跑垃圾桶 GC,把过保留期(30 天)的软删 note 永久清掉。
            TrashView.runGarbageCollection(modelContext: container.mainContext)

            // CloudKit 启用时,异步缓存当前 user record(团队功能用 currentUserID 区分谁创建谁分配)。
            // 失败不阻塞(可能用户没登 iCloud / 没网)。
            if ICloudSyncConfig.shared.isEnabled {
                Task.detached {
                    try? await ICloudSyncConfig.shared.fetchAndCacheUserRecord()
                }
            }

            state = .ready(container)
        } catch {
            #if DEBUG
            print("[SiteNote] ModelContainer 创建失败: \(error.localizedDescription)")
            #endif
            state = .failed(error)
        }
    }

    /// E3.5:重排所有未完成且需推送的 note。给时区监听 + scenePhase 钩子复用。
    @MainActor
    private func rescheduleAllNotes(in context: ModelContext) {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.deletedAt == nil && $0.isDone == false }
        )
        guard let notes = try? context.fetch(descriptor) else { return }
        NotificationService.shared.rescheduleAll(notes: notes)
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
