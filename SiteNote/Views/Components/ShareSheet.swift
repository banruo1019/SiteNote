//
//  ShareSheet.swift
//  SiteNote
//
//  SwiftUI 包装的 UIActivityViewController。
//

import SwiftUI
import UIKit

/// 系统分享面板。接受任意可分享项（文本、URL、图片等）。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// 用户成功完成分享后的回调（取消不会触发）。
    var onComplete: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in
            if completed {
                onComplete()
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
