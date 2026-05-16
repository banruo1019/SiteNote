//
//  SiteNoteSchemaV1.swift
//  SiteNote
//
//  Schema V1 — 对齐 App Store v1.0 build 2 已发布版本。
//  3 张表:Note / LogEntry / ShareLog。
//
//  **重要**:V1 是真实生产数据的形态,任何改动都会让 v1.0 用户升级时
//  schema mismatch。一旦在 v1.0 上 archive 过,这个 enum 就是只读历史。
//
//  字段从 v1.0 → 当前主分支唯一变化是给 non-optional 字段加了 default value,
//  这在 SQLite 层不算 schema 改动(SwiftData/CoreData 允许 default value 演进)。
//  所以 V1 直接引用顶层 Note.self / LogEntry.self / ShareLog.self,
//  不需要嵌套 V1 类型。
//

import Foundation
import SwiftData

enum SiteNoteSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            Note.self,
            LogEntry.self,
            ShareLog.self,
        ]
    }
}
