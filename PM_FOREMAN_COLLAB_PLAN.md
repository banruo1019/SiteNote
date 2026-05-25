# PM ↔ Foreman 协作方案(SiteNote v1.x → v2.0)

## 1. 出发点

SiteNote 当前主要服务**单兵工程师**:录音 → 巡检 session → 报告 → 邮件。团队功能(`TeamCloudKitService` + `TeamDataMirrorService`)只是把"巡检报告"这套数据共享给 Owner — 这是 Engineer 内部对 Inspector 角色的协作,不是真实工地的 PM / Foreman 协作语义。

真实工地协作的核心场景:
- **PM**(项目经理 / 工头):在办公室或现场,负责分配任务、审批、出 Daily Site Report
- **Foreman**(工长 / 现场负责人):每天到现场,执行巡检、签字、拍照
- **Subbie**(分包工):只负责自己的工序,不看全局
- **Client / Inspector**(审计 / 巡检员):**只读**,看 daily report 决定通过

**当前 InspectionReport 模型不直接适配** — 它是 Engineer-centric 的"巡检报告",而 PM 真正需要的是"今日工作摘要 + 进度 + 问题清单"。强行复用会扭曲 model。

## 2. MVP 范围

### 2.1 必须做(MVP)

**数据模型 — 新增 4 张表**(独立于 InspectionReport):

| Table | 字段(关键) | CloudKit 同步策略 |
|---|---|---|
| `Project` | id / name / address / projectNo / client / startDate / endDate / status | share zone(team-owned)|
| `Task` | id / projectID / title / description / assignedToUserID / dueDate / status / priority | share zone |
| `TaskUpdate` | id / taskID / updaterUserID / content / photoCount / noteSnapshotsJSON / createdAt | share zone |
| `DailyReport` | id / projectID / date / pmSummary / openIssuesJSON / completedTaskIDs / createdByUserID | share zone |

**最小流程**:
1. PM 创建 Project,绑定到 Team
2. PM 在 Project 内创建 Task,assign 给 Foreman(`assignedToUserID = Foreman 的 userID`)
3. Foreman 在「今日任务」Tab 看到分配给自己的 Task
4. Foreman 在 Task 详情下"+ 现场记录"按钮 → 复用现有 RecordView 录音 / 拍照流程 → 自动写入 `TaskUpdate`
5. PM 在「项目时间线」看到所有 Foreman 提交的 TaskUpdate(按时间排,按 Foreman 分组)
6. PM 在「Daily Report」Tab 点"今日汇总" → 自动从 today 的 TaskUpdate 聚合 → 生成 DailyReport(可编辑摘要) → 一键导出 PDF

### 2.2 不做(明确划出 v2.0 范围外)

- **审批 / 多级签字**:Builder Form / 工序签字这种工业级流程,留到 v2.5
- **Subbie 提交申报 → PM 审批**:Phase 2
- **Client 实时浏览**:Phase 3,涉及 web 端
- **Gantt / 工序依赖**:Phase 3
- **预算 / 工时**:不做,SiteNote 不是 PM 工具
- **多 Project 并行**:v2.0 支持但不优化,UI 默认显示当前 Project

## 3. 角色矩阵

### 3.1 ProfileKind(UI 模式 — 控制看什么 tab)

| ProfileKind | UI tabs | 备注 |
|---|---|---|
| `pm` | 项目 / 任务 / 团队 / 日报 / 设置 | 看全局 |
| `engineer`(legacy)| 记 / 报告 / 日程 / 设置 | 现有 SiteNote 行为,不动 |
| `foreman`(**新增**)| 今日任务 / 记 / 项目 / 设置 | 只看分配给自己 + 主动选择参与的 |
| `subbie`(**新增**)| 今日任务 / 设置 | 极简,只看分配 |
| `viewer`(**新增**)| 项目 / 日报 / 设置 | 只读 |

ProfileKind 已存在(`pm` + `engineer`),需扩展。**ProfileKind 只影响 UI 入口可见性,不决定数据权限**。

### 3.2 TeamRole(数据权限)

| TeamRole | 创建 Project | 创建/分配 Task | 提交 TaskUpdate | 生成 DailyReport | 看团队全部 |
|---|---|---|---|---|---|
| `owner` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `pm`(**新增**)| ✓ | ✓ | ✓ | ✓ | ✓ |
| `lead`(已有,Foreman 同义) | — | ✓(下属 Task) | ✓ | ✓ | ✓(自己团队) |
| `engineer`(已有)| — | — | ✓(自己被分配的) | — | ✓ |
| `subbie`(**新增**)| — | — | ✓(自己被分配的) | — | × 只看自己 |
| `viewer`(**新增**)| — | — | — | — | ✓ 只读 |

权限检查:每个 mutation API 入口检查 `TeamMember(currentUserID, team).role` 是否在允许集合内。

**规则**:`ProfileKind` 控 UI,`TeamRole` 控数据权限,**不混用**:
- 一个 ProfileKind=pm 的人在某个 team 里可能是 viewer(他是 PM 但被邀请进朋友公司是 viewer)→ 进 team 后只看不能改
- ProfileKind=foreman 在自己 team 里可能是 owner(他建的团队他是老板)

## 4. 数据流(单一事实源决策)

延续 v1.x [`CLOUD_DATA_FLOW.md`](./CLOUD_DATA_FLOW.md) 的双链路并存策略:

- **SwiftData CloudKit `.private(containerID)` auto-sync**:Project / Task / TaskUpdate / DailyReport 都加入,**支持 Owner 同账号多设备**
- **CKShare zone mirror**:跨账号 Owner ↔ Foreman / Subbie / Viewer,所有 mutation 双写

每个新 @Model 加 `func mirrorXxx(in modelContext:)` 到 `TeamDataMirrorService`,延续 `mirrorReport / mirrorSchedule / mirrorSitePreset` 的模式。

特殊:DailyReport 的"今日汇总"摘要字段(JSON snapshot)同 `noteSnapshotsJSON` 思路,把 Foreman 提交的文字 / 照片元数据固化进 record,跨账号可见。

## 5. UI 改动清单

### 5.1 复用
- `MainTabView` 根据 `ProfileKind` 切 tab 组合(已有)
- `RecordView`(录音/拍照)、`StagedPhoto`、`NoteDetailView`、`FloorPlan` — 不动
- `TeamManagementView`(团队邀请 / 解散 / 撤销)— 加 role picker for Owner

### 5.2 新增
- `ProjectListView` / `ProjectDetailView`(PM tab)
- `TaskListView` / `TaskDetailView` / `TaskEditorSheet`
- `TodayTasksView`(Foreman / Subbie tab,显示 dueDate == today + assignedToUserID == me)
- `TaskTimelineView`(PM 看 TaskUpdate 流)
- `DailyReportView`(PM 看日报,可手动编辑摘要)
- `DailyReportPDFBuilder`(类似 `InspectionReportPDFBuilder` 套新 layout)

### 5.3 删除 / 收敛
- Engineer 模式下的"巡检 session"流程**保留**(单兵 inspector 仍需要)
- 但 PM 模式不显示"巡检报告"tab,改为"日报"

## 6. 实现路线图(v2.0)

| Phase | 任务 | 估时 | 风险 |
|---|---|---|---|
| 2.0-α | Project / Task / TaskUpdate / DailyReport 4 个 @Model + Schema 加版本 | 1 周 | 中(SwiftData migration) |
| 2.0-β | UI:ProjectList / Task / TodayTasks 三个最小可用 view | 1 周 | 低 |
| 2.0-γ | TeamDataMirrorService 扩展 4 类 mirror + Cleanup 老逻辑 | 4 天 | 中(改 mirror service 易出 bug) |
| 2.0-δ | 权限检查器 `TeamPermissions` 单元测试覆盖 | 2 天 | 低 |
| 2.0-ε | PM 日报 view + PDF builder | 4 天 | 低 |
| 2.0-ζ | 5 角色 ProfileKind / TeamRole 配 onboarding | 2 天 | 低 |
| 2.0-η | 真机 CloudKit 跨账号测试 | 3 天 | 高(CloudKit 时序 bug 调) |

**关键风险**:
1. SwiftData 加 4 张表的 lightweight migration 在 iOS 17/18 偶发 SwiftDataError 1。**对策**:加 SiteNoteSchemaV3,但不写 MigrationPlan(走 inference),fallback DatabaseRecoveryView
2. CKShare 权限模型在 iOS 跨账号场景有时序问题(参考 v1.x 拉到 0 条 bug)。**对策**:`TeamDataMirrorService.resolveZoneID` 已经处理 owner identity 不匹配的 fallback

## 7. 决策开放点(待用户拍板)

1. **PM 是否需要"审批 / 退回"Foreman 提交**?如果需要,DailyReport 需加 approved/rejected status + comment 字段
2. **Subbie 看自己被分配 Task 的同时是否能看到同 Project 其他 Subbie 的 Task**?现方案是不能(只看自己),但工地实际可能要看"邻组在做什么"避免重复
3. **Daily Report 是按 Project 还是按 Date 还是按 Team**?方案是 Project+Date,但可能某些公司喜欢"全员 daily standup"按日期跨 Project 聚合

这些待 v2.0-α 开发开始前对齐。

## 8. 不做的(明确)

- **不做项目模板** — 工地千变万化,模板必假
- **不做 Gantt** — 这是 PM 软件做的
- **不做时间打卡** — 隐私 + 法律风险高
- **不做即时聊天 / 评论流** — SiteNote 不是 IM
- **不做账号体系** — 走 iCloud,简单可靠

## 验证

- 本文档为 v2.0 设计基线,不立即落代码
- v1.x 期间已落地的 P1 修复(token reset / nukeAllData / mirror snapshots / remove member)是 v2.0 的基础设施,已 build pass
