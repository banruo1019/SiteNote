# SiteNote 团队协作 — 真机测试指南

**日期**:2026-05-17
**版本**:v1.6 团队协作首次端到端
**前置阅读**:`MEMORY.md` → team-collab-plan(总体方案)

---

## 0. 必要准备

### 0.1 两个 iCloud 账号
团队协作要 2 个真人 / 2 个 iCloud 账号才能验:
- **Owner 设备**:你自己的 iPhone(主 iCloud)
- **Member 设备**:第 2 台 iPhone(另一个 iCloud)或者第 2 个 iCloud 账号登第 2 台 / 模拟器

⚠️ 同一个 iCloud 在两台设备上**不算两个人** — CloudKit Sharing 不会发邀请给"自己"。
⚠️ 模拟器登 iCloud 经常拉不到 currentUserRecordName,**强烈建议用 2 台真机**。

### 0.2 都开启 iCloud
两台设备的设置 → 你的名字 → iCloud:
- ✅ 已登录
- ✅ iCloud Drive 开启
- ✅ App 列表里 SiteNote 开关打开

### 0.3 App 内启用 iCloud 同步
两台设备 → SiteNote → 设置 → 数据和关于 → **iCloud 同步** toggle 开启 → **完全杀掉 App(从后台划掉)再重开**(toggle 改动需要重启 App 才生效,设置里会提示)。

### 0.4 设置「我的名字」
两台设备 → 设置 → 我是 → 「我的名字」分别填:
- Owner 设备:你的真名(例 `Sam`)
- Member 设备:同事名(例 `Jamie`)

这名字会出现在报告 Tab 的「by Jamie」副标 + 工程师签字。

---

## 1. Owner 创建团队 + 发邀请(5 min)

**设备 A (Owner)**:
1. 设置 → 团队 → 进 `TeamManagementView`
2. 点「创建团队」→ 输团队名(例 `Demo Engineering`)→ 保存
3. 系统**自动**调 `TeamCloudKitService.createTeamOnCloud` 建 CKShare + custom zone,然后立刻弹 `UICloudSharingController`
4. 在 UICloudSharingController 里:
   - 「与他人共享」→ 选「邮件 / 信息 / 复制链接」其一
   - 收件人填 Member 的 iCloud 邮箱(注意:必须是对方 iCloud 注册邮,**不是普通 Gmail**)
   - 权限:Read/Write(默认),Anyone with link 也行
5. 发送出去

**验证**:
- TeamManagementView 列表里看到团队 + 1 个 member(自己,角色 owner)
- CloudKit Dashboard(developer.apple.com)→ Schema → Private DB → SharedDatabase 应能看到 `cloudkit.Team` 类型 record(可以晚一点查,异步同步)

---

## 2. Member 接受邀请(2 min)

**设备 B (Member)**:
1. 打开邮件 / 信息 → 看到分享链接
2. 点链接 → 系统弹「在 SiteNote 中打开」→ 允许
3. SiteNote 启动后,`SiteNoteApp` 的 `acceptShareInvitation` 监听器会接收 `CKShare.Metadata` → 调 `TeamCloudKitService.shared.acceptShareInvitation(...)` → 本地 SwiftData mirror 出现 Team + TeamMember(B)
4. 设置 → 团队 → 看到团队名 + 2 个成员(Sam 是 owner,Jamie 是自己)

**验证**:
- 两边的 TeamManagementView 应该都能看到 2 个 member
- 如果只有 1 个 → 等 30 秒重启 App(CloudKit 同步有延迟)
- 仍不行 → 看「troubleshooting → 邀请未接收」

---

## 3. Owner 分配工地 + 自动建日程(3 min)

**设备 A (Owner)**:
1. 设置 → 工地 → 「+」新建工地(例地址 `123 Sample St, Sydney NSW 2000`)
2. 在编辑 sheet 滚到底部「团队分配」段
3. 选 member → 点 `Jamie` → 看到「已分配给 Jamie · 刚刚」
4. **关键**:此时本地会**自动 insert 一条 SiteVisitSchedule**(今天 09:00,siteTag = 这个工地)
5. 保存

**验证设备 A**:
- 工地预设列表回到主页应该显示这个工地 + 分配状态
- 日程 Tab 应该**看不见**这条 schedule(因为 assignedToUserID = Jamie,不是 Sam)

---

## 4. Member 看到新分配(2-30 sec CloudKit 同步)

**设备 B (Member)**:
1. 打开 App / 切到「日程」Tab
2. CloudKit 拉新 schedule(可能需要 5-30 秒)
3. `TeamAssignmentNotifier.scanAndNotify` 触发:
   - 弹本地通知「新工地分配:你被分配到「123 Sample St」」
   - 日程列表里该 row 顶部有橙色 「NEW」 chip
4. 主屏(记 Tab)idle 视图的「今日巡检」section 也应该看到这条工地

**点开后**:NEW badge 消失(`markRead` 写 UserDefaults)

**没出现?**
- 重启 App 触发再次 fetch
- 等 30 秒(CloudKit 同步)
- 看 troubleshooting → 「member 端不接收 schedule」

---

## 5. Member 做巡检 + 报告(5 min)

**设备 B (Member)**:
1. 日程 Tab 点新分配的 schedule → 「▶ 开始巡检」(或主屏的今日 schedule list 点击)
2. session 自动 start,Banner 出现「正在巡检」
3. 录 2-3 条音 / 拍照
4. 点「✓ 完成巡检」→ EndInspectionSheet
5. 检查报告号(SVR-2026-XXX)+ 项目地址(应该 = 工地地址)+ 工程师(应该 = `Jamie`)
6. 勾「发邮件」+ 选收件人 + 「确认完成并发邮件」(或不发,「暂存为草稿」)

**验证设备 B**:
- 报告 Tab 应该看到这条 report,scope = 「我的」可见
- 状态:已发 = 已提交;未发 = 草稿

---

## 6. Owner 看到 Member 的报告(2-30 sec CloudKit 同步)

**设备 A (Owner)**:
1. 切到「报告」Tab
2. 顶部应该出现「我的 / 团队全部」segmented(因为有团队)
3. 默认是「我的」→ 不会显示 Jamie 的报告
4. 切到「团队全部」→ **看到 Jamie 创建的 report**,行的副标末尾有 `by Jamie` 灰字
5. 点进去 → 看到完整内容 + notes + 可以「重新预览 PDF」/「再发一次邮件」

⚠️ 没看到 Jamie 的报告?
- 等 30 秒重新进 Tab
- 重启 App
- CloudKit Dashboard 看 InspectionReport record 是否同步
- 看 troubleshooting → 「报告不同步」

---

## 7. 联动验证

### 7.1 Owner 取消分配
设备 A:工地预设 → Jamie 的工地 → 团队分配段 → 选「未分配」→ 保存

预期:
- `preset.assignedToUserID = nil`
- 已生成的 SiteVisitSchedule **不删**(Jamie 可能已开始,删了会丢失关联)
- Jamie 端日程仍能看到该 schedule(他可以继续做)

### 7.2 草稿同步
- Jamie 暂存草稿 → Sam 端报告 Tab → 「团队全部」应能看到草稿(显示「草稿」蓝 badge)
- Sam 点进去 → 看到 notes + 「继续巡检」按钮(理论上 Sam 也能继续,但 session manager 只有 1 个 active,行为待验)

### 7.3 离线行为
- Jamie 飞行模式 → 仍能开巡检 / 录音 / 写报告(本地 SwiftData)
- 联网后 CloudKit 自动同步 → Sam 端拉到

---

## Troubleshooting

### 邀请未接收
- 检查 Member 设备 SiteNote 是否打开过(必须运行过 SiteNoteApp 至少一次,才能注册 URL handler)
- iCloud 邮箱必须正确(对方 iCloud 注册邮,不是同邮箱别名)
- CloudKit 容器:`iCloud.com.banruo.SiteNote` 在 dashboard 看是否「Production」就绪;还在 Development 的话两台设备都用 dev build 才行(开发模式)

### Member 端不接收 schedule
- 验 Member 设备 SiteNote 设置里 iCloud 同步 toggle 开启(且重启过 App)
- `ICloudSyncConfig.shared.currentUserRecordName` 应该非空 — 可在「设置 → 关于」加个临时调试输出(Phase 后可删)
- CloudKit Dashboard → Private DB → Shared zone 看 SiteVisitSchedule 有没有这条
- SwiftData migration 失败:`SiteVisitSchedule.assignedToUserID` 字段是新加的,如果 Member 设备 App 版本旧没这字段 → 同步会 silent fail。两台都要更新到同一 build

### 报告不同步(Owner 看不到 Member 报告)
- `InspectionReport.createdByUserID` 必须由 Member 端 InspectionSessionManager 自动填(已实现)
- 同上,确认 Member 端 ICloudSyncConfig 拉到了 userID
- CloudKit Dashboard 看 InspectionReport zone

### EngineerReportsView segmented 不显示
- 必须有 Team → 检查 Member 设备 TeamManagementView 是否看到 team(有的话,segmented 才显示)
- `@Query` filter 是 `deletedAt == nil`,如果 team 被软删了不显示

### NEW 通知不弹
- 系统设置 → 通知 → SiteNote → 允许
- `UserNotifications` 权限授权过没(首次 App 启动时弹的"允许通知")
- `TeamAssignmentNotifier.scanAndNotify` 在 RecordView / EngineerScheduleView 的 `.task` 里调,如果 task 没触发(view 没出现过)就不会扫
- 同一条 schedule.id 已经在 UserDefaults `team.assignment.notified.v1` 集合里 → 不再弹(预期行为,只通知一次)

### 同步延迟太长
- CloudKit private/shared DB push 通常 < 30s,但首次共享建 zone 可能 1-2 min
- 测试时两台设备保持 WiFi 联网 + 前台运行 App
- 网络差时可手动「下拉刷新」(目前没实现这个 UI,可手动重启 App 触发)

---

## 已知未实现 / Phase 后续

| 功能 | 状态 | 说明 |
|---|---|---|
| Member 看别人的工地预设 | ⚠️ 不限 | Member 当前可以在工地 Tab 看到全部 SitePreset(CloudKit 同步),想要"只看分配给自己的"需要在 SitePresetEditorView list 加 filter |
| Owner 改了别人的报告 | ⚠️ 不防护 | 现在 Member 的报告 Owner 能改;权限 gating 要加 |
| 离队 / Member 移除 | ⚠️ 部分 | 有 deleteTeamZoneOnCloud,但单个 member 移除流程没真机验 |
| CloudKit push 推送 | ❌ | 现在用本地 polling + scanAndNotify;真 push 需要 CKModifySubscriptionsOperation |
| 多个 Team | ❌ | 当前架构只支持 1 个 Team(`teams.first`),多团队需重设计 |

---

## 验证 checklist(打勾即过)

- [ ] 两台设备都开了 iCloud 同步
- [ ] Owner 创建团队成功(TeamManagementView 看到)
- [ ] Member 接受邀请成功(两边都看到 2 个 member)
- [ ] Owner 分配工地后,本地建了 schedule(Owner 自己看不到,因 assignedToUserID = member)
- [ ] Member 端日程 Tab 看到该 schedule + NEW badge + 弹通知
- [ ] Member 完成巡检 + 出报告
- [ ] Owner 报告 Tab 「团队全部」看到 Member 的报告 + `by Jamie` 副标
- [ ] Member 报告 Tab 「我的」只看到自己的 / 不会看到 Owner 的

全打勾 = 团队协作 MVP 跑通。
