//
//  DiagnosticPackager.swift
//  SiteNote
//
//  数据库恢复界面用:
//    1. createDiagnosticZip(errorDescription:) — 把出错的 SwiftData store + UserDefaults
//       + 错误信息打包成 zip,让用户发给开发者排查。
//    2. resetDatabase() — 删掉 Application Support 下的 SwiftData store 文件,
//       让下次 ModelContainer 创建从空库开始。**会丢业务数据**,只在恢复界面"最后手段"用。
//
//  与 BackupService 的区别:Backup 假设 App 已正常运行(SwiftData 工作),走 NSFileCoordinator。
//  这里假设 App 启动失败,只能直接读文件。
//

import Foundation

enum DiagnosticPackager {

    enum DiagnosticError: LocalizedError {
        case appSupportMissing
        case packageFailed(String)

        var errorDescription: String? {
            switch self {
            case .appSupportMissing:
                return "无法访问 App 的内部数据目录。"
            case .packageFailed(let detail):
                return "打包失败: \(detail)"
            }
        }
    }

    /// 把出错的 store 文件 + UserDefaults + 错误描述 + 系统信息打包成 zip。
    static func createDiagnosticZip(errorDescription: String) throws -> URL {
        let fm = FileManager.default
        let tempBase = fm.temporaryDirectory.appendingPathComponent("sitenote-diagnostic-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try? fm.removeItem(at: tempBase)
        try fm.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempBase) }

        // 1. 错误描述 + 设备信息
        let info = """
        SiteNote Diagnostic
        Generated: \(Date())
        iOS: \(deviceInfo())

        Error:
        \(errorDescription)
        """
        try info.write(to: tempBase.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)

        // 2. SwiftData store 文件(可能损坏,但仍要导出给排查)
        if let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            let storeDir = tempBase.appendingPathComponent("store", isDirectory: true)
            try? fm.createDirectory(at: storeDir, withIntermediateDirectories: true)
            for name in ["default.store", "default.store-wal", "default.store-shm"] {
                let src = appSupport.appendingPathComponent(name)
                guard fm.fileExists(atPath: src.path) else { continue }
                try? fm.copyItem(at: src, to: storeDir.appendingPathComponent(name))
            }
        }

        // 3. UserDefaults(只导我们的 settings.* 键,不泄漏 Apple 私有键)
        let mineDefaults = UserDefaults.standard.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("settings.") }
            .compactMapValues { JSONSerialization.isValidJSONObject([$0]) ? $0 : nil }
        if let data = try? JSONSerialization.data(
            withJSONObject: mineDefaults,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: tempBase.appendingPathComponent("userdefaults.json"))
        }

        // 4. 把 tempBase 打包成 zip(用 NSFileCoordinator forUploading)
        let destURL = fm.temporaryDirectory.appendingPathComponent("SiteNote-diagnostic-\(Int(Date().timeIntervalSince1970)).zip")
        try? fm.removeItem(at: destURL)

        var coordError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: tempBase,
            options: [.forUploading],
            error: &coordError
        ) { coordinatedURL in
            do {
                try fm.copyItem(at: coordinatedURL, to: destURL)
            } catch {
                copyError = error
            }
        }

        if let coordError {
            throw DiagnosticError.packageFailed(coordError.localizedDescription)
        }
        if let copyError {
            throw DiagnosticError.packageFailed(copyError.localizedDescription)
        }

        return destURL
    }

    /// 删掉 Application Support 下的 SwiftData store 文件,让下次 ModelContainer 从空库开始。
    /// **会丢所有 SwiftData 数据**(Note / LogEntry / ShareLog)。Documents 下的录音/照片不动。
    static func resetDatabase() {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            let url = appSupport.appendingPathComponent(name)
            try? fm.removeItem(at: url)
        }
        print("[SiteNote] DiagnosticPackager: 已重置 SwiftData store")
    }

    private static func deviceInfo() -> String {
        let pi = ProcessInfo.processInfo
        return "\(pi.operatingSystemVersionString)"
    }
}
