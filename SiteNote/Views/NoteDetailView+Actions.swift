//
//  NoteDetailView+Actions.swift
//  SiteNote
//
//  从 NoteDetailView.swift 拆分出来的 Actions & helpers:
//  - reschedule / softDeleteNote
//  - writeEditedPhoto / appendPhoto
//  - generateSharePDF
//  - buildAssignMessage / loadNotePhotosForAssignment / renderFloorPlanWithPin
//

import SwiftUI
import SwiftData
import UIKit

extension NoteDetailView {

    // MARK: - Actions & helpers

    func reschedule(to newDeadline: Deadline) {
        note.deadline = newDeadline
        note.dueDate = newDeadline.dueDate(from: Date())
        NotificationService.shared.schedule(for: note)
    }

    /// 软删:打 deletedAt,取消推送,不碰文件。可在设置→垃圾桶里恢复或永久删除。
    func softDeleteNote() {
        NotificationService.shared.cancel(for: note)
        note.deletedAt = Date()
        dismiss()
    }

    /// 把标注完的图覆盖回原路径(就地保存,不产生孤儿文件)。
    /// 失败时返回 false,调用方应提示"标注保存失败,原图保留"。
    @discardableResult
    func writeEditedPhoto(_ image: UIImage, toPath path: String) -> Bool {
        guard let url = PhotoStorage.absoluteURL(forRelative: path),
              let data = image.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 把一张新图保存到磁盘并加到当前 note。
    func appendPhoto(_ image: UIImage) {
        let paths = PhotoStorage.save([image])
        guard !paths.isEmpty else { return }
        note.photoPaths = note.photoPaths + paths
        galleryRefreshID = UUID()
    }

    /// 点"分享"时生成单条 note 的 PDF(不带封面),含平面图+照片。
    /// 生成完成后设 `sharePDFURL` 触发 ShareSheet。
    func generateSharePDF() {
        guard !isGeneratingShare else { return }
        isGeneratingShare = true
        // Note 是 SwiftData 模型,不是 Sendable,只能在 MainActor 上读。
        // 单条记录 PDF 生成很快(<1s),不阻塞感知。
        Task { @MainActor in
            do {
                let url = try PDFExportService.generatePDF(
                    notes: [note],
                    startDate: nil,
                    endDate: nil,
                    title: String(localized: "SiteNote 记录", locale: AppLanguageManager.currentLocale),
                    includeCoverPage: false,
                    filenamePrefix: "SiteNote-Note"
                )
                sharePDFURL = url
                isGeneratingShare = false
            } catch {
                aiError = String(localized: "分享 PDF 生成失败: \(error.localizedDescription)", locale: AppLanguageManager.currentLocale)
                isGeneratingShare = false
            }
        }
    }

    func buildAssignMessage() -> String {
        let dateStr = note.createdAt.formatted(date: .abbreviated, time: .shortened)
        let loc = note.locationAddress.map { " · \($0)" } ?? ""
        let deadlineName = note.deadline.displayName
        let deadline = String(localized: "到期: \(deadlineName)", locale: AppLanguageManager.currentLocale)
        let body = note.transcription.isEmpty ? String(localized: "(见照片)", locale: AppLanguageManager.currentLocale) : note.transcription
        var lines: [String] = ["[SiteNote \(dateStr)\(loc)]", body]
        if let tag = note.siteTag { lines.append(String(localized: "工地: \(tag)", locale: AppLanguageManager.currentLocale)) }
        if !note.otherTags.isEmpty { lines.append(String(localized: "类型: ", locale: AppLanguageManager.currentLocale) + note.otherTags.joined(separator: " / ")) }
        if let planName = note.floorPlanRef { lines.append(String(localized: "位置: 平面图 \(planName)", locale: AppLanguageManager.currentLocale)) }
        lines.append(deadline)
        lines.append(String(localized: "—— 请处理并回复。", locale: AppLanguageManager.currentLocale))
        return lines.joined(separator: "\n")
    }

    /// 收集要随指派短信发的图片:note 的照片 + 平面图(若有)。
    /// 数量限制 MMS 总大小,最多 5 张。
    func loadNotePhotosForAssignment() -> [UIImage] {
        var images: [UIImage] = []

        // 原照片(最多 3 张,给 MMS 大小留余量)
        for path in note.photoPaths.prefix(3) {
            if let url = PhotoStorage.absoluteURL(forRelative: path),
               let img = UIImage(contentsOfFile: url.path) {
                images.append(img)
            }
        }

        // 平面图带图钉(如果有)
        if let planName = note.floorPlanRef,
           let x = note.floorPlanX,
           let y = note.floorPlanY,
           let plan = FloorPlansStorage.find(name: planName),
           let url = FloorPlansStorage.absoluteURL(forRelative: plan.imageRelativePath),
           let planImage = UIImage(contentsOfFile: url.path),
           let composited = renderFloorPlanWithPin(planImage, normalizedX: x, normalizedY: y, color: pinColorForThisNote) {
            images.append(composited)
        }

        return images
    }

    /// 把平面图和图钉合成一张 UIImage,用于短信附件。
    func renderFloorPlanWithPin(
        _ image: UIImage,
        normalizedX: Double,
        normalizedY: Double,
        color: Color
    ) -> UIImage? {
        // 渲染到 1000×1000 bbox,图片 aspect fit 居中
        let canvasSize = CGSize(width: 1000, height: 1000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { _ in
            // 浅灰背景
            UIColor(white: 0.95, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()

            // Aspect fit
            let imgAspect = image.size.width / image.size.height
            let canvasAspect: CGFloat = 1.0
            let imgRect: CGRect
            if imgAspect > canvasAspect {
                let h = canvasSize.width / imgAspect
                imgRect = CGRect(x: 0, y: (canvasSize.height - h) / 2, width: canvasSize.width, height: h)
            } else {
                let w = canvasSize.height * imgAspect
                imgRect = CGRect(x: (canvasSize.width - w) / 2, y: 0, width: w, height: canvasSize.height)
            }
            image.draw(in: imgRect)

            // 图钉
            let pinX = imgRect.minX + imgRect.width * CGFloat(normalizedX)
            let pinY = imgRect.minY + imgRect.height * CGFloat(normalizedY)
            let dotRadius: CGFloat = 18
            let outerRadius: CGFloat = dotRadius + 4

            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(
                x: pinX - outerRadius,
                y: pinY - outerRadius,
                width: outerRadius * 2,
                height: outerRadius * 2
            )).fill()

            UIColor(color).setFill()
            UIBezierPath(ovalIn: CGRect(
                x: pinX - dotRadius,
                y: pinY - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )).fill()

            // 白色十字
            UIColor.white.setStroke()
            let cross = UIBezierPath()
            cross.move(to: CGPoint(x: pinX - 7, y: pinY))
            cross.addLine(to: CGPoint(x: pinX + 7, y: pinY))
            cross.move(to: CGPoint(x: pinX, y: pinY - 7))
            cross.addLine(to: CGPoint(x: pinX, y: pinY + 7))
            cross.lineWidth = 3
            cross.stroke()
        }
    }
}
