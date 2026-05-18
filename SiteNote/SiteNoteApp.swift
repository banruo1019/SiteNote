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
import CloudKit

@main
struct SiteNoteApp: App {
    /// 接收 CloudKit share invitation(用户点 Mail/Messages 里的 share URL 后系统调回来)。
    /// SiteNoteAppDelegate 把 metadata 派发给 .shareInvitationReceived 通知。
    @UIApplicationDelegateAdaptor(SiteNoteAppDelegate.self) private var appDelegate

    init() {
        // v1.2 起不再使用 OpenAI。主动清掉残留的 API Key(每次启动都做,
        // 用户从旧版升级或多设备 sync 残留时,这里兜底确保 key 不留在 Keychain)。
        KeychainStorage.delete(for: KeychainKeys.openAIAPIKey)

        // v1.5:Builder 拆成 Builder(公司)+ Contact(联系人)。
        // 一次性把扁平老数据拆成二级结构,UserDefaults flag 保证 idempotent。
        ContactsStorage.migrateFromBuilderLegacyOnce()

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
    @State private var shareInviteMessage: String?
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
            // **P1 retry queue**:前台时处理 mirror retry queue。
            // 用户离线时 mirror 失败入队 → 网络恢复后 app 切前台自动重发。
            Task { @MainActor in
                await TeamDataMirrorService.shared.processRetryQueue(in: container.mainContext)
            }
        }
        // CloudKit share invitation:SiteNoteAppDelegate 把 metadata 派发到这里,
        // ModelContext 准备好后(.ready)接受 share + 在本地建 Team/TeamMember mirror。
        .onReceive(NotificationCenter.default.publisher(
            for: .shareInvitationReceived
        )) { note in
            guard case .ready(let container) = state,
                  let metadata = note.userInfo?["metadata"] as? CKShare.Metadata else { return }
            Task { @MainActor in
                do {
                    try await TeamCloudKitService.shared.acceptShareInvitation(
                        metadata: metadata,
                        modelContext: container.mainContext
                    )
                    shareInviteMessage = String(
                        localized: "已加入团队",
                        locale: AppLanguageManager.currentLocale
                    )
                } catch {
                    shareInviteMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
        .alert(
            String(localized: "团队邀请", locale: AppLanguageManager.currentLocale),
            isPresented: Binding(
                get: { shareInviteMessage != nil },
                set: { if !$0 { shareInviteMessage = nil } }
            )
        ) {
            Button(String(localized: "知道了", locale: AppLanguageManager.currentLocale)) {
                shareInviteMessage = nil
            }
        } message: {
            Text(shareInviteMessage ?? "")
        }
    }

    private func initContainer() {
        // E3.2:启动时把老路径下的内部目录搬到 Caches。只跑一次,失败静默。
        BackupService.migrateLegacyDirectories()
        CrashReporter.migrateLegacyDirectory()

        // Schema:所有 7 张表共享一个 store。
        //   - 速记/照片/巡检报告/日程 → SwiftData CloudKit private DB auto-sync(开启 toggle 后)
        //   - Team / TeamMember 也在同 store(Owner 多设备能看见自己的 team)
        //   - 跨用户 Team 共享另由 TeamCloudKitService 用 raw CKDatabase 处理
        //
        // **不传 MigrationPlan,不用 VersionedSchema**:经多次实测,Apple
        // SwiftData 在 iOS 18+ 的 VersionedSchema + MigrationPlan 在某些
        // model 配置下会抛 SwiftDataError 1(具体根因未公开)。回退到 v1.0
        // 那种最简单的 schema 用法,让 SwiftData 自动 lightweight inference。
        // v1.0 老用户升级:旧 3 张表数据保留,新加的 4 张表 SwiftData 自动建空表。
        let schema = Schema(SiteNoteSchemaV2.models)

        let modelConfiguration: ModelConfiguration
        if ICloudSyncConfig.shared.isEnabled {
            modelConfiguration = ICloudSyncConfig.cloudKitConfiguration(schema: schema)
        } else {
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            // v1.6: SwiftDataStack 注册 — facade(SitePresetStorage 等)启动后能拿到 mainContext。
            // 必须在任何 storage facade 被调用前完成,所以放在 ModelContainer 创建成功后第一时间。
            SwiftDataStack.shared.register(container)
            // v1.6: 一次性迁移 — UserDefaults `settings.sitePresets.v1` JSON → SwiftData @Model。
            // idempotent flag 防重跑。
            SitePresetStorage.migrateFromUserDefaultsOnce()
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
            // SwiftDataError 1 等通用错误 localizedDescription 信息很少,
            // 把 NSError 详情都打出来方便排查。Xcode Console 直接看。
            print("[SiteNote] ❌ ModelContainer 创建失败")
            print("  error: \(error)")
            print("  localizedDescription: \(error.localizedDescription)")
            let nsError = error as NSError
            print("  domain: \(nsError.domain)")
            print("  code: \(nsError.code)")
            print("  userInfo: \(nsError.userInfo)")
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                print("  underlying: \(underlying)")
                print("  underlying.userInfo: \(underlying.userInfo)")
            }
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
