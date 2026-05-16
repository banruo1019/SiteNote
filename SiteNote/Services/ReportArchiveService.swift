//
//  ReportArchiveService.swift
//  SiteNote
//
//  归档已导出的 PDF 报告。两层存储:
//   1) 本地主存(必有):<Application Support>/Reports/<filename>.pdf
//      —— 即使没开 iCloud capability、没登 iCloud 也能用。卸载 App 才会丢。
//   2) iCloud Drive 镜像(可选):<Ubiquity Container>/Documents/<filename>.pdf
//      —— 需要在 Xcode 加 iCloud Documents capability + Info.plist 配
//      NSUbiquitousContainers(详见 ICLOUD_FILES_SETUP.md)。配齐后,文件会
//      自动出现在 Files App → iCloud Drive → SiteNote 文件夹。
//
//  为什么双写而不是单走 iCloud:
//   - 用户可能没开 iCloud / 没登 / 没网。本地必须存,否则导出后没地方看。
//   - iCloud 是"额外能力",失败静默(不阻塞导出流程)。
//
//  调用方:
//   - PDFExportView 批量导出后 archive(url:)
//   - InspectionFormView SVR 生成后 archive(url:)
//   - 单条分享(NoteDetailView+Actions)目前不归档——那只是临时分享。
//

import Foundation

enum ReportArchiveService {

    // MARK: - 路径

    /// 本地主存目录(`<App Support>/Reports/`)。第一次访问时自动创建。
    private static func localDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("Reports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// iCloud Drive 容器的 Documents 目录。
    /// 没配 capability / 用户没登 iCloud → 返回 nil(优雅降级)。
    static func iCloudDocumentsDirectory() -> URL? {
        // 把 forUbiquityContainerIdentifier 传 nil = 用 entitlements 里 ubiquity-container 的第一个
        // 注:这调用可能阻塞,首次调用建议在后台线程。我们这里用主线程的"快速访问"——
        // 系统会在第一次调用后缓存,后续调用基本秒回。
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let docs = container.appendingPathComponent("Documents", isDirectory: true)
        if !FileManager.default.fileExists(atPath: docs.path) {
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        }
        return docs
    }

    /// iCloud 是否可用(capability 开了 + 用户登了 iCloud)。
    static var isICloudAvailable: Bool {
        iCloudDocumentsDirectory() != nil
    }

    // MARK: - Archive

    /// 把临时 PDF 归档到本地(+ iCloud 镜像)。返回归档后的本地 URL。
    /// - Parameter sourceURL: 通常是 temp 目录里的 PDF。归档后**不**删除源文件(调用方负责)。
    /// - Returns: 归档后的本地 URL。即使 iCloud 写失败也会返回本地 URL。
    @discardableResult
    static func archive(sourceURL: URL) throws -> URL {
        let localDir = try localDirectory()
        let filename = sourceURL.lastPathComponent
        let dest = localDir.appendingPathComponent(filename)

        // 文件已存在 → 覆盖(同一份报告重复导出常见)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)

        // iCloud 镜像:能写就写,失败静默(返回本地 URL)
        if let iCloudDir = iCloudDocumentsDirectory() {
            let iCloudDest = iCloudDir.appendingPathComponent(filename)
            // iCloud 用 setUbiquitous 移动,而不是 copy ——后者不会触发 sync
            // 但我们不能 move(本地要保留),所以这里直接 copy:
            // 系统会自动 sync(放进 ubiquity 容器的文件)。
            if FileManager.default.fileExists(atPath: iCloudDest.path) {
                try? FileManager.default.removeItem(at: iCloudDest)
            }
            try? FileManager.default.copyItem(at: dest, to: iCloudDest)
        }

        return dest
    }

    // MARK: - 列表

    struct ArchivedReport: Identifiable, Hashable {
        let url: URL
        let filename: String
        let createdAt: Date
        let sizeBytes: Int64
        /// 是否同时存在 iCloud 镜像(用户能在 Files App 看到)。
        let hasICloudMirror: Bool

        var id: URL { url }

        var sizeDescription: String {
            ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }
    }

    /// 列出所有已归档的报告,按创建时间倒序。
    static func listArchived() -> [ArchivedReport] {
        guard let dir = try? localDirectory() else { return [] }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let iCloudDir = iCloudDocumentsDirectory()
        let pdfs = files.filter { $0.pathExtension.lowercased() == "pdf" }

        let reports = pdfs.compactMap { url -> ArchivedReport? in
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let date = values?.creationDate ?? Date.distantPast
            let size = Int64(values?.fileSize ?? 0)
            let mirrorExists: Bool
            if let iCloudDir {
                let mirrorURL = iCloudDir.appendingPathComponent(url.lastPathComponent)
                mirrorExists = fm.fileExists(atPath: mirrorURL.path)
            } else {
                mirrorExists = false
            }
            return ArchivedReport(
                url: url,
                filename: url.lastPathComponent,
                createdAt: date,
                sizeBytes: size,
                hasICloudMirror: mirrorExists
            )
        }
        return reports.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - 删除

    /// 删除归档(本地 + iCloud 镜像)。
    static func delete(_ report: ArchivedReport) throws {
        try FileManager.default.removeItem(at: report.url)
        if let iCloudDir = iCloudDocumentsDirectory() {
            let mirror = iCloudDir.appendingPathComponent(report.filename)
            try? FileManager.default.removeItem(at: mirror)
        }
    }

    // MARK: - 同步状态(诊断用)

    /// 给设置页用:返回一行人话说明当前 iCloud Files 同步状态。
    static func diagnosticStatus() -> String {
        if isICloudAvailable {
            return String(
                localized: "iCloud Files 同步已启用,归档自动出现在 Files App → iCloud Drive → SiteNote",
                locale: AppLanguageManager.currentLocale
            )
        } else {
            return String(
                localized: "iCloud Files 同步未启用(Xcode capability 缺失 / 未登 iCloud)。报告只存本地。",
                locale: AppLanguageManager.currentLocale
            )
        }
    }
}
