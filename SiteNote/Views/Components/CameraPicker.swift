//
//  CameraPicker.swift
//  SiteNote
//
//  UIImagePickerController 的 SwiftUI 包装，用于拍照。
//  SwiftUI 原生 PhotosPicker 不支持相机，只能走 UIKit 这条路。
//

import SwiftUI
import UIKit

/// 拍照相机界面。调出系统相机，用户拍一张后写入 `image` 绑定。
///
/// 使用示例：
/// ```swift
/// .sheet(isPresented: $showCamera) {
///     CameraPicker(image: $capturedImage)
/// }
/// ```
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
