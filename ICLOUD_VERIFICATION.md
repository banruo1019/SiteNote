# ICLOUD_VERIFICATION.md — v1.2 iCloud + Team 真机验证清单

v1.2 大版本(2026-05-16 完成)包含两条 iCloud 功能,**都需要真机实测**才能确认上架前 OK。

| 功能 | 状态 |
|---|---|
| iCloud SwiftData 跨设备同步速记 | ⏸ 待实测 |
| Team CKShare 跨用户共享 | ⏸ 待实测 |
| iCloud Drive Files 报告归档 | ✅ binary 已验证(详见 ICLOUD_FILES_SETUP.md) |

---

## 测试环境要求

| 项 | 说明 |
|---|---|
| **设备 A** | 你的主 iPhone(已登 Apple ID `banruostudio@gmail.com`) |
| **设备 B** | 第二台设备:iPad / 第二台 iPhone / Mac Simulator |
| **CKShare 测试需第三方** | 一个**不同** Apple ID 的设备(找朋友/家人/同事的设备) |
| iCloud Drive 设置 | 两台都开 |
| 网络 | WiFi 优先,初次 sync 一般 < 1 分钟 |

---

## 测试 1:速记跨设备同步(同一 Apple ID)

### 前提
1. 设备 A 装 v1.2 build,**正常启动到首页**(不卡在 DatabaseRecoveryView)
2. 设备 A 进:设置 → 数据 → **iCloud 同步 toggle ON** → App 提示重启 → kill App → 重启
3. 设备 B 同 Apple ID 装 v1.2,同样开 toggle 重启

### 步骤
1. 设备 A 录一条新速记(随便说几个字)
2. 设备 A 等 30 秒,看 CloudKit 系统活动(右上角小齿轮)
3. 设备 B 拉刷新主页(下拉)
4. **预期**:设备 B 看到设备 A 录的那条
5. 反向:设备 B 录一条 → 设备 A 应看到

### 失败排查

| 症状 | 检查 |
|---|---|
| **设备 A 开 toggle 重启就崩**(DatabaseRecoveryView) | Schema migration 失败,看 OS Console "[SiteNote] ModelContainer 创建失败" log。可能是 V1 → V2 migration 没跑通 — 回报错误信息 |
| 设备 B 一直看不到 | 1. 检查两台都登同一 Apple ID。2. CloudKit Dashboard https://icloud.developer.apple.com/dashboard → `iCloud.com.banruo.SiteNote` → Private DB → 看有没有 Note record。3. 设备 B 关网络再开,强制 SwiftData refetch |
| Console 报 "CKError 25" partial failure | 通常是 schema 没 deploy,去 Dashboard "Deploy schema to production" |

---

## 测试 2:Team 创建 + 单设备验证

### 前提
- 设备 A 已开 iCloud 同步,App 正常启动

### 步骤
1. 设备 A:角色切 Engineer → 设置 → 团队 → "创建团队"
2. 输入团队名:测试团队
3. 点"创建"
4. **预期**:
   - 几秒内系统弹出 **UICloudSharingController**(系统原生邀请 UI)
   - 顶部显示"测试团队 - SiteNote"
   - 可以选 Mail / Messages / Copy Link 等分享方式
5. 关掉 sharing controller(右上角 X / Cancel)
6. 团队页应显示:
   - Team header: "测试团队 / 1/10 成员"
   - Members 列表里:1 个 owner(crown 图标)
   - 底部按钮:"邀请成员"、"解散团队"

### 失败排查

| 症状 | 检查 |
|---|---|
| 点"创建"后没动静/转圈不结束 | OS Console 看 `[TeamCloudKit] Zone creation failed` 之类 |
| "无法获取 iCloud 用户身份" alert | iCloud 没登陆 → 系统设置 → Apple ID 登录 |
| `iCloud 未登录或不可用` 错误 | CKAccountStatus 不是 available |
| 创建成功但 share controller 没弹 | sheet binding 出问题 — 回报 |
| CloudKit Dashboard 看不到 zone | container ID 不对 / capability 没勾 |

---

## 测试 3:跨用户邀请 + 接受(最难)

**这一步是 v1.2 核心价值,失败可能性最高**。

### 前提
- 设备 A:Owner 已创建团队(测试 2 通过)
- **找一台不同 Apple ID 的设备 X**(同事的 iPhone)装 v1.2

### Owner 端操作(设备 A)
1. 重做测试 2 流程,系统 sharing controller 弹出
2. 在 sharing controller 里:
   - 选"添加联系人"或直接输入对方 iCloud Email
   - 或者选"Copy Link" → 把链接通过任何方式(Messages / 微信 / Slack)发给对方
3. 提交邀请

### Member 端操作(设备 X)
1. 点击 owner 发来的 share URL(在 Messages / Mail 里)
2. 系统弹出"加入团队"sheet
3. 点"接受"
4. **预期**:
   - SiteNote 自动打开
   - 弹出 alert:**"团队邀请 / 已加入团队"**
   - 设备 X 进 设置 → 团队 → 应该看到"测试团队 / 2/10 成员",列表里包含 Owner + 自己

### 双向 sync 验证
5. **设备 A**:在 团队 → 邀请成员 → 输入第二个 member 姓名+email → 应能再次弹邀请
6. 设备 X 拉刷新团队页 → 应能看到新加的 member 行(等 ~30 秒)

### 失败排查(预期 bug 区域)

| 症状 | 可能原因 | 我能怎么修 |
|---|---|---|
| 设备 X 点链接 SiteNote 不打开 | URL scheme 没配 / `userDidAcceptCloudKitShareWith` 没接到 | 检查 entitlements + `SiteNoteSceneDelegate` 类绑定。把 Console log 给我 |
| App 打开了但没 alert | NotificationCenter publisher 没接 | 检查 RootContainerView .onReceive。给 log |
| Alert 提示"接受邀请失败" | CKAcceptSharesOperation 失败 | 99% 是 schema 没 deploy 到 Production / containerID 不对 / metadata.share 拉不到。把错误描述给我 |
| 接受成功但本地没出现 Team | acceptShareInvitation 拉 records 时 zoneID 不对 | 加 log 看 fetched records 数,给我 |

---

## CloudKit Dashboard 自查(Owner 创建团队后)

1. 打开 https://icloud.developer.apple.com/dashboard
2. 选 `iCloud.com.banruo.SiteNote`
3. **Schema** → "Record Types" 应该看到:
   - `SiteNoteTeam`(字段:teamID / name / ownerUserID / createdAt)
   - `SiteNoteTeamMember`(字段:memberID / teamID / userID / displayName / email / roleRaw / joinedAt)
4. **Data** → Private Database → "All Zones"
   - 默认 `com.apple.coredata.cloudkit.zone`(SwiftData 的 Note 等都在这里)
   - 新出现一个 zone:`<team-uuid>`(测试 2 创建的)
5. 该 zone 里应该看到 1 条 SiteNoteTeam 记录

**如果 Record Types 自动创建失败**(常见 "Schema not in Production" 错):
- 点 Dashboard 顶部 "Deploy Schema Changes to Production"
- 重新建团队

---

## 实测后回报模板

请把以下信息告诉我,我据此修 bug:

```
测试 1(速记同步):
- 设备 A 录速记后,设备 B 看到吗? [是/否]
- 如果否,错误信息 / Console 关键 log:

测试 2(创建团队):
- 系统 share controller 弹出来了吗? [是/否]
- Team 列表能看到自己 Owner row 吗? [是/否]
- Dashboard 上有 SiteNoteTeam record 吗? [是/否]
- 如果否,详细:

测试 3(跨用户接受):
- 设备 X 点 share link,SiteNote 打开了吗? [是/否]
- "已加入团队" alert 出现吗? [是/否]
- 设备 X 看到 Team 列表里有 owner 吗? [是/否]
- 如果否,详细:
```

---

## v1.2 没做完的(留 v1.2.x / v1.3)

- ❌ Member 离开团队时**不**自动从 CKShare participants 移除(只清本地)→ 需要 raw CKShare 操作,留 v1.2.x
- ❌ Owner 移除 member 时**不**自动从 CKShare 移除该 participant → 同上
- ❌ 业务数据(Note / Inspection Report 等)**没有**按 team 共享 — 第一版团队功能只共享团队**身份**,业务报告还是个人的。要 member 看到 owner 的 reports,需要把 Note 等也 mirror 到 team zone,留 v1.3
- ❌ CKShare.publicPermission 现是 .none(必须显式邀请),没做"任何人通过 link 加入"模式

这些都是 known limitation,实测过 v1.2 跑通基本 Team CKShare 后再迭代。
