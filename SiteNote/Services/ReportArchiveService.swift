//
//  ReportArchiveService.swift
//  SiteNote
//
//  归档已导出的 PDF 报告。两层存储 + per-project 子文件夹:
//   1) 本地主存(必有):<Application Support>/Reports/<project>/<filename>.pdf
//      —— 即使没开 iCloud capability、没登 iCloud 也能用。卸载 App 才会丢。
//   2) iCloud Drive 镜像(可选):<Ubiquity Container>/Documents/<project>/<filename>.pdf
//      —— 需要在 Xcode 加 iCloud Documents capability + Info.plist 配
//      NSUbiquitousContainers(详见 ICLOUD_FILES_SETUP.md)。配齐后,文件会
//      自动出现在 Files App → iCloud Drive → SiteNote → <project> 文件夹。
//
//  Per-project 文件夹规则:
//   - projectFolder 由 caller 传(通常是 InspectionReport.projectNo 或 SitePreset.siteTag)
//   - 空 / 空白 → 用 "未分类" 占位
//   - 文件名里有 `/` 替成 `_`(防 path traversal)
//   - 历史平铺文件保留在 Reports/ 根目录,UI 显示成 "未分类"
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

    /// 默认 "未分类" 文件夹名 — 没传 project 或 project 空时用。
    static let unsortedFolderName = "未分类"

    /// 把 caller 传的 project 字段净化成安全文件夹名。
    /// 空 → 未分类。`/` 替 `_` 防 path traversal。修剪首尾空白。
    static func sanitizeProjectFolder(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return unsortedFolderName }
        return trimmed.replacingOccurrences(of: "/", with: "_")
    }

    // MARK: - Archive

    /// 把临时 PDF 归档到本地(+ iCloud 镜像),按 projectFolder 分子目录。
    /// - Parameters:
    ///   - sourceURL: 通常是 temp 目录里的 PDF。归档后**不**删除源文件。
    ///   - projectFolder: 项目文件夹名(通常 InspectionReport.projectNo 或 siteTag);
    ///     传 nil / 空 → 落到 "未分类" 子文件夹。
    /// - Returns: 归档后的本地 URL。即使 iCloud 写失败也会返回本地 URL。
    @discardableResult
    static func archive(sourceURL: URL, projectFolder: String? = nil) throws -> URL {
        let folder = sanitizeProjectFolder(projectFolder)
        let localDir = try localDirectory().appendingPathComponent(folder, isDirectory: true)
        if !FileManager.default.fileExists(atPath: localDir.path) {
            try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        }
        let filename = sourceURL.lastPathComponent
        let dest = localDir.appendingPathComponent(filename)

        // 文件已存在 → 覆盖(同一份报告重复导出常见)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)

        // iCloud 镜像:能写就写,失败静默(返回本地 URL)
        if let iCloudRoot = iCloudDocumentsDirectory() {
            let iCloudDir = iCloudRoot.appendingPathComponent(folder, isDirectory: true)
            try? FileManager.default.createDirectory(at: iCloudDir, withIntermediateDirectories: true)
            let iCloudDest = iCloudDir.appendingPathComponent(filename)
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
        /// 该报告归属的项目文件夹名("未分类" 表示 legacy 平铺 / 未传 project)。
        let projectFolder: String
        /// 是否同时存在 iCloud 镜像(用户能在 Files App 看到)。
        let hasICloudMirror: Bool
        /// v1.6 (en-v1):用户是否归档(在 Reports tab 右滑触发)。
        /// 实现:文件在 `Reports/<project>/.archived/` 子目录里 = true,其他 = false。
        let isUserArchived: Bool

        var id: URL { url }

        var sizeDescription: String {
            ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }
    }

    /// v1.6 (en-v1):用户归档隐藏子目录名(隐藏在 iOS Files App 不可见 — 点开头)。
    private static let userArchivedSubdir = ".archived"

    /// 列出所有已归档的报告(递归扫子目录),按创建时间倒序。
    /// - legacy: 直接在 Reports/ 根目录下的 .pdf 视为 "未分类"
    /// - 现在的: Reports/<projectFolder>/<file>.pdf(recent)
    /// - v1.6 (en-v1):Reports/<projectFolder>/.archived/<file>.pdf(user archived)
    static func listArchived() -> [ArchivedReport] {
        guard let root = try? localDirectory() else { return [] }
        let fm = FileManager.default
        let iCloudRoot = iCloudDocumentsDirectory()

        var results: [ArchivedReport] = []

        // 1) 根目录里的 legacy 平铺 .pdf → 算"未分类",isUserArchived=false
        let opts: FileManager.DirectoryEnumerationOptions = []  // 必须不 skip hidden,才能看到 .archived
        if let topFiles = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .isDirectoryKey],
            options: opts
        ) {
            for url in topFiles where url.pathExtension.lowercased() == "pdf" {
                if url.lastPathComponent.hasPrefix(".") { continue }
                results.append(makeReport(
                    url: url,
                    projectFolder: unsortedFolderName,
                    isUserArchived: false,
                    iCloudRoot: iCloudRoot,
                    fm: fm
                ))
            }
            // 2) 每个子目录里的 .pdf → 算该 project + isUserArchived=false
            let subDirs = topFiles.filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                    && !url.lastPathComponent.hasPrefix(".")  // 跳过 .archived(下面单独处理)
            }
            for sub in subDirs {
                let folder = sub.lastPathComponent
                if let files = try? fm.contentsOfDirectory(
                    at: sub,
                    includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .isDirectoryKey],
                    options: opts
                ) {
                    for url in files where url.pathExtension.lowercased() == "pdf" {
                        if url.lastPathComponent.hasPrefix(".") { continue }
                        results.append(makeReport(
                            url: url,
                            projectFolder: folder,
                            isUserArchived: false,
                            iCloudRoot: iCloudRoot,
                            fm: fm
                        ))
                    }
                    // 3) 子目录里的 .archived/ → user archived
                    let archivedDir = sub.appendingPathComponent(userArchivedSubdir, isDirectory: true)
                    if fm.fileExists(atPath: archivedDir.path),
                       let archivedFiles = try? fm.contentsOfDirectory(
                           at: archivedDir,
                           includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                           options: []
                       ) {
                        for url in archivedFiles where url.pathExtension.lowercased() == "pdf" {
                            results.append(makeReport(
                                url: url,
                                projectFolder: folder,
                                isUserArchived: true,
                                iCloudRoot: iCloudRoot,
                                fm: fm
                            ))
                        }
                    }
                }
            }
            // 4) 根目录 .archived/ — 老 legacy 未分类被归档时的去处
            let topArchived = root.appendingPathComponent(userArchivedSubdir, isDirectory: true)
            if fm.fileExists(atPath: topArchived.path),
               let archivedTopFiles = try? fm.contentsOfDirectory(
                   at: topArchived,
                   includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                   options: []
               ) {
                for url in archivedTopFiles where url.pathExtension.lowercased() == "pdf" {
                    results.append(makeReport(
                        url: url,
                        projectFolder: unsortedFolderName,
                        isUserArchived: true,
                        iCloudRoot: iCloudRoot,
                        fm: fm
                    ))
                }
            }
        }

        return results.sorted { $0.createdAt > $1.createdAt }
    }

    /// v1.6 (en-v1):把 report 从 recent 标记为 user archived(移到 .archived/ 子目录)。
    /// 本地 + iCloud 镜像同步移动。
    @discardableResult
    static func markUserArchived(_ report: ArchivedReport) throws -> URL {
        return try moveReport(report, toArchived: true)
    }

    /// v1.6 (en-v1):把 report 从 user archived 还原到 recent(移出 .archived/)。
    @discardableResult
    static func markUserRecent(_ report: ArchivedReport) throws -> URL {
        return try moveReport(report, toArchived: false)
    }

    /// 内部:移动文件到 `.archived/` 或移出。
    private static func moveReport(_ report: ArchivedReport, toArchived: Bool) throws -> URL {
        let fm = FileManager.default
        let root = try localDirectory()

        // 计算目标目录:project/<.archived/>?
        let projectDir = root.appendingPathComponent(report.projectFolder, isDirectory: true)
        let destDir: URL
        if toArchived {
            destDir = projectDir.appendingPathComponent(userArchivedSubdir, isDirectory: true)
        } else {
            destDir = projectDir
        }
        if !fm.fileExists(atPath: destDir.path) {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        }
        let dest = destDir.appendingPathComponent(report.filename)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.moveItem(at: report.url, to: dest)

        // iCloud 镜像同步移动(失败静默)
        if let iCloudRoot = iCloudDocumentsDirectory() {
            let srcMirror = iCloudRoot
                .appendingPathComponent(report.projectFolder, isDirectory: true)
                .appendingPathComponent(toArchived ? "" : userArchivedSubdir, isDirectory: true)
                .appendingPathComponent(report.filename)
            let dstMirrorDir = iCloudRoot
                .appendingPathComponent(report.projectFolder, isDirectory: true)
                .appendingPathComponent(toArchived ? userArchivedSubdir : "", isDirectory: true)
            let dstMirror = dstMirrorDir.appendingPathComponent(report.filename)
            if fm.fileExists(atPath: srcMirror.path) {
                if !fm.fileExists(atPath: dstMirrorDir.path) {
                    try? fm.createDirectory(at: dstMirrorDir, withIntermediateDirectories: true)
                }
                if fm.fileExists(atPath: dstMirror.path) {
                    try? fm.removeItem(at: dstMirror)
                }
                try? fm.moveItem(at: srcMirror, to: dstMirror)
            }
        }

        return dest
    }

    /// 构造一条 ArchivedReport,顺手探测 iCloud 镜像是否存在。
    private static func makeReport(
        url: URL,
        projectFolder: String,
        isUserArchived: Bool = false,
        iCloudRoot: URL?,
        fm: FileManager
    ) -> ArchivedReport {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        let date = values?.creationDate ?? Date.distantPast
        let size = Int64(values?.fileSize ?? 0)
        let mirrorExists: Bool
        if let iCloudRoot {
            // **R6#5 关键修**:archive() 永远写到 `iCloudRoot/<folder>/<filename>`
            // (folder = "未分类" 或具体 project)。之前 makeReport 在未分类时检测 iCloud 根
            // → 永远查不到镜像 → UI 错显"未同步 iCloud"。
            // 同时兼容老数据:先查规范路径,fallback 老根路径。
            let canonical = iCloudRoot
                .appendingPathComponent(projectFolder, isDirectory: true)
                .appendingPathComponent(url.lastPathComponent)
            let legacyRoot = iCloudRoot.appendingPathComponent(url.lastPathComponent)
            mirrorExists = fm.fileExists(atPath: canonical.path) ||
                (projectFolder == unsortedFolderName && fm.fileExists(atPath: legacyRoot.path))
        } else {
            mirrorExists = false
        }
        return ArchivedReport(
            url: url,
            filename: url.lastPathComponent,
            createdAt: date,
            sizeBytes: size,
            projectFolder: projectFolder,
            hasICloudMirror: mirrorExists,
            isUserArchived: isUserArchived
        )
    }

    // MARK: - 删除

    /// 删除归档(本地 + iCloud 镜像)。
    /// R6#5:未分类 PDF 在 iCloud 可能在 `<unsortedFolderName>/<filename>`(新)或根目录
    /// `<filename>`(老 legacy)— 两条都删。
    static func delete(_ report: ArchivedReport) throws {
        try FileManager.default.removeItem(at: report.url)
        if let iCloudRoot = iCloudDocumentsDirectory() {
            let canonical = iCloudRoot
                .appendingPathComponent(report.projectFolder, isDirectory: true)
                .appendingPathComponent(report.filename)
            try? FileManager.default.removeItem(at: canonical)
            // 未分类 legacy 路径也清一遍(老用户残留)
            if report.projectFolder == unsortedFolderName {
                let legacyRoot = iCloudRoot.appendingPathComponent(report.filename)
                try? FileManager.default.removeItem(at: legacyRoot)
            }
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
