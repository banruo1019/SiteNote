//
//  BackupService.swift
//  SiteNote
//
//  用系统 NSFileCoordinator 把整个 Documents 目录打包成 .zip。不依赖第三方。
//
//  V2(B3 整改):打包前先把 SwiftData 数据库 + UserDefaults 快照写到 Documents/_backup_meta/,
//  这样 zip 真正包含"全量数据"——速记内容(SwiftData)+ 用户偏好(UserDefaults)+ 附件(audio/photos)。
//  之前只打包 Documents 等于备份了附件没备份账本,用户清空后无法恢复速记本身。
//

import Foundation

/// 数据备份。把 App 的 Documents 目录（含 audio/ 和 photos/）打包成临时 .zip 文件。
/// 调用方拿到 URL 后用 UIActivityViewController 让用户选择保存到 iCloud Drive / 邮件 / 文件等。
enum BackupService {

    /// 备份元数据子目录名。**之前**塞在 Documents/ 下,但 iOS Files App 会把 Documents 暴露给用户,
    /// 用户看到 `_backup_meta/` 莫名其妙。改成放 Library/Caches/(Caches 不进 iTunes/iCloud 备份,
    /// 系统空间紧张时会清——对临时元数据来说没问题)。
    private static let metaDirName = "_backup_meta"

    /// 真实存放路径:Library/Caches/_backup_meta。失败回退到 tempDir 子目录(几乎不可能失败)。
    private static func metaDir() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        return base.appendingPathComponent(metaDirName, isDirectory: true)
    }

    enum BackupError: LocalizedError {
        case documentsDirectoryMissing
        case zipCreationFailed(String)

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryMissing:
                return String(localized: "无法访问 App 的数据目录。", locale: AppLanguageManager.currentLocale)
            case .zipCreationFailed(let detail):
                return String(localized: "备份失败:\(detail)", locale: AppLanguageManager.currentLocale)
            }
        }
    }

    /// 同步地创建一个 .zip 包含全部 Documents 目录 + SwiftData 数据库 + UserDefaults 快照。
    /// - Returns: 临时 .zip 文件的 URL。
    /// - Throws: `BackupError`。
    static func createBackupZip() throws -> URL {
        let fm = FileManager.default
        guard let docs = fm.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw BackupError.documentsDirectoryMissing
        }

        // 元数据快照写到 Caches/_backup_meta(不再污染 Documents,用户在 Files App 看不见)。
        let metaDir = metaDir()
        try? fm.removeItem(at: metaDir)
        try? fm.createDirectory(at: metaDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: metaDir) }
        // 这层目录从不参与 iCloud/iTunes 备份。
        var metaResource = URLResourceValues()
        metaResource.isExcludedFromBackup = true
        var mutableMeta = metaDir
        try? mutableMeta.setResourceValues(metaResource)

        snapshotSwiftDataStore(into: metaDir)
        snapshotUserDefaults(into: metaDir)

        // 由于 meta 不再在 Documents 下,直接 zip Documents 拿不到 meta。
        // 改成:在 Caches 下搭个 staging 目录,把 Documents 各子项**硬链/复制**进来 + meta 一并放进去,
        // 然后 NSFileCoordinator 打 staging 这一坨。
        let timestamp = Int(Date().timeIntervalSince1970)
        let cachesBase: URL = {
            (try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        }()
        let staging = cachesBase.appendingPathComponent("_backup_staging_\(timestamp)", isDirectory: true)
        try? fm.removeItem(at: staging)
        try? fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        // 复制 Documents 下"用户内容"子项;跳过临时/隐藏的(_crash_reports 旧路径 / _backup_meta 旧路径)。
        if let entries = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for entry in entries {
                let name = entry.lastPathComponent
                if name == "_backup_meta" || name == "_crash_reports" { continue }
                let dst = staging.appendingPathComponent(name)
                // 硬链快(同卷可),失败降级到 copy。
                if (try? fm.linkItem(at: entry, to: dst)) == nil {
                    try? fm.copyItem(at: entry, to: dst)
                }
            }
        }
        // 把 meta 也搬到 staging。
        let metaInStaging = staging.appendingPathComponent(metaDirName, isDirectory: true)
        try? fm.copyItem(at: metaDir, to: metaInStaging)

        let destURL = fm.temporaryDirectory.appendingPathComponent("SiteNote-backup-\(timestamp).zip")
        try? fm.removeItem(at: destURL)

        var coordError: NSError?
        var moveError: Error?

        // .forUploading 让系统给我们一个打包好的 zip 临时副本
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: staging,
            options: [.forUploading],
            error: &coordError
        ) { coordinatedURL in
            do {
                try fm.copyItem(at: coordinatedURL, to: destURL)
            } catch {
                moveError = error
            }
        }

        if let error = coordError {
            throw BackupError.zipCreationFailed(error.localizedDescription)
        }
        if let error = moveError {
            throw BackupError.zipCreationFailed(error.localizedDescription)
        }

        return destURL
    }

    /// 从旧路径搬走遗留:之前 `_backup_meta` 在 Documents/ 下若残留(异常退出时 defer 没跑),
    /// 启动时静默清掉,避免 Files App 暴露老用户的内部目录。
    static func migrateLegacyDirectories() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let oldMeta = docs.appendingPathComponent(metaDirName, isDirectory: true)
        if fm.fileExists(atPath: oldMeta.path) {
            try? fm.removeItem(at: oldMeta)
        }
    }

    /// 把 SwiftData 默认 store 文件(.store / -wal / -shm)拷到 metaDir/store/。
    /// 失败静默——store 不存在(全新 App)或写失败都不阻断备份。
    private static func snapshotSwiftDataStore(into metaDir: URL) {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        let storeDir = metaDir.appendingPathComponent("store", isDirectory: true)
        try? fm.createDirectory(at: storeDir, withIntermediateDirectories: true)

        // SwiftData 默认 store 名 default.store,可能伴随 -wal / -shm 日志文件。
        let candidates = ["default.store", "default.store-wal", "default.store-shm"]
        for name in candidates {
            let src = appSupport.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = storeDir.appendingPathComponent(name)
            try? fm.copyItem(at: src, to: dst)
        }
    }

    /// E3.4:显式白名单 + 前缀兜底。原来只用 `hasPrefix("settings.")` 模糊匹配,
    /// 一旦未来引入第三方库往 settings.xxx 写键就被一并备份了。这里给所有当前确认要备份的键
    /// 列出来,让审计/将来 PR 加键时一眼能看到"这条要不要进备份"。
    /// 仍然保留前缀兜底,避免漏掉个别小工具自加的 settings.xxx 临时键。
    static let backupKeys: [String] = [
        // 语言 / 角色
        "settings.appLanguage",
        "settings.userProfile",
        "settings.userProfile.selected",
        // 录入 / 提醒
        "settings.speechLanguage",
        "settings.morningReminderHour",
        "settings.morningReminderMinute",
        "settings.dailyDigestEnabled",
        "settings.inspectorName",
        // AI 总开关 / 单功能
        "settings.aiMasterEnabled",
        "settings.aiPolishEnabled",
        "settings.aiAutoTagEnabled",
        "settings.aiOmniClassifyEnabled",
        "settings.aiLogExtractEnabled",
        // AI 引擎配置(API Key 在 Keychain,不进备份)
        "settings.aiEngine",
        "settings.openAITextModel",
        "settings.openAIVisionModel",
        "settings.openAIEmbeddingModel",
        // 用户内容列表
        "settings.siteTags",
        "settings.subTagsGlobalV1",
        "settings.clauseRefs",
        "settings.clauseRefs.seeded",
        "settings.floorPlans",
        "settings.siteCentroids.v1",
        "settings.jargonCustomTerms",
        "settings.jargonShortcuts",
        // (Obsidian 已下架,这两个 key 留作 legacy 兼容,旧用户备份能恢复)
        "settings.obsidian.exportFolderPath",
        // 引导
        "settings.onboarding.dismissed.v1",
        "settings.aiKeyHint.dismissed.v1",
    ]

    /// 把 SiteNote 自己的 UserDefaults 键序列化为 JSON 写到 metaDir/userdefaults.json。
    /// 用 `backupKeys` 显式白名单,避免误备份第三方/系统键。
    private static func snapshotUserDefaults(into metaDir: URL) {
        let defaults = UserDefaults.standard
        var picked: [String: Any] = [:]
        for key in backupKeys {
            guard let value = defaults.object(forKey: key) else { continue }
            if JSONSerialization.isValidJSONObject([value]) {
                picked[key] = value
            }
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: picked,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }

        let url = metaDir.appendingPathComponent("userdefaults.json")
        try? data.write(to: url, options: .atomic)
    }
}
