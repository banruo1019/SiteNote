# 团队协作 v2 — 完成状态 + 测试指南

**日期**:2026-05-17
**版本**:v1.6 团队 v2(基于 Audit 后的方案 B' = SwiftData @Model + raw CKShare mirror)

---

## 完成清单

### Phase 1 ✅ SitePreset → @Model
- `SitePreset` struct + UserDefaults JSON → @Model class(SwiftData)
- `SwiftDataStack` 全局单例,SiteNoteApp init 时 register
- `SitePresetStorage` 保留 facade(所有 25+ callers 0 改动)内部走 SwiftData
- 启动一次性迁移老 UserDefaults JSON → SwiftData,idempotent flag 防重跑
- Schema 注册 `SitePreset.self`

### Phase 2 ✅ TeamDataMirrorService 创建
- 新 service 处理跨用户 mirror(`SiteNote/Services/TeamDataMirrorService.swift`)
- 3 个 mirror APIs:`mirrorSitePreset` / `mirrorSchedule` / `mirrorReport`
- 写时按 `isOwner(of:)` 决定 privateDB(owner) / sharedDB(member)
- 失败 silent + log,不阻塞 UI

### Phase 3 ✅ 双向 sync(fetchAndSyncAll)
- `fetchAndSyncAll(in:)` 拉当前 team zone 自上次 server token 以来的 changes
- upsert 进本地 SwiftData(SitePreset / Schedule / Report / **Team** / **TeamMember**)
- 软删:云端删的 record 本地标 `deletedAt`
- `CKServerChangeToken` UserDefaults 持久化,增量 sync 省流量
- 触发点:
  - `RecordView.task` / `EngineerScheduleView.task` / `EngineerReportsView.task` — 进入 view 时拉
  - `acceptShareInvitation` 末尾(首次全量)

### Phase 4 ✅ TeamMember 注册闭环
- Member acceptShare 时 **`registerSelfAsMember`** 主动往 share zone 写一条自己的 TeamMember CKRecord
- Owner 下次 `fetchAndSyncAll` 拉到 → 本地 SwiftData 多一条 TeamMember
- → Owner 的 SitePresetEditor 分配 Picker `@Query teamMembers` 自动看到 Member
- 分配建 schedule 后自动 fire `mirrorSchedule` + `mirrorSitePreset`,Member 下次进 view 拉到 → 自动出现「新工地」+ NEW badge + local notification

### 数据流(端到端)
```
Owner 加 SitePreset → SitePresetStorage.add → fireMirror → CKRecord 写 privateDB team zone
                                                                          ↓ CloudKit sync
Member 进 view → fetchAndSyncAll → 拉 zone changes → upsertSitePreset → 本地 @Query 更新 → UI 自动刷新

Owner 在分配 picker 选 Member → modelContext.insert(SiteVisitSchedule) → mirrorSchedule
                                                                          ↓ CloudKit
Member 进 view → fetchAndSyncAll → upsertSchedule → @Query allSchedules 多一条
                                                  → TeamAssignmentNotifier 弹 local notification + NEW badge

Member 完成巡检 → InspectionSessionManager.start/end → mirrorReport(写 sharedDB)
                                                                          ↓ CloudKit
Owner 进 Reports Tab → fetchAndSyncAll → upsertReport → @Query allReports 多一条 → 「团队全部」段看到 + 「by Member」副标
```

---

## 测试指南(更新版,覆盖之前的 TEAM_TEST.md)

### 准备
- 两个 iCloud 账号(2 台真机推荐)
- 两台手机 Xcode 装同一 build(同 Bundle ID + 同 Team sign)
- Info.plist 已有 `CKSharingSupported = true`(v1.6 加的)
- 两台都设置 → 我是 → 填「我的名字」(例 Sam / Jamie)
- 两台都设置 → iCloud 同步 toggle on + 完全杀掉 App 重开

### 流程

**1. Owner (Sam) 创建团队**
- 设置 → 团队 → 创建团队 → 输团队名 → 弹 UICloudSharingController → 选「邮件」发给 Jamie 的 iCloud 邮箱

**2. Member (Jamie) 接受邀请**
- 邮箱点链接 → 系统弹「在 SiteNote 打开」→ 允许
- App 启动,弹「已加入团队」alert
- 后台:`acceptShareInvitation` → mirror Team/TeamMember 到 Jamie 本地 → `registerSelfAsMember` 把 Jamie 写回 share zone → `fetchAndSyncAll` 拉所有 records

**3. Owner 拉新 Member**
- Sam 把 App 切到后台再切回(触发 `.task`),或者直接进入「记」Tab → `fetchAndSyncAll` 拉新 zone changes → 拉到 Jamie 写的 TeamMember → Sam 本地多一条 → 设置 → 团队 应该看到 2/10 成员

**4. Owner 分配工地**
- Sam:设置 → 工地 → 「+」新建一个工地(例 `123 Sample St, Sydney NSW 2000`)
- 编辑工地 → 滚到「团队分配」段 → 选「Jamie」→ 保存
- 后台:`assignToMember` → 写 SitePreset + 建 SiteVisitSchedule → fire mirror 两个 entity 到 share zone

**5. Member 看到分配 + 自动建日程**
- Jamie 进入 App / 切到「记」Tab → `fetchAndSyncAll` 拉新 → 本地多 1 个 SitePreset + 1 个 SiteVisitSchedule
- `TeamAssignmentNotifier.scanAndNotify` 触发 → 弹本地通知「新工地分配:你被分配到「123 Sample St」」
- 「日程」Tab 可以看到该 schedule,行头有橙色 NEW chip
- 主屏「今日巡检」列表也可看到该工地

**6. Member 做巡检 + 报告**
- Jamie 点该日程 → 「▶ 开始巡检」 → 录音/拍照 → 「✓ 完成巡检」 → 发邮件 / 暂存草稿
- 后台:`InspectionSessionManager.start/end` → fire `mirrorReport` → CKRecord 写 sharedDB

**7. Owner 看到 Member 报告**
- Sam 切「报告」Tab → 顶部应该出现「我的 / 团队全部」segmented(因有 Team)
- 默认「我的」看不到 Jamie 的;切「团队全部」→ 看到 Jamie 的报告,副标末尾「by Jamie」灰字
- 点进去 → 完整 report + notes + 可以「重新预览 PDF」/「再发一次邮件」

---

## 已知 v1 局限(MVP 范围内可接受)

| 项目 | 状态 | 说明 |
|---|---|---|
| Contact / Builder 通讯录共享 | ❌ 未实现 | 还是 struct + UserDefaults,Member 端看 SitePreset 的 linkedContactIDs 反查不到 → 显示"未知联系人" |
| Note 实例共享 | ❌ 未实现 | InspectionReport.noteIDs 索引同步了,但 Note 本身在 Member 端拉不到。Member 点报告里的 note 详情可能空 |
| Push notification | ❌ 用 polling | 现在用进 view 时 `.task` 拉 = polling-on-foreground;后台不会有 push。**所以 Member 必须打开 App 才能看到新分配**。后续可加 CKDatabaseSubscription |
| Member 删除 / 离队 | ⚠️ 部分 | Team CKShare 解除有 owner / member 双向 API;UI 只有 owner 解散流程,member 主动离队没暴露 |
| 冲突处理 | ⚠️ Last-write-wins | 两人同时改同 record 走 CloudKit 默认 LWW,无显式冲突 UI |
| iCloud 不可用(没登 / 没网) | ✅ Fallback | 单机功能正常,mirror 静默失败 + log;网恢复后下次 mirror 重试 |

---

## Production 上线 Checklist(给你做)

CloudKit 在 Development 环境(Xcode debug build)能跑,但 App Store 发版需要 deploy 到 Production:

### Apple Developer 后台
1. **CloudKit Dashboard** → 选 container `iCloud.com.banruo.SiteNote` → **Deploy Schema to Production**
   - 把 Development 环境所有 record types 推到 Production
   - 必须做!否则发版后所有 mirror 写云端会失败(record type 不存在)
2. **APS Push certificate**(如果未来加 push)— 现在用 polling 不需要

### Xcode 配置
3. **entitlements** — `SiteNote.entitlements` 的 `aps-environment` Archive 上传时自动切 `production`(Xcode 自动管,通常不用动)
4. **CloudKit container** — entitlements 已有 `iCloud.com.banruo.SiteNote`,不动

### App Store Connect
5. 上传新 build → TestFlight 内部测试 → 多个 iCloud 账号真机验同 production
6. 测试 production 环境(注意 development records **不会** appear in production)

---

## 真机测试 troubleshooting

### Member 不接收 TeamMember 同步
- Owner 端:把 App 杀掉重开 → `.task` 触发 `fetchAndSyncAll`(`recordZoneChanges` 拉)
- 如果 Owner 仍看 0/10 → 检查 console log: `TeamDataMirror Sync FAILED for zone=...` 看具体错(可能 production schema 没 deploy)

### Member 看不到 Owner 分配的工地
- Member 端把 App 杀掉重开 → `.task` 触发 fetchAndSyncAll
- 看 console:`Synced N records ... from zone=xxx` — N 应该 ≥ 1
- 如果 0 → Owner 端 mirrorSitePreset 失败(Owner console 看 `Mirror preset FAILED`)

### Server change token mismatch
- 切换团队 / Owner 重置 zone 后,Member 端的 token 可能过期 → fetchAndSyncAll 报错
- 临时 fix:Member 端「设置 → 数据 → 清空所有内容」(我们之前加的危险按钮),重新接邀请

### iCloud 配额问题
- Apple 个人 iCloud 免费 5GB,团队共享同 zone 的数据走 owner 的配额。大量录音 / PDF mirror 上去可能爆配额。当前 mirror **不** 包括 photo / audio 二进制(只 mirror metadata),所以配额压力小

---

## 总结

✅ **代码已实现**:四阶段全部完成,build 通过
🚧 **真机待验**:你两台手机重新装 build 测一遍完整流程
📋 **Production 上线**:CloudKit Dashboard 推 Schema to Production 是必须步骤

未 commit。先真机测一遍,跑通了再 commit。
