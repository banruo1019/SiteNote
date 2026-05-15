//
//  CrashReporter.swift
//  SiteNote
//
//  MetricKit 崩溃监听。Apple 自带,无第三方依赖。
//  收到 crash diagnostic 后写到 Library/Caches/_crash_reports/<timestamp>.json,
//  用户在 Settings → 反馈时可作为附件发邮件。
//
//  路径迁移:从 Documents/_crash_reports → Library/Caches/_crash_reports。
//  原因:Documents 在 iOS Files App 暴露给用户,看到 "_crash_reports" 莫名其妙。
//

import Foundation
import MetricKit
import os.log

final class CrashReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReporter()

    private let logger = Logger(subsystem: "com.banruoyang.sitenote", category: "crash")

    private override init() { super.init() }

    /// 在 SiteNoteApp init 调一次。
    func start() {
        MXMetricManager.shared.add(self)
        logger.info("CrashReporter started")
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        // v1 不处理性能/电量指标
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty else { return }
        let dir = Self.crashReportsDir()
        for payload in payloads {
            guard !payload.crashDiagnostics.isNilOrEmpty else { continue }
            let timestamp = Int(payload.timeStampBegin.timeIntervalSince1970)
            let url = dir.appendingPathComponent("crash-\(timestamp).json")
            do {
                let data = payload.jsonRepresentation()
                try data.write(to: url, options: .atomic)
                logger.info("Saved crash report: \(url.lastPathComponent)")
            } catch {
                logger.error("Failed to save crash: \(error.localizedDescription)")
            }
        }
    }

    /// 当前的 crash reports 目录(Library/Caches/_crash_reports)。
    /// 让外部反馈邮件能附最新一份 crash JSON,所以暴露成 static。
    static func crashReportsDir() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("_crash_reports", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // 不进 iCloud/iTunes 备份。
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = dir
        try? mutable.setResourceValues(values)
        return dir
    }

    /// 反馈邮件用:返回最新一份 crash JSON 文件 URL,没有时返回 nil。
    static func latestCrashReport() -> URL? {
        let fm = FileManager.default
        let dir = crashReportsDir()
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }
        let jsons = files.filter { $0.pathExtension == "json" }
        // 按修改时间倒序拿最新。
        return jsons.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }.first
    }

    /// 启动时把 Documents/_crash_reports/* 迁到 Caches/_crash_reports/*,
    /// 已存在的同名跳过,迁完删旧目录。失败静默——不阻塞冷启动。
    static func migrateLegacyDirectory() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let oldDir = docs.appendingPathComponent("_crash_reports", isDirectory: true)
        guard fm.fileExists(atPath: oldDir.path) else { return }

        let newDir = crashReportsDir()
        if let files = try? fm.contentsOfDirectory(at: oldDir, includingPropertiesForKeys: nil) {
            for src in files {
                let dst = newDir.appendingPathComponent(src.lastPathComponent)
                if !fm.fileExists(atPath: dst.path) {
                    try? fm.moveItem(at: src, to: dst)
                }
            }
        }
        try? fm.removeItem(at: oldDir)
    }
}

private extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
