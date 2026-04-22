//
//  ShareLog.swift
//  SiteNote
//
//  分享/导出事件的轻量审计表。
//
//  iOS 的 UIActivityViewController 是黑盒——我们不知道用户把 PDF 发给了谁,
//  能拿到的只有 activityType(如 "com.apple.UIKit.activity.Mail" 或第三方 App bundleID)
//  和"是否完成"。所以这里只记 channel 级别的统计。
//
//  价值:
//    - 设置页能显示"上次分享 X 时,共分享 N 次"——增长性指标
//    - 可以在未来加"每周自动汇总"——产品的 last-mile 闭环度量
//

import Foundation
import SwiftData

@Model
final class ShareLog {
    var id: UUID
    /// 分享发生时间。
    var sharedAt: Date
    /// "site-diary" / "single-note-pdf" / "weekly-summary" / 其他。
    var format: String
    /// UIActivityType.rawValue,可能为 nil(系统不返回 / 用户取消)。
    var activityType: String?
    /// 是否成功完成(UIActivityViewController completion 的 completed 参数)。
    var completed: Bool
    /// 涉及的 Note ID 列表(JSON 字符串)。空表示纯日终汇总。
    var noteIDsJSON: String?

    init(
        format: String,
        activityType: String? = nil,
        completed: Bool = true,
        noteIDs: [UUID] = []
    ) {
        self.id = UUID()
        self.sharedAt = Date()
        self.format = format
        self.activityType = activityType
        self.completed = completed
        self.noteIDsJSON = noteIDs.isEmpty
            ? nil
            : (try? JSONEncoder().encode(noteIDs.map { $0.uuidString })).flatMap {
                String(data: $0, encoding: .utf8)
            }
    }

    /// activityType 解析成可读名(给 UI 显示)。
    var channelLabel: String {
        guard let raw = activityType else { return "未知" }
        if raw.contains("Mail") { return "邮件" }
        if raw.contains("Message") { return "短信" }
        if raw.contains("WeChat") || raw.contains("wechat") { return "微信" }
        if raw.contains("WhatsApp") || raw.contains("whatsapp") { return "WhatsApp" }
        if raw.contains("AirDrop") { return "AirDrop" }
        if raw.contains("CopyToPasteboard") { return "复制" }
        if raw.contains("SaveToCameraRoll") || raw.contains("Photos") { return "存到相册" }
        return raw.split(separator: ".").last.map(String.init) ?? "其他"
    }
}
