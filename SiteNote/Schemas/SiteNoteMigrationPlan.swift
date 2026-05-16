//
//  SiteNoteMigrationPlan.swift
//  SiteNote
//
//  Schema 演进路线图。SiteNoteApp.initContainer() 在 ModelContainer 初始化时
//  传入此 plan,SwiftData 据此决定是否需要 migration、走哪个 stage。
//
//  V1 → V2:**lightweight**(只加表,不改字段)。SwiftData 自动迁移,旧用户
//  数据保留,新表初始为空。
//
//  以后加表(v1.3 想加什么)走 V2 → V3 lightweight。改字段才需要 custom stage。
//

import Foundation
import SwiftData

enum SiteNoteMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            SiteNoteSchemaV1.self,
            SiteNoteSchemaV2.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: SiteNoteSchemaV1.self,
                toVersion: SiteNoteSchemaV2.self
            ),
        ]
    }
}
