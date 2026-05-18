# SiteNote 云端数据流(P1 #179 决策记录)

## 背景

当前 SiteNote 同时启用了两条云端同步链路:

1. **SwiftData CloudKit auto-sync** — `SiteNoteApp` 把 `SiteNoteSchemaV2.models` 全部交给 `.private(containerID)` 配置,SwiftData 自动把每个 @Model 实例推到当前用户的 private DB 的 `com.apple.coredata.cloudkit.zone`(record type `CD_<ModelName>`)。

2. **Raw CKShare zone mirror** — `TeamDataMirrorService` 把 `SitePreset` / `SiteVisitSchedule` / `InspectionReport`(以及 `Team` / `TeamMember`)推到 Owner 创建的自定义 zone(zoneName = `team.id.uuidString`,record type `SiteNoteXxx`),并通过 zone-wide `CKShare` 让 Member 跨 Apple ID 访问。

两条链路对**同一个 @Model 实例**写**两条独立的 CKRecord**(record type、zone、recordID 都不同),CloudKit 层面物理隔离,**不会直接冲突**。

## 决策(2026-05-18 自主整改 R6)

**不拆 ModelConfiguration** — SwiftData iOS 17/18 的 ModelConfiguration 是 schema 级别,拆分会破坏现有用户多设备同步。两条链路并存,角色明确分工:

| 链路 | 事实源场景 | 触发时机 |
|---|---|---|
| SwiftData CloudKit auto-sync | **同账号多设备**(Owner 在 iPad + iPhone) | SwiftData @Model 任何改动自动 |
| CKShare zone mirror | **跨账号协作**(Owner ↔ Foreman/Member) | 显式 `mirrorXxx(in:)` 调用 |

## 双写规则(必须遵守)

**每一次 SwiftData @Model 改动(insert / update / soft delete)都必须调对应的 `mirrorXxx`**:
- 否则只走 SwiftData CloudKit(同账号多设备 OK,但团队成员看不到)
- 已修补 mirror trigger:`start / end / attachIfNeeded / resume / saveDraft / suspendAsDraft / markCompleted / markPending / markCancelled / deleteSchedule / softDelete(report) / performDelete(report) / ScheduleEditorSheet.save / SitePresetEditor 保存 / EngineerScheduleView markAsSubmitted`

**Mirror 进来的 record(从 share zone 拉到本地 SwiftData)**:
- `upsertXxx` 调 `modelContext.insert / update`
- SwiftData CloudKit 会自动把这条"外来"record 当作本设备的 @Model 实例,推到自己的 private DB SwiftData zone
- 后果:Owner 主设备 mirror 进来的 Member's report,在 Owner 副设备能通过 SwiftData CloudKit 看到(无需另一次 fetchAndSyncAll)

## 已知边界 case

### 删除后再被回填

- 场景:Owner 软删 mirror 进来的 report,SwiftData auto-sync 推 deletion 到 Owner 私有 SwiftData zone
- 副设备 SwiftData sync 拉到 deletion → 也软删
- 但 **share zone 里这条 record 还在**(Member push 的;`mirrorReport` 已修补会推 `deletedAt` 字段)
- 副设备下次 `fetchAndSyncAll` 拉 share zone changes 拉到 record(deletedAt 字段已写) → `upsertReport` 更新 `target.deletedAt = ...` → 软删保持
- **依赖**:`mirrorReport` 必须把 `deletedAt` 写入 CKRecord(已实现,L207 后),不要只写 nil 跳过
- **风险**:如果 Owner 端 mirror push 失败(无网),deletedAt 没传到 share zone,下次 fetch 拉回 record 时 deletedAt 又是 nil → record 被"复活"。当前 mirror 失败只 log 不重试 → **待解决**(写入 retry queue 或保证 background task 等网恢复)

### Member 端的 record 在 SwiftData zone 里有 ghost
- Member 自己创建 report → SwiftData CloudKit 推到 Member private DB
- Member 自己的副设备能看到(单账号多设备同步)
- Owner 通过 share zone 也能看到 — 但 Owner 拉进自己 SwiftData → SwiftData CloudKit 推到 Owner private DB
- 最终 record 在三处都有 CKRecord:Member private DB / Owner private DB / share zone
- 浪费 quota 但**不冲突**

## v1.x 后续路线(beta 之后)

考虑拆 ModelConfiguration 把团队相关 @Model 隔离出 SwiftData CloudKit auto-sync:
- 优点:删 SwiftData zone 副本,share zone 成为唯一事实源
- 缺点:同账号多设备同步要 fetchAndSyncAll 显式跑,不再"自动透明"
- 触发条件:用户报 "iPad 看到 iPhone 没的数据" 这种 SwiftData ↔ share zone 漂移 case 时再做

## 验证

- `xcodebuild -project SiteNote.xcodeproj -scheme SiteNote -destination 'generic/platform=iOS Simulator' build` → BUILD SUCCEEDED(R6)
- 真机 CloudKit 验证:Owner 端软删一份 Member's report → 等 10 秒 → Member 端 fetchAndSyncAll → 应该看到 record 软删
- 真机:Owner 主设备解散团队 → Owner 副设备应该在 SwiftData auto-sync 拉到 deletion 后 5-30s 内 UI 看不到 Team
