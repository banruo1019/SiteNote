//
//  ObsidianExportService.swift
//  SiteNote
//
//  把 Note 渲染成 Obsidian-flavored markdown，导出到用户在 iCloud Drive 选的文件夹。
//  目标 vault：construction-pm 的 vault/00_Inbox/，由 intake.py 自动读取并归位。
//
//  设计：
//  - 输出 .md 文件，frontmatter 含全部结构化字段（site / hazard / location / weather / floorPlan / contractClause / assignedTo / deadline）
//  - 文件名：YYYY-MM-DD_HHMM_<site-slug>_<note-id-prefix>.md
//  - 不含音频 / 照片二进制（保持 vault 轻量）；frontmatter 留 audio_attached / photos_count 元数据
//  - 用户选目标文件夹一次（UserDefaults 记住），之后批量导出
//

import Foundation
import SwiftData

enum ObsidianExportError: LocalizedError {
    case folderNotConfigured
    case folderInaccessible(String)
    case writeFailed(String)
    case nothingToExport

    var errorDescription: String? {
        switch self {
        case .folderNotConfigured:
            return String(localized: "尚未设置 Obsidian 导出文件夹。设置 → Obsidian 导出。")
        case .folderInaccessible(let path):
            return String(localized: "文件夹无法访问：\(path)")
        case .writeFailed(let detail):
            return String(localized: "写入失败：\(detail)")
        case .nothingToExport:
            return String(localized: "没有可导出的速记。")
        }
    }
}

/// 导出结果统计。
struct ObsidianExportResult {
    let exported: Int
    let skipped: Int   // 已存在 + skipExisting=true 的数量
    let failed: [(noteID: UUID, error: String)]
}

enum ObsidianExportService {

    // ============ 配置 ============

    /// UserDefaults key（沿用 SiteNote 现有 settings.* 命名规范）。
    /// 存的是 security-scoped bookmark Data，不是字符串 path（沙盒要求）。
    static let bookmarkKey = "settings.obsidian.exportFolderBookmark"
    /// 给 UI 展示用的可读路径。
    static let displayPathKey = "settings.obsidian.exportFolderPath"

    /// 把用户在 UIDocumentPickerViewController 选的 URL 持久化为 bookmark。
    /// 在 SettingsView 里调用一次即可。
    static func persistFolder(_ url: URL) throws {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(url.path, forKey: displayPathKey)
    }

    // MARK: - Vault 迁移到开发目录的占位 helper
    //
    // 用户希望把 ~/Library/Mobile Documents/iCloud~md~obsidian/Documents/construction-pm
    // 在 Mac 端"挂"到 ~/Developer/SiteNote/obsidian-vault 下,方便统一管理。
    //
    // **iOS App 沙盒里跑不动 ln -s,且 vault 在 Mac 文件系统上,App 端无需(也无法)操作**。
    // 这个方法只是一个 **文档锚点 + 常量来源**,实际操作请用户跑 OBSIDIAN_MIGRATION.md
    // 第 3.3 节里的 shell 命令:
    //
    //   ln -s "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/construction-pm" \
    //         "$HOME/Developer/SiteNote/obsidian-vault"
    //
    // 跑完软链接后,iOS App 这边 **完全不用动** —— UserDefaults 里的 bookmark 还是指向
    // iCloud Drive 真路径,symlink 只是 Mac 端的快捷方式,对 iOS sandbox 透明。
    //
    /// 占位 helper(不执行任何文件操作)。在 OBSIDIAN_MIGRATION.md 决策落地后,
    /// 这里可以加一段"检查 symlink 是否存在并回报状态"的纯只读逻辑;但要做实际
    /// `mkdir` / `link` 操作必须用户在 macOS 终端里手动执行 —— 见上面文档锚点。
    /// - Returns: 永远返回 `false`,表示 iOS 端不处理 symlink 创建。
    @discardableResult
    static func symlinkVaultToDevDir() -> Bool {
        // 故意不做任何事:iOS 沙盒不能动 ~/Developer,Mac 端的事 Mac 端做。
        // 如果未来要做"Mac 配套 CLI",可以在这里把推荐命令以字符串形式返回出来。
        #if DEBUG
        print("[ObsidianExportService] symlinkVaultToDevDir() is a no-op stub. " +
              "See OBSIDIAN_MIGRATION.md §3.3 for the user-side shell command.")
        #endif
        return false
    }

    /// 解析回 security-scoped URL；外部使用必须包在 startAccessing... / stopAccessing... 里。
    static func resolveFolder() throws -> URL {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw ObsidianExportError.folderNotConfigured
        }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale {
                // bookmark 失效了（用户重命名了文件夹等），让用户重新选
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                throw ObsidianExportError.folderNotConfigured
            }
            return url
        } catch {
            throw ObsidianExportError.folderInaccessible(error.localizedDescription)
        }
    }

    // ============ 导出主流程 ============

    /// 批量导出。返回结果统计。
    /// - Parameter notes: 要导出的 Note 数组（已过滤）
    /// - Parameter skipExisting: 文件已存在时是否跳过（默认 true）
    @discardableResult
    static func exportNotes(_ notes: [Note], skipExisting: Bool = true) throws -> ObsidianExportResult {
        guard !notes.isEmpty else {
            throw ObsidianExportError.nothingToExport
        }

        let folder = try resolveFolder()
        let didStart = folder.startAccessingSecurityScopedResource()
        defer { if didStart { folder.stopAccessingSecurityScopedResource() } }

        var exported = 0
        var skipped = 0
        var failed: [(UUID, String)] = []

        for note in notes {
            let baseName = baseNameFor(note)
            let mdTarget = folder.appendingPathComponent(baseName + ".md")

            if skipExisting && FileManager.default.fileExists(atPath: mdTarget.path) {
                skipped += 1
                continue
            }

            do {
                // 1) 复制照片到 export 文件夹（命名带 sitenote 前缀，方便 intake 关联）
                let photoFilenames = try copyPhotos(for: note, baseName: baseName, folder: folder)
                // 2) 渲染 markdown（含 ![[]] 图片引用）
                let md = renderMarkdown(for: note, photoFilenames: photoFilenames)
                try md.write(to: mdTarget, atomically: true, encoding: .utf8)
                exported += 1
            } catch {
                failed.append((note.id, error.localizedDescription))
            }
        }

        return ObsidianExportResult(exported: exported, skipped: skipped, failed: failed)
    }

    /// 复制 note 的所有 photo 到导出文件夹，命名 `{baseName}_photo{i}.{ext}`，返回文件名数组。
    private static func copyPhotos(for note: Note, baseName: String, folder: URL) throws -> [String] {
        var out: [String] = []
        for (i, relPath) in note.photoPaths.enumerated() {
            guard let src = PhotoStorage.absoluteURL(forRelative: relPath),
                  FileManager.default.fileExists(atPath: src.path) else { continue }
            let ext = src.pathExtension.isEmpty ? "jpg" : src.pathExtension
            let destName = "\(baseName)_photo\(String(format: "%02d", i + 1)).\(ext)"
            let dest = folder.appendingPathComponent(destName)
            // 已存在则跳过（不覆盖，幂等）
            if FileManager.default.fileExists(atPath: dest.path) {
                out.append(destName)
                continue
            }
            do {
                try FileManager.default.copyItem(at: src, to: dest)
                out.append(destName)
            } catch {
                // 单张照片失败不阻断 note 导出
                continue
            }
        }
        return out
    }

    /// 单条快速导出（详情页"导到 Obsidian"按钮用）。
    static func exportSingleNote(_ note: Note) throws {
        let result = try exportNotes([note], skipExisting: false)
        if result.failed.first != nil {
            throw ObsidianExportError.writeFailed(result.failed[0].error)
        }
    }


    // ============ 文件命名 ============

    /// 不带后缀的 base name，markdown 用 .md、photos 用 _photoXX.{ext}
    private static func baseNameFor(_ note: Note) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        formatter.timeZone = .current
        let timeStr = formatter.string(from: note.createdAt)

        let siteSlug = slugify(note.siteTag) ?? "unsorted"
        let idPrefix = String(note.id.uuidString.prefix(6))

        return "sitenote_\(timeStr)_\(siteSlug)_\(idPrefix)"
    }

    private static func filenameFor(_ note: Note) -> String {
        return baseNameFor(note) + ".md"
    }

    private static func slugify(_ raw: String?) -> String? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        // 保留中英数字，其它替换为 -
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_"))
            .union(CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}"))
        let filtered = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(filtered).trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(40).description
    }

    // ============ Markdown 渲染 ============

    /// 渲染单条 Note 为完整 markdown 文档。
    /// frontmatter 字段命名跟 intake.py 的 SiteNote handler 对齐。
    /// - Parameter photoFilenames: 已复制到导出文件夹的照片文件名（不含路径），用 `![[]]` 嵌入
    static func renderMarkdown(for note: Note, photoFilenames: [String] = []) -> String {
        var lines: [String] = ["---"]

        // 来源识别（intake.py 据此走 SiteNote handler）
        lines.append("source: SiteNote")
        lines.append("sitenote_id: \(note.id.uuidString)")

        // 时间（ISO8601）
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime]
        lines.append("created: \(isoFmt.string(from: note.createdAt))")

        // 工地标签 — intake.py 用这个直接定位项目（绕过 Claude 分类）
        if let site = note.siteTag, !site.isEmpty {
            lines.append("site: \"\(yamlEscape(site))\"")
        }

        // 隐患优先级
        lines.append("hazard: \(note.isHazard)")

        // 到期 / 状态
        lines.append("deadline: \(note.deadline.rawValue)")
        lines.append("done: \(note.isDone)")

        // 合同条款（EOT 关键）
        if let clause = note.contractClauseRef, !clause.isEmpty {
            lines.append("contract_clause: \"\(yamlEscape(clause))\"")
        }

        // 分派人
        if let assignee = note.assignedTo, !assignee.isEmpty {
            lines.append("assigned_to: \"\(yamlEscape(assignee))\"")
        }

        // 其它标签
        if !note.otherTags.isEmpty {
            let tags = note.otherTags.map { "\"\(yamlEscape($0))\"" }.joined(separator: ", ")
            lines.append("other_tags: [\(tags)]")
        }

        // 位置
        if let lat = note.latitude, let lng = note.longitude {
            lines.append("location:")
            lines.append("  lat: \(lat)")
            lines.append("  lng: \(lng)")
            if let addr = note.locationAddress {
                lines.append("  address: \"\(yamlEscape(addr))\"")
            }
        }

        // 天气（EOT 证据）
        if note.weatherSummary != nil || note.temperatureCelsius != nil || note.weatherCode != nil {
            lines.append("weather:")
            if let s = note.weatherSummary { lines.append("  summary: \"\(yamlEscape(s))\"") }
            if let t = note.temperatureCelsius { lines.append("  temp_c: \(t)") }
            if let c = note.weatherCode { lines.append("  code: \(c)") }
        }

        // 平面图坐标
        if let ref = note.floorPlanRef {
            lines.append("floor_plan:")
            lines.append("  ref: \"\(yamlEscape(ref))\"")
            if let x = note.floorPlanX { lines.append("  x: \(x)") }
            if let y = note.floorPlanY { lines.append("  y: \(y)") }
        }

        // 媒体附件（不含二进制，只标记数量供 vault 端知晓）
        lines.append("audio_attached: \(note.audioFilePath != nil)")
        lines.append("photos_count: \(note.photoPaths.count)")

        lines.append("---")
        lines.append("")

        // 标题
        let titleSite = note.siteTag ?? "未分类工地"
        let titleTimeFmt = DateFormatter()
        titleTimeFmt.dateFormat = "yyyy-MM-dd HH:mm"
        let titleTime = titleTimeFmt.string(from: note.createdAt)
        let hazardPrefix = note.isHazard ? "🚨 " : ""
        lines.append("# \(hazardPrefix)\(titleSite) · \(titleTime)")
        lines.append("")

        // 正文 — 当前编辑过的 transcription
        lines.append("## 速记")
        lines.append("")
        lines.append(note.transcription.isEmpty ? "_（无内容）_" : note.transcription)
        lines.append("")

        // 照片（用 Obsidian wikilink 嵌入，文件已 copy 到同一文件夹）
        if !photoFilenames.isEmpty {
            lines.append("## 📸 照片")
            lines.append("")
            for fn in photoFilenames {
                lines.append("![[\(fn)]]")
            }
            lines.append("")
        }

        // 原始转写（如果与 polished 不同，留作证据）
        if note.transcriptionOriginal != note.transcription && !note.transcriptionOriginal.isEmpty {
            lines.append("## 原始转写（未经修标）")
            lines.append("")
            lines.append("> " + note.transcriptionOriginal.replacingOccurrences(of: "\n", with: "\n> "))
            lines.append("")
        }

        // 元信息块
        lines.append("---")
        lines.append("")
        lines.append("**来源**：SiteNote App · `\(note.id.uuidString.prefix(8))`")
        if note.audioFilePath != nil {
            lines.append("**录音**：原始 m4a 留在 iPhone 本机（备份 ZIP 才会包含）")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func yamlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
