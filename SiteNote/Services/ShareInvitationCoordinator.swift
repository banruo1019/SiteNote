//
//  ShareInvitationCoordinator.swift
//  SiteNote
//
//  接收系统传来的 CKShare.Metadata(用户从 Messages/Mail/等点了 share URL 后)。
//  通过 NotificationCenter 把 metadata 派发给 RootContainerView,后者拿到
//  ModelContext 后调 TeamCloudKitService.acceptShareInvitation。
//
//  ## 流程
//
//  1. AppDelegate / SceneDelegate 收到 `userDidAcceptCloudKitShareWith` 回调
//  2. 把 metadata 包成 .shareInvitationReceived notification 抛出
//  3. RootContainerView .onReceive 收到 → 拿 container.mainContext → 调 service
//  4. 显示成功/失败 alert
//

import Foundation
import CloudKit
import UIKit

/// share invitation 派发通道。
extension Notification.Name {
    /// userInfo["metadata"] = CKShare.Metadata
    static let shareInvitationReceived = Notification.Name("com.banruo.sitenote.shareInvitationReceived")
}

/// UIApplicationDelegate 实现:负责把 share invitation 派发出去。
/// SiteNoteApp 用 @UIApplicationDelegateAdaptor 注入。
final class SiteNoteAppDelegate: NSObject, UIApplicationDelegate {

    /// 入口:scene-based App,这里把 SceneDelegate 类型告诉系统。
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SiteNoteSceneDelegate.self
        return config
    }
}

/// UIWindowSceneDelegate:接 share invitation。
/// 不实现 scene(_:willConnectTo:options:) — 让 SwiftUI 自己接管 window。
final class SiteNoteSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    /// 系统在用户接受 share URL 后调这里。把 metadata 派发给 SwiftUI 层。
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        NotificationCenter.default.post(
            name: .shareInvitationReceived,
            object: nil,
            userInfo: ["metadata": cloudKitShareMetadata]
        )
    }
}
