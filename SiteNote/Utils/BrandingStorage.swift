//
//  BrandingStorage.swift
//  SiteNote
//
//  公司 Logo 存储,用于 PDF 导出时左上角带 logo。
//  存到 Documents/branding/logo.png(用户上传 → 转 UIImage → 写盘)。
//

import UIKit

enum BrandingStorage {
    private static var logoURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("branding", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("logo.png")
    }

    /// 是否设过 logo。
    static var hasLogo: Bool {
        FileManager.default.fileExists(atPath: logoURL.path)
    }

    /// 加载当前 logo;没设返回 nil。
    static func loadLogo() -> UIImage? {
        guard FileManager.default.fileExists(atPath: logoURL.path) else { return nil }
        return UIImage(contentsOfFile: logoURL.path)
    }

    /// 保存用户上传的图片。会按需缩到 max edge 1024。
    /// F9 (R4-P2-19):宽高比超出 [1:4, 4:1] 直接拒——横条 / 竖图在 PDF 左上角缩放后
    /// 要么被压成一线要么挤掉文字。失败原因写到 UserDefaults 让 SettingsView 读取。
    static func saveLogo(_ image: UIImage) -> Bool {
        let w = image.size.width
        let h = image.size.height
        guard w > 0, h > 0 else {
            recordError(String(localized: "图片尺寸无效。", locale: AppLanguageManager.currentLocale))
            return false
        }
        let aspect = w / h
        if aspect > 4.0 || aspect < 0.25 {
            recordError(String(localized: "图片宽高比过于极端,建议使用接近方形的 logo。", locale: AppLanguageManager.currentLocale))
            return false
        }

        let resized = image.resized(maxEdge: 1024)
        guard let data = resized.pngData() else {
            recordError(String(localized: "图片编码失败。", locale: AppLanguageManager.currentLocale))
            return false
        }
        do {
            try data.write(to: logoURL, options: .atomic)
            clearError()
            return true
        } catch {
            recordError(error.localizedDescription)
            return false
        }
    }

    /// F9:最近一次 saveLogo 失败原因。SettingsView 上传失败后可读这条做提示。
    /// 成功时清空。
    static var lastError: String? {
        UserDefaults.standard.string(forKey: lastErrorKey)
    }

    private static let lastErrorKey = "branding.lastError"

    private static func recordError(_ message: String) {
        UserDefaults.standard.set(message, forKey: lastErrorKey)
        print("[SiteNote] BrandingStorage.saveLogo failed: \(message)")
    }

    private static func clearError() {
        UserDefaults.standard.removeObject(forKey: lastErrorKey)
    }

    /// 清掉用户的 logo。
    @discardableResult
    static func clearLogo() -> Bool {
        try? FileManager.default.removeItem(at: logoURL)
        return !FileManager.default.fileExists(atPath: logoURL.path)
    }
}

private extension UIImage {
    /// 等比缩到最长边 = maxEdge,小图不放大。
    func resized(maxEdge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return self }
        let scale = maxEdge / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
