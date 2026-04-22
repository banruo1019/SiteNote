//
//  ContactPicker.swift
//  SiteNote
//
//  SwiftUI 包装 CNContactPickerViewController。选联系人用。
//  不需要通讯录权限——系统在独立进程提供选择 UI,类似 PhotosPicker。
//

import SwiftUI
import ContactsUI
import Contacts

/// 联系人选择器。只显示有电话号码的联系人。
struct ContactPicker: UIViewControllerRepresentable {

    /// 选中回调。参数:联系人显示名 + 第一个电话号码(可能为 nil)。
    let onSelect: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count > 0")
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPicker

        init(_ parent: ContactPicker) {
            self.parent = parent
        }

        func contactPicker(
            _ picker: CNContactPickerViewController,
            didSelect contact: CNContact
        ) {
            let fullName = "\(contact.givenName) \(contact.familyName)"
                .trimmingCharacters(in: .whitespaces)
            let displayName = fullName.isEmpty ? contact.organizationName : fullName
            let phone = contact.phoneNumbers.first?.value.stringValue
            parent.onSelect(displayName, phone)
            parent.dismiss()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.dismiss()
        }
    }
}
