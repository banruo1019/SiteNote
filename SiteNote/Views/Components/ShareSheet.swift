//
//  ShareSheet.swift
//  SiteNote
//
//  SwiftUI 包装的 UIActivityViewController。
//

import SwiftUI
import UIKit

/// 系统分享面板。接受任意可分享项(文本、URL、图片等)。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// 用户成功完成分享后的回调(取消不会触发)。
    var onComplete: () -> Void = {}
    /// 完整完成回调,带 activityType(可空)+ completed 标志。
    /// 用于 ShareLog 记录:外部传 closure 时,本组件就把分享事件落到 SwiftData。
    var onActivity: ((_ activityType: String?, _ completed: Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { activity, completed, _, _ in
            if completed { onComplete() }
            onActivity?(activity?.rawValue, completed)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
