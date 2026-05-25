//
//  PhotoStorage.swift
//  SiteNote
//
//  把 UIImage 压缩为 JPEG 保存到 Documents/photos/，返回相对路径。
//

import Foundation
import UIKit

/// 照片文件管理。只做"保存"和"路径转绝对 URL"两件事。
enum PhotoStorage {

    /// JPEG 压缩质量（0-1）。0.8 在质量和体积间平衡。
    static let jpegQuality: CGFloat = 0.8

    /// 把一组 UIImage 保存为 .jpg 到 Documents/photos/。
    /// 单张失败会被跳过，不抛错，不影响其他张。
    /// - Parameter images: 要保存的图像。
    /// - Returns: 每张对应的相对路径（如 "photos/UUID.jpg"）。
    static func save(_ images: [UIImage]) -> [String] {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return []
        }
        let photoDir = docs.appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: photoDir,
            withIntermediateDirectories: true
        )

        var paths: [String] = []
        for image in images {
            guard let data = image.jpegData(compressionQuality: jpegQuality) else { continue }
            let filename = "\(UUID().uuidString).jpg"
            let url = photoDir.appendingPathComponent(filename)
            do {
                try data.write(to: url)
                paths.append("photos/\(filename)")
            } catch {
                continue
            }
        }
        return paths
    }

    /// 性能优化:预先生成 UUID 文件名(主线程瞬时,不做 I/O)。
    /// 调用方先用这些路径写到 Note,触发 navigation;真正的 JPEG 编码 + 落盘
    /// 用 `saveImages(_:toRelativePaths:)` 在后台串行执行。
    /// 落盘窗口期(几十毫秒)与 NavigationStack push 动画(~400ms)重叠,
    /// 用户走到详情页时文件已就绪。
    /// - Parameter count: 需要预留的张数。
    /// - Returns: 形如 ["photos/<UUID>.jpg", ...] 的相对路径数组。
    static func reservePaths(count: Int) -> [String] {
        guard count > 0 else { return [] }
        return (0..<count).map { _ in "photos/\(UUID().uuidString).jpg" }
    }

    /// 把 `images` 按 1:1 写到对应 `paths`。images.count 与 paths.count 必须相等。
    /// 用于先 reservePaths → 写到 Note → 后台落盘的延迟优化路径。
    /// 调用方应在后台线程调用(此函数纯 CPU/Disk,可安全并发)。
    /// - Parameters:
    ///   - images: 待写入图像。
    ///   - paths: reservePaths 返回的相对路径数组。
    /// - Returns: 实际写盘成功的相对路径(写失败的被剔除,调用方可据此修剪 Note.photoPaths)。
    @discardableResult
    static func saveImages(_ images: [UIImage], toRelativePaths paths: [String]) -> [String] {
        guard images.count == paths.count, !images.isEmpty else { return [] }
        guard let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return []
        }
        let photoDir = docs.appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: photoDir,
            withIntermediateDirectories: true
        )

        var written: [String] = []
        for (image, relative) in zip(images, paths) {
            guard let data = image.jpegData(compressionQuality: jpegQuality) else { continue }
            let url = docs.appendingPathComponent(relative)
            do {
                try data.write(to: url)
                written.append(relative)
            } catch {
                continue
            }
        }
        return written
    }

    /// 把相对路径转成绝对 URL（读取/展示时用）。
    /// - Parameter relative: 相对 Documents 的路径。
    /// - Returns: 绝对 URL；无法构造时为 `nil`。
    static func absoluteURL(forRelative relative: String) -> URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return docs.appendingPathComponent(relative)
    }
}
