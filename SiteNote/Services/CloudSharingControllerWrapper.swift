//
//  CloudSharingControllerWrapper.swift
//  SiteNote
//
//  UICloudSharingController 的 SwiftUI 包装。用于团队 Owner 邀请成员。
//
//  ⚠️ Phase 0(2026-05-16):prototype。需要 iCloud entitlement + ModelContainer 接 CloudKit 才能真用。
//  Phase 2 接通后,从 TeamManagementView 的"邀请成员"按钮调用。
//
//  参考:Apple sample-cloudkit-sharing (https://github.com/apple/sample-cloudkit-sharing)
//

import SwiftUI
import CloudKit
import UIKit

/// Owner 邀请新成员时弹这个 controller。
/// - share: 已存在的 CKShare(如果团队还没 share,先 prepare 一个再传入)
/// - container: CKContainer.default()
struct CloudSharingControllerView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onAdd: ((CKShare) -> Void)?     // 邀请发出后 callback
    let onRemove: (() -> Void)?         // 取消 sharing
    let onStop: (() -> Void)?           // owner stop sharing

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let parent: CloudSharingControllerView

        init(_ parent: CloudSharingControllerView) {
            self.parent = parent
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("[CloudSharing] save failed: \(error.localizedDescription)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            return csc.share?[CKShare.SystemFieldKey.title] as? String ?? "SiteNote Team"
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            if let share = csc.share {
                parent.onAdd?(share)
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            parent.onStop?()
        }
    }
}

// MARK: - Share 创建/获取辅助

/// CloudKit Sharing 业务逻辑封装。Phase 2 才真使用。
enum TeamSharingService {
    /// Container ID — 必须跟 entitlements 里配的一致。
    /// Phase 1c 文档 ICLOUD_SETUP.md 会指导用户在 Xcode 加 iCloud capability 并设置 container ID。
    static let containerID = "iCloud.com.banruo.SiteNote"

    static var defaultContainer: CKContainer {
        CKContainer(identifier: containerID)
    }

    /// 为给定 record 创建一个新 CKShare。
    /// 在 Owner 第一次"创建团队"按钮被点时调用,然后弹 CloudSharingControllerView。
    static func prepareShare(for rootRecord: CKRecord, title: String) -> CKShare {
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "com.banruo.SiteNote.team" as CKRecordValue
        share.publicPermission = .none  // 必须邀请,URL 漏出去也没用
        return share
    }

    /// 接受邀请(由 SceneDelegate 的 userDidAcceptCloudKitShareWith 调用)。
    static func acceptShareInvitation(meta: CKShare.Metadata, completion: @escaping (Result<CKShare, Error>) -> Void) {
        let operation = CKAcceptSharesOperation(shareMetadatas: [meta])
        operation.perShareResultBlock = { _, result in
            switch result {
            case .success(let share):
                DispatchQueue.main.async { completion(.success(share)) }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        defaultContainer.add(operation)
    }

    /// 通过 CKShare 拿到所有 participants(Owner 看成员列表用)。
    static func participants(of share: CKShare) -> [CKShare.Participant] {
        return share.participants
    }

    /// Owner 移除 participant。
    static func removeParticipant(_ participant: CKShare.Participant, from share: CKShare) {
        share.removeParticipant(participant)
    }
}
