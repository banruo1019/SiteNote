//
//  ICloudSyncConfig.swift
//  SiteNote
//
//  iCloud 备份 + CloudKit 同步配置开关。
//
//  ⚠️ 设计:用 feature flag 控制,默认 disabled。用户在 Xcode 加 iCloud capability
//  + 在 ICLOUD_SETUP.md 走完清单后,通过 ICloudSyncConfig.shared.isEnabled = true 启用。
//
//  Phase 1 完成后,SiteNoteApp.swift 会在 initContainer() 里根据 isEnabled 选择
//  CloudKit private DB 或本地 only。
//

import Foundation
import SwiftData
import CloudKit

@Observable
final class ICloudSyncConfig {
    static let shared = ICloudSyncConfig()
    private init() {}

    /// CloudKit container 标识。需要跟 entitlements 里配的完全一致。
    static let containerID = "iCloud.com.banruo.SiteNote"

    /// UserDefaults key,用户在 Xcode 加 iCloud capability + 真机测试 OK 后启用。
    private static let userDefaultsKey = "icloud.syncEnabled.v1"

    /// 当前是否启用 iCloud 同步。
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.userDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.userDefaultsKey) }
    }

    /// ModelConfiguration 的 CloudKit 配置(SwiftData 兼容)。
    /// 在 SiteNoteApp.initContainer 里:
    ///   let config = ICloudSyncConfig.shared.isEnabled
    ///       ? ICloudSyncConfig.cloudKitConfiguration(schema: schema)
    ///       : ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    @MainActor
    static func cloudKitConfiguration(schema: Schema) -> ModelConfiguration {
        return ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(containerID)
        )
    }

    /// CKContainer 句柄,Phase 2 TeamSharingService 用。
    var ckContainer: CKContainer {
        CKContainer(identifier: Self.containerID)
    }

    /// 用户 Apple ID(同步过来才有,本地模式 nil)。
    /// 后续团队功能(SitePreset.assignedToUserID 等)用此判断当前用户身份。
    var currentUserRecordName: String? {
        get { UserDefaults.standard.string(forKey: "icloud.currentUserRecordName.v1") }
        set { UserDefaults.standard.set(newValue, forKey: "icloud.currentUserRecordName.v1") }
    }

    /// 异步获取当前 user record(用于初次登录后缓存到 currentUserRecordName)。
    ///
    /// 注意:这里不能受 `isEnabled` 限制。`isEnabled` 只控制 SwiftData private
    /// CloudKit 自动同步,但团队协作使用 raw CKShare/sharedDB;即使用户没有打开
    /// SwiftData iCloud 同步,团队 owner/member 身份判断仍然必须能拿到 userRecordID。
    func fetchAndCacheUserRecord() async throws {
        let recordID = try await ckContainer.userRecordID()
        await MainActor.run {
            self.currentUserRecordName = recordID.recordName
        }
    }
}
