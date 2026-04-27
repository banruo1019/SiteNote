//
//  CrashReporter.swift
//  SiteNote
//
//  MetricKit 崩溃监听。Apple 自带,无第三方依赖。
//  收到 crash diagnostic 后写到 Documents/_crash_reports/<timestamp>.json,
//  下次用户进 Settings → 反馈时可附带这些(后续 task)。
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
        let dir = crashReportsDir()
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

    private func crashReportsDir() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("_crash_reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
