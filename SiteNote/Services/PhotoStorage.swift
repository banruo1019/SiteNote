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
