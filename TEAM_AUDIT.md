# 团队协作 — 架构 Audit + 整改方案

**日期**:2026-05-17
**触发**:Member 端接受邀请显示「已加入」但「0/10 成员」+ 看不到团队报告 + Owner 端分配工地分配不到 Member

---

## 根因(一句话)

**数据流断裂 — 两套同步机制并行但只通了一半**:
- `SwiftData CloudKit auto-sync` 只 sync 到**用户自己的 Private DB**(单人多设备)
- `TeamCloudKitService raw CKShare` 跨用户但**只搬了 Team / TeamMember 两张表**
- `InspectionReport / SiteVisitSchedule / SitePreset` 根本**没写进 share zone**,跨用户当然看不到

---

## 详细数据流诊断

### 1. Team / TeamMember 同步
| 步骤 | Owner 端 | Member 端 | 问题 |
|---|---|---|---|
| Owner 创建团队 | 写本地 SwiftData + 写云端 raw CKRecord(custom zone)+ 建 CKShare | — | OK |
| Owner 加 member | 写本地 TeamMember + 写云端 raw CKRecord | — | OK |
| 发邀请 | UICloudSharingController 弹出 | — | OK |
| Member 接受 | — | container.accept(metadata) + `recordZoneChanges` 拉 Team + TeamMember → mirror 进 Member 本地 SwiftData | ⚠️ 一次性快照,**不监听后续变更** |
| Member 后续看到新 member | — | **看不到** — Owner 加新 member 后 Member 端不会拉 | ❌ Bug 1 |
| Owner 后续看到 Member 真正加入 | **不知道** — Member 接受了 share 但没回写"我接受"的 record | — | ❌ Bug 2(0/10 现象) |

### 2. InspectionReport 同步
| 谁创建 | 写到哪里 | 谁能看到 |
|---|---|---|
| Member 创建报告 | Member 自己的 Private DB(SwiftData auto-sync) | **只有 Member 自己多设备**,Owner 完全看不到 |
| Owner 创建报告 | Owner 自己的 Private DB | 只有 Owner 自己 |

❌ Bug 3:报告共享**完全没机制**。当初想"SwiftData auto-sync 会自动处理团队",但 auto-sync 只 sync **用户自己的私有 DB**,不跨用户。

### 3. SitePreset 同步
SitePreset 不是 @Model 是 UserDefaults JSON,**根本不会同步任何地方**。Owner 设的工地预设 Member 永远看不到。

❌ Bug 4:工地预设根本没跨用户同步。

### 4. 工地分配 UI
`SitePresetEditSheet` 里 `@Query private var teamMembers: [TeamMember]`:
- Owner 端:本地 SwiftData 有 Team + Owner 自己一条 TeamMember(创建团队时 insert)。**Member 接受邀请后 Owner 端不会自动拿到 Member 的 TeamMember 记录**(Bug 2)
- 结果:Owner 在分配 UI 里看到 0 个其他 member,只有自己 → 没人可分配

❌ Bug 5(也是 Bug 2 的下游)

### 5. SiteVisitSchedule 同步(分配自动建日程)
SitePresetEditor 选完 Member → `modelContext.insert(SiteVisitSchedule(assignedToUserID: target))`。这条 schedule 进**Owner 自己的 Private DB**(auto-sync),Member 的 Private DB 根本拿不到。

❌ Bug 6:分配建的日程根本同步不到 Member 端。

---

## 总结

**当前能跑通的**:Team 创建 + 邀请发送 + Member 接受 + Member 看到团队名 + Member 看到自己 + Owner 看到团队名 + Owner 看到自己。

**全部跑不通的**:其它所有功能(报告共享、工地预设共享、分配、日程同步、Owner 看 Member 加入、Member 看 Owner 加新人)。

---

## 整改方案对比

### 方案 A:补完所有 raw CKShare 代码(在现有架构上)
把 InspectionReport / SiteVisitSchedule / SitePreset 在创建 / 改动时**显式**写进 team share zone 的 CKRecord;Member 端定期 poll 或订阅 zone changes;手动维护本地 SwiftData mirror。

- **工作量**:5-7 天
- **风险**:大量 raw CK 代码 + 自维护 mirror,同步冲突 / 离线 / 删除全要自己 handle。SitePreset 还得改 @Model 或同时维护两套。
- **优点**:不改架构,在现有路上推
- **缺点**:你在重复造 Apple 在 iOS 18 已经给你的轮子

### 方案 B:SwiftData iOS 18+ Native Share(WWDC 2024 推出)
iOS 18 SwiftData 原生支持 CKShare:`ModelContainer` 多 configuration(private + shared),@Model 的实例可以"挂"到 share zone,SwiftData 自动 sync 到 Shared DB;Member 端 SwiftData 自动 pull,view 用 `@Query` 直接看见。

- **工作量**:3-4 天(主要是把 SitePreset 改 @Model + ModelContainer reconfigure + 删一半 TeamCloudKitService raw CK 代码)
- **风险**:iOS 18+ only(老用户掉队;但你才上线没 v1 老用户)
- **优点**:Apple 全包同步 / 冲突 / 离线 / 多设备一致性。代码量 -50%
- **缺点**:SitePreset migration 要小心 + iOS 18+ 限制 + SwiftData 不熟需要 learn

### 方案 C:废掉团队功能 MVP,先 v1.0 单机上架(保守)
团队功能 hide / 砍。专注 Engineer 单机版打磨上 App Store,赚到真用户后再做团队。

- **工作量**:1 天(隐藏 settings team 入口 + 整理代码注释 "Phase 2")
- **优点**:能立刻发版收钱;真用户跑过单机版后 feedback 比脑补准
- **缺点**:之前对齐过"现在做团队",承诺要兑现

---

## 我的建议

**方案 B**,理由:
1. 你 iOS 26.5 模拟器 + iPhone 17,deployment target 设 iOS 18 没问题(你本来就在用新 API)
2. SitePreset 是 UserDefaults JSON,改 @Model 反正早晚要做(将来 ABN/Logo/floor plan 字段越加越多,UserDefaults 不够 robust),顺带做了
3. raw CKShare 代码 5-7 天写完后,你之后任何 Team 数据改动都得维护 mirror 同步逻辑,长期负担大;SwiftData native 自动处理
4. 你刚才"看不到 / 分配不了"全是 raw CK 缺代码 — 补这 5-7 天纯粹是堵窟窿,堵完还得长期维护

---

## 方案 B 执行 Roadmap

如果你选 B,我开始干以下事:

### Phase 1(0.5 天):SitePreset 升级 @Model
- 新 `@Model class SitePreset` 替代 struct
- 数据迁移:启动时一次性把 UserDefaults JSON 倒进 SwiftData(idempotent flag)
- 所有 SitePresetStorage callers 改读 @Query
- xcodebuild verify

### Phase 2(1 天):ModelContainer 双 configuration
- ICloudSyncConfig 改 `cloudKitDatabase: .automatic` 或 multi-config(private + shared)
- SwiftData 自动识别 share zone 的 records
- 删一半 TeamCloudKitService 代码(只留创建 Team zone + 发邀请那部分)

### Phase 3(1 天):InspectionReport / SiteVisitSchedule / SitePreset 关联到 share
- 创建时 `ModelContext.share(model:)` 或者用 `@Relationship` 把 record 挂到 Team
- 由 SwiftData 自动决定写 private 还是 shared

### Phase 4(0.5 天):分配 UI + 报告 Tab 接通
- Owner 在 SitePresetEditor 分配 → 改 preset.assignedToUserID → SwiftData 自动 sync share zone → Member 端 @Query 自动看到
- 报告 Tab segmented 直接看本地 @Query(SwiftData 自动 merged private + shared)

### Phase 5(0.5 天):真机端到端验

---

## 你的选择

| 选项 | 适合 | 代价 |
|---|---|---|
| **A 补 raw CK**(5-7 天) | 不愿改架构 | 短期通 / 长期债 |
| **B SwiftData native**(3-4 天) ⭐ | 长期路线 / iOS 18+ | 投资 SitePreset 升级 |
| **C 砍团队上架** | 急上线 | 撇下已对齐承诺 |

**告诉我选哪个,我就开干**。
