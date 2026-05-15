# CloudKit + 团队系统:完整落地设计

**起草时间**:2026-05-16
**目标**:让 SiteNote 支持公司多人协作,头分配工地给 member,member 报告自动汇总给头。
**约束**:零后端,只用 Apple CloudKit。

---

## 一、决策回顾(2026-05-16 用户已对齐)

详见 memory:[[team-collab-plan]] + [[task_engineer_roadmap]]

- ✅ 选定方案:CloudKit Sharing(不是 Firebase / 自建后端)
- ✅ 角色:Owner / Lead / Engineer(对应 CKShare 自带 3 档权限)
- ✅ 前置:必须先做 iCloud 备份(任务 1)铺好 CloudKit 基础
- ⏳ 未定 4 件事(用户拍板前不能动 ModelContainer):
  1. iCloud 备份免费 vs 付费?
  2. 团队最大人数?
  3. member 能否看别人报告?
  4. 离开团队后数据归个人还是公司?

---

## 二、同类产品对标(2026-05-16 网调)

| 平台 | 多人协作机制 | 角色模型 | 加入流程 |
|---|---|---|---|
| **Procore** | 公司账号 + Project Directory + User Directory | Admin / Standard / Read-only,可全局或 per-project | Admin 输入邮箱 → email 邀请 → 接受 |
| **Fieldwire** | Account-level + Project-level | Account Owner / Account Manager / Project Admin / Foreman | "People" tab 邀请 → 邮件 |
| **CompanyCam** | Project-based,GPS 时间戳每张照片 + 团队相册 | Owner / Admin / Crew Member | 邀请链接 / 邮件 |
| **SafetyCulture** | Group + User permissions | Owner / Admin / Team Manager / User | 邀请邮件 + accept |

### 共同 pattern
1. **Owner / Admin / Member** 三级角色(我们对齐这个)
2. **邀请走邮件**(我们用 iCloud 邮箱 + CKShare URL)
3. **公司层 + 项目层** 双层组织(我们简化为单层 Team,因为大部分小公司只有一个 team)
4. **可视权限分级**:谁能看谁的报告 / 谁能修改

### SiteNote 差异点(故意简化)
- **不分公司 / 项目两层** — 一个 Team 直接 own 多个工地。小公司不需要双层。
- **不做 read-only role** — Owner / Lead / Engineer 三档够用
- **member 默认只看自己创建的** — 透明度 by default 低,Owner 可显式开权限

---

## 三、CloudKit Sharing 技术架构

### Apple 自带 3 档 CKShare 权限
```
publicPermission       — 拿到 URL 任何人能看(我们用 .none,必须邀请)
participantPermission  — 邀请进来的人
  .readOnly            — 只能看
  .readWrite           — 看 + 改
participantRole        — Apple 自带的 role 概念
  .owner               — 创建者
  .privateUser         — 通常用户
  .publicUser          — 通过 URL 进来的
```

### SiteNote 角色映射
- **Owner**(我们的"头"):CKShare 的 owner,默认 readWrite
- **Lead**(可选):邀请时设 `.readWrite` + 自定义 metadata "role: lead"
- **Engineer**(普通 member):邀请时设 `.readWrite` 但 app 端通过 metadata "role: engineer" 限制看到的 Note

### 关键 API
```swift
// 1. 创建 share
let share = CKShare(rootRecord: teamRecord)
share[CKShare.SystemFieldKey.title] = "ABC Engineering Team"
share.publicPermission = .none

// 2. 邀请 — 通过 UICloudSharingController
let controller = UICloudSharingController(share: share, container: CKContainer.default())
controller.delegate = self  // 处理保存 / 邀请发送

// 3. 接受邀请 — 在 SiteNoteApp.swift 加 SceneDelegate 监听:
func windowScene(_ scene: UIWindowScene, userDidAcceptCloudKitShareWith meta: CKShare.Metadata) {
    let op = CKAcceptSharesOperation(shareMetadatas: [meta])
    // ... 加入 shared database
}
```

### Sample 项目
- [apple/sample-cloudkit-sharing on GitHub](https://github.com/apple/sample-cloudkit-sharing) — Apple 官方 sample,直接抄
- WWDC21 "Build apps that share data through CloudKit and Core Data"

---

## 四、数据模型设计

```swift
@Model
final class Team {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""               // "ABC Engineering"
    var ownerUserID: String = ""        // CKRecord.creatorUserRecordID
    var createdAt: Date = Date()
    var deletedAt: Date?
    @Relationship var members: [TeamMember] = []
}

@Model
final class TeamMember {
    @Attribute(.unique) var id: UUID = UUID()
    var userID: String = ""             // Apple ID (CKUserIdentity recordID)
    var displayName: String = ""
    var email: String = ""
    var roleRaw: String = "engineer"    // .owner / .lead / .engineer
    var joinedAt: Date = Date()
    @Relationship(inverse: \Team.members) var team: Team?

    var role: TeamRole {
        get { TeamRole(rawValue: roleRaw) ?? .engineer }
        set { roleRaw = newValue.rawValue }
    }
}

enum TeamRole: String, Codable, CaseIterable {
    case owner, lead, engineer
}
```

### 现有 @Model 加字段(团队接通时改)
```swift
// SitePreset
var assignedToUserID: String?  // 头分配给哪个 member
var assignedAt: Date?

// InspectionReport
var createdByUserID: String = ""  // CKRecord.creatorUserRecordID 自动

// SiteVisitSchedule
var assignedToUserID: String?
```

⚠️ **重要**:所有 CloudKit 同步的 @Model 字段必须 **optional 或有 default value**(CloudKit 硬性要求)。这是改造现有 8 个 model 的工作量来源。

---

## 五、UI 流程(7 个 screen)

### 1. 设置 → 团队(新)
- 没团队 → "创建团队"按钮(头点)+ "我已加入团队"提示
- 有团队 → 团队名 + 成员数 + "管理成员"

### 2. 创建团队 sheet
- Team 名称输入
- 自动:你成为 owner

### 3. 管理成员
- List(members)→ 邀请 / 移除 / 改角色
- Owner 按钮 "+ 邀请成员" → call UICloudSharingController

### 4. 接受邀请(系统自动)
- 收件人收到 iCloud 邮件 → 点 link → 系统弹"加入 ABC Team?" → 接受 → app 里看到 Team

### 5. 工地分配(已有 SitePreset,加入分配)
- Owner 长按 SitePreset → "分配给…" → 选 member → 推送

### 6. 报告 Tab(已有 EngineerReportsView,加 segmented)
- Owner 看到顶部 segmented:**我的 / 团队全部**
- 后者按 member 分组显示所有人的 InspectionReport

### 7. 日程分配(已有 SiteVisitSchedule,加分配)
- Owner 新建日程时可选 "assign to" → member 收到

---

## 六、分阶段实施 Milestone

### Phase 0(本次 overnight 做)
- [x] 写完整设计 + 对标
- [ ] Team / TeamMember 数据模型(独立文件,**不接通**)
- [ ] Team UI shell(纯 UI,mock data,**不挂入 MainTabView**)
- [ ] CKShare prototype(UICloudSharingController SwiftUI 包装)

**产出**:5 个新文件 + 这份文档。用户回来 review,决定何时接通。

### Phase 1(等用户回来批准)— iCloud 备份
- [ ] 改 8 个 @Model 类:字段全部 optional 或 default
- [ ] 改 SiteNoteApp.swift 的 ModelContainer 配置 → CloudKit private DB
- [ ] 加 iCloud capability + entitlement
- [ ] App Store Connect 配 iCloud container
- [ ] 第一次启动 onboarding "已开启 iCloud 同步"
- **风险**:Migration 一次性,失败 = 用户数据丢。需要 Apple ID 真测 + 真机。
- **时间**:5-7 天

### Phase 2 — 团队基础(Phase 1 完成后)
- [ ] Team / TeamMember 接入 ModelContainer schema
- [ ] Settings → 团队 入口
- [ ] 创建团队 / 邀请成员 UI
- [ ] UICloudSharingController 真接通
- [ ] 接受邀请的 SceneDelegate
- **时间**:3 天

### Phase 3 — 工地 / 日程 / 报告分配
- [ ] SitePreset.assignedToUserID + UI
- [ ] SiteVisitSchedule.assignedToUserID + UI
- [ ] EngineerReportsView 加"团队全部" segmented
- **时间**:3 天

### Phase 4 — 权限 / 推送 / polish
- [ ] member 看不到没分配给自己的工地的报告(权限 gate)
- [ ] 分配成功推送通知给 member
- [ ] 离队 / 移除成员流程
- **时间**:2 天

**Phase 1-4 累计 ~13-15 天**,远超 overnight 可做。

---

## 七、风险登记

| 风险 | 影响 | 缓解 |
|---|---|---|
| Migration v1.1 → v1.2(本地 → CloudKit)失败 | 用户数据丢 | 备份现有 SwiftData store 到 Documents/ 再迁移;失败回滚 |
| 用户没 iCloud 账号 | App 不能启动 | private DB 在没 iCloud 时仍 fallback 到 local,只是不同步 |
| CKShare URL 被泄露 | 第三方拿到 link 进团队 | publicPermission = .none,必须邀请 +接受 |
| 邀请人 iCloud 邮箱不是收件人主邮箱 | 收不到邀请 | 让用户在 app 内显示 share URL + AirDrop 备选 |
| Apple ID 在两设备 = 两 user record | 同人重复算 member | userRecordID 唯一,以 Apple ID 为准 |
| App Review 拒(iCloud 团队功能不解释清楚)| 提交被拒 | App Store Connect 说明:用 iCloud Sharing 实现团队协作,零服务端 |

---

## 八、关键决策(等用户回来拍板)

1. **付费 gating**:
   - 免费版:本地 + 单机 + iCloud 备份(单人)
   - Pro($X/月):团队 + 多人协作
   - 建议:**iCloud 备份免费,团队付费**

2. **团队最大人数**:
   - CKShare 自身限制:**最多 ~100 participants**
   - 小公司平均 3-15 人。无 paywall 限制即可,实际靠 CKShare 兜底

3. **member 可见性默认**:
   - 默认 **member 只看自己的报告 + 分配给自己工地的**
   - Owner 看全部
   - Lead 可选,设置项给 Owner 决定 lead 能看到什么

4. **离队数据**:
   - **个人创建的 report 跟人走**(member 离队后数据保留在他的 iCloud)
   - Owner 不能强制删 member 的 report(法律 / 隐私)
   - 但 SitePreset / Team 等共享数据归 Owner

---

## 九、下一步(我现在做)

### Phase 0 自动跑
- ✅ #61 这份文档
- ⏳ #62 Team / TeamMember model swift 文件(不接通)
- ⏳ #63 Team UI shell(不挂)
- ⏳ #64 CloudKit Sharing prototype(包装 UICloudSharingController)

完成后 commit 一连串,等你回来 review。

### Phase 1+ 等你回来
等你拍板 4 件决策后,我才动 ModelContainer。在此之前**不会改 SiteNoteApp.swift / entitlements / pbxproj**。

---

## 附录:Sources

- [Apple Sample - CloudKit Sharing](https://github.com/apple/sample-cloudkit-sharing)
- [CKShare Documentation](https://developer.apple.com/documentation/cloudkit/ckshare)
- [WWDC21: Build apps that share data through CloudKit and Core Data](https://developer.apple.com/videos/play/wwdc2021/10015/)
- [Procore Invite Users Guide](https://support.procore.com/products/online/user-guide/company-level/directory/tutorials/invite-users-and-collaborators-to-your-companys-procore-account)
- [Fieldwire Team Management](https://help.fieldwire.com/hc/en-us/articles/360003476711-How-to-Invite-or-Remove-a-User-from-Accounts-or-Projects)
- [CompanyCam + Procore Integration](https://help.companycam.com/en/articles/6828457-integrate-companycam-procore)
- [Core Data with CloudKit Sharing - FatBobMan](https://fatbobman.com/en/posts/coredatawithcloudkit-6/)
