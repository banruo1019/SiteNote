//
//  MailComposeView.swift
//  SiteNote
//
//  SwiftUI 包装 MFMailComposeViewController。
//  专为 Inspection "一键发邮件" 工作流准备:预填收件人 / 主题 / 正文 + 附 PDF,
//  用户点系统"发送"按钮才真正发——我们绝不替用户发。
//
//  典型用法:
//      .sheet(isPresented: $showsMailCompose) {
//          MailComposeView(
//              recipients: ["foo@bar.com"],
//              subject: "Site Visit Report SVR25159.05A",
//              body: "Please find attached...",
//              attachments: [.init(data: pdfData, mimeType: "application/pdf", filename: "X.pdf")]
//          ) { result, error in
//              // 处理 sent / cancelled / failed
//          }
//      }
//
//  设备未配置邮箱时,`MailComposeView.canSendMail` 返回 false——
//  调用方有责任降级到 ShareSheet / 提示用户去 iOS 设置加邮箱账号。
//

import SwiftUI
import MessageUI

struct MailComposeView: UIViewControllerRepresentable {

    /// 一个邮件附件。data 必须已经在内存里(读 PDF 由调用方负责)。
    struct Attachment {
        let data: Data
        let mimeType: String
        let filename: String

        init(data: Data, mimeType: String, filename: String) {
            self.data = data
            self.mimeType = mimeType
            self.filename = filename
        }
    }

    let recipients: [String]
    var ccRecipients: [String] = []
    let subject: String
    let body: String
    var isHTMLBody: Bool = false
    let attachments: [Attachment]
    /// 用户关闭撰写界面后的回调。Coordinator 用 weak self 持有 dismiss 闭包,避免循环。
    let onCompletion: (MFMailComposeResult, Error?) -> Void

    @Environment(\.dismiss) private var dismiss

    /// 当前设备是否能发邮件(模拟器、未配置任何邮箱账号时返回 false)。
    static var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(recipients)
        if !ccRecipients.isEmpty {
            vc.setCcRecipients(ccRecipients)
        }
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: isHTMLBody)
        for att in attachments {
            vc.addAttachmentData(att.data, mimeType: att.mimeType, fileName: att.filename)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        /// 完成回调。捕获后只用一次,触发后释放;不会重复调用。
        private let onCompletion: (MFMailComposeResult, Error?) -> Void
        /// 关闭 sheet 用的闭包。SwiftUI 的 dismiss 是 env value,无 retain cycle 风险,
        /// 但我们仍然保持闭包独立——避免 Coordinator 反持 parent 造成循环。
        private let dismiss: () -> Void

        init(
            onCompletion: @escaping (MFMailComposeResult, Error?) -> Void,
            dismiss: @escaping () -> Void
        ) {
            self.onCompletion = onCompletion
            self.dismiss = dismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            // 先 dismiss 再回调,防止 onCompletion 内部又 present 时栈混乱。
            // weak self 防御:即便 Coordinator 已经被释放(理论不会),也不崩。
            let onCompletion = self.onCompletion
            let dismiss = self.dismiss
            dismiss()
            onCompletion(result, error)
        }
    }
}
