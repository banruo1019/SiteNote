//
//  MessageComposer.swift
//  SiteNote
//
//  SwiftUI 包装 MFMessageComposeViewController。预填短信发给联系人。
//  用户自己按"发送"——我们不替用户发。
//

import SwiftUI
import MessageUI

/// 短信撰写界面。支持附图(MMS)。
struct MessageComposer: UIViewControllerRepresentable {

    let recipient: String
    let body: String
    /// 附件图片(UIImage 数组,会转 JPEG)。空数组即纯文字短信。
    var attachmentImages: [UIImage] = []
    /// 用户关闭界面后的回调。`true` 表示已发送,`false` 表示取消/失败。
    let onResult: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    /// 当前设备是否能发短信(模拟器、iPad 无 SIM 会返回 false)。
    static var canSendMessages: Bool {
        MFMessageComposeViewController.canSendText()
    }

    /// 当前设备是否能发 MMS 附件。
    static var canSendAttachments: Bool {
        MFMessageComposeViewController.canSendAttachments()
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = [recipient]
        vc.body = body
        vc.messageComposeDelegate = context.coordinator

        // 附图:转 JPEG 后加进去,单张坏图不废整条短信。
        if Self.canSendAttachments {
            for (index, image) in attachmentImages.enumerated() {
                guard let data = image.jpegData(compressionQuality: 0.75) else { continue }
                vc.addAttachmentData(
                    data,
                    typeIdentifier: "public.jpeg",
                    filename: "photo-\(index + 1).jpg"
                )
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: MessageComposer

        init(_ parent: MessageComposer) {
            self.parent = parent
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            parent.onResult(result == .sent)
            parent.dismiss()
        }
    }
}
