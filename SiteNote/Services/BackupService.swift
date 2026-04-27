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

    /// 备份元数据子目录(临时塞在 Documents 里好让 NSFileCoordinator 一并打包)。
    private static let metaDirName = "_backup_meta"

    enum BackupError: LocalizedError {
        case documentsDirectoryMissing
        case zipCreationFailed(String)

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryMissing:
                return "无法访问 App 的数据目录。"
            case .zipCreationFailed(let detail):
                return "备份失败: \(detail)"
            }
        }
    }

    /// 同步地创建一个 .zip 包含全部 Documents 目录 + SwiftData 数据库 + UserDefaults 快照。
    /// - Returns: 临时 .zip 文件的 URL。
    /// - Throws: `BackupError`。
    static func createBackupZip() throws -> URL {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw BackupError.documentsDirectoryMissing
        }

        // 打包前先生成元数据快照(SwiftData 文件 + UserDefaults JSON),临时塞 Documents。
        // 无论 zip 成败,defer 清掉,避免污染 Documents。
        let metaDir = docs.appendingPathComponent(metaDirName, isDirectory: true)
        try? FileManager.default.removeItem(at: metaDir)
        try? FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: metaDir) }

        snapshotSwiftDataStore(into: metaDir)
        snapshotUserDefaults(into: metaDir)

        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let destURL = tempDir.appendingPathComponent("SiteNote-backup-\(timestamp).zip")

        try? FileManager.default.removeItem(at: destURL)

        var coordError: NSError?
        var moveError: Error?

        // .forUploading 让系统给我们一个打包好的 zip 临时副本
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: docs,
            options: [.forUploading],
            error: &coordError
        ) { coordinatedURL in
            do {
                try FileManager.default.copyItem(at: coordinatedURL, to: destURL)
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

    /// 把 SiteNote 自己的 UserDefaults 键(以 "settings." 开头)序列化为 JSON 写到 metaDir/userdefaults.json。
    /// 不导出系统/Apple 私有键以减小尺寸 + 避免"导回 App 时把不该恢复的偏好搞乱"。
    private static func snapshotUserDefaults(into metaDir: URL) {
        let defaults = UserDefaults.standard
        let dict = defaults.dictionaryRepresentation()
        let mineOnly = dict.filter { key, _ in key.hasPrefix("settings.") }

        // 只保留 JSON 可序列化的值(Data 跳过)。
        let safe = mineOnly.compactMapValues { value -> Any? in
            JSONSerialization.isValidJSONObject([value]) ? value : nil
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: safe,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }

        let url = metaDir.appendingPathComponent("userdefaults.json")
        try? data.write(to: url, options: .atomic)
    }
}
