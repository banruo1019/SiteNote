//
//  BackupService.swift
//  SiteNote
//
//  用系统 NSFileCoordinator 把整个 Documents 目录打包成 .zip。不依赖第三方。
//

import Foundation

/// 数据备份。把 App 的 Documents 目录（含 audio/ 和 photos/）打包成临时 .zip 文件。
/// 调用方拿到 URL 后用 UIActivityViewController 让用户选择保存到 iCloud Drive / 邮件 / 文件等。
enum BackupService {

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

    /// 同步地创建一个 .zip 包含全部 Documents 目录。
    /// - Returns: 临时 .zip 文件的 URL。
    /// - Throws: `BackupError`。
    static func createBackupZip() throws -> URL {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw BackupError.documentsDirectoryMissing
        }

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
}
