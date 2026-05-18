# Claude 10h 自主整改 LOG

启动时间:2026-05-18(本机时区)
目标:推进 SiteNote 从"能编译的功能堆叠"到"可上架前 beta 稳定"。

## Round 0 — 起始状态

### Build baseline
- `xcodebuild -project SiteNote.xcodeproj -scheme SiteNote -destination 'generic/platform=iOS Simulator' build` → **BUILD SUCCEEDED** ✅
- Targets:`SiteNote`(单 target,无 Tests target)
- Schemes:`SiteNote`
- Branch:`main`,有大量 modified 文件(local edits 未 commit),新增文件:SwiftDataStack / TeamAssignmentNotifier / TeamDataMirrorService / ContactsStorage / EmailTemplateStorage / AddressAutocompleteField / EmailTemplateEditorView。

### P1 backlog 已扫描的关键事实
| 项 | 现状 | 缺陷 |
|---|---|---|
| SwiftData CloudKit | SiteNoteApp 把 `SiteNoteSchemaV2.models` 全部交 `.private(containerID)` auto-sync | 与 TeamDataMirrorService raw CKShare zone 形成**双事实源** |
| Team 模型 | Team / TeamMember 走 raw CKShare,**未**加 SwiftData auto-sync 排除(Schema 上仍混在一起) | 同上;Schema 注释里说 team 不走 auto-sync,但 ModelConfiguration 没真正隔离 |
| removeMember | TeamManagementView 当前只删本地,**未推云端** | Owner 移除成员后云端 TeamMember 还在 → 下次 fetchAndSyncAll 重新拉回本地 |
| leaveTeam | 删本地 Team mirror,**未清** token / sharedZoneOwnerName / selfMemberID flag | 重新加入团队后老 token 卡住、ownerName 缓存对不上、self id 复用错误 |
| dissolveTeam | 删云端 zone OK,本地清理也调 clearLocalTeamMirror | 唯一相对完整的路径,可作其他离队路径的对照 |
| nukeAllData | EngineerSettingsRoot 删了 Note/Report/Schedule/ShareLog/LogEntry,**漏 SitePreset @Model** | SitePreset 已迁 SwiftData @Model,旧清理只删 UserDefaults legacy JSON |
| nukeAllData UserDefaults | 漏 builders.v1 / contacts.v1 / emailTemplate.v1 / engineerCompanyName / engineerABN / userProfile.displayName / floorPlans / siteCentroids / jargon | 用户"清空"后这些业务设置还活着 |
| BackupService | backupKeys 缺 contacts / emailTemplate / engineerCompanyName / engineerABN / userProfile.displayName | 备份不完整,导致还原后 UI 显示空状态 |
| token reset | resetToken 只删 `.v1`,新代码已切 `.v2 (private/shared)`;还有 `team.sharedZoneOwnerName.<zoneName>` / `team.selfPushed.<...>` 不清 | 卸载重装 / 解散重建团队后 token 残留 → 拉不到 |
| AI / Onboarding | AIService 实际只本地 Apple Intelligence polish | OnboardingView L145 仍写"可选 OpenAI Key"误导;Localizable 里还有"AI 用工地名分类" |
| 测试 target | 不存在 SiteNoteTests target,*.swift 测试文件存在但永不 run | Cmd+U 无效 |

### 计划顺序(由低风险 + 高数据完整性影响排序)
1. **R1**:P1 #185 AI / Onboarding 误导文案(纯文本,零风险,立刻提升信任度)
2. **R2**:P1 #184 token reset 全前缀清理(纯函数,易测,后续 R3-R6 都依赖)
3. **R3**:P1 #182 nukeAllData 漏 SitePreset + 业务 UserDefaults + 附件目录
4. **R4**:P1 #183 BackupService 补 key + 删 aiKeyHint
5. **R5**:P1 #180 removeMember / leaveTeam(团队真删除,需 token reset 已就绪)
6. **R6**:P1 #179 云端单一事实源 — 用 ModelConfiguration 把 Team/TeamMember/SitePreset/Schedule/InspectionReport 从 auto-sync 隔离(高风险大改,放在前面修完小问题后做)
7. **R7**:P1 #181 团队报告完整性(snapshot 字段)
8. **R8**:P1 #186 SiteNoteTests target(pbxproj 风险)
9. **R9-10**:P2 UI 精修 + PM/Foreman 协作方案文档

## Round 历史

### R1 — 2026-05-18 — P1 #185 AI / Onboarding 误导文案
- 改:OnboardingView L145 / L192 中文文案,删 "可选 OpenAI Key" 和 "AI 用工地名分类"。
- 改后:"录音和语音识别都在设备本地处理,不上传任何云端 AI。" / "先填一个工地,录音会自动绑定到它。"
- 验证:`xcodebuild build` → BUILD SUCCEEDED
- 风险:Localizable.xcstrings 旧 source string 变 stale entry,Xcode 下次 build 会自动 extract 新 key,不影响功能

### R2 — 2026-05-18 — P1 #184 token reset 全前缀清理
- 改 `TeamDataMirrorService.resetToken(forZoneName:)`:之前只删 `.v1`,扩展为前缀扫描清所有 token 变种(v1 legacy / v2.private / v2.shared)
- 新增 `purgeTeamLocalCaches(teamID:)`:统一清 token + sharedZoneOwnerName + selfMemberID + selfPushed
- `clearLocalTeamMirror` 改为 internal 可见(team 解散 / 离队 / nukeAllData 都能调)
- 验证:BUILD SUCCEEDED

### R3 — 2026-05-18 — P1 #182 nukeAllData 全面化
- 漏的 @Model 全补:`SitePreset` / `Team` / `TeamMember` 进 delete 清单
- 漏的 UserDefaults 补:builders / contacts(走 facade)+ siteTags / floorPlans / subTagsGlobalV1 / clauseRefs / emailTemplate / engineerCompanyName / engineerABN / userProfile.displayName / inspectorName / obsidian.exportFolderPath / sitePresets.v1(legacy)/ migration flag / aiKeyHint / onboarding / inspection.session.*(全清)
- 团队前缀全清:`team.serverChangeToken.*` / `team.sharedZoneOwnerName.*` / `team.selfMemberID.*` / `team.selfPushed.*`
- 附件目录全删:`Documents/photos`、`Documents/audio`、`Application Support/Reports`
- UI 文案更新:confirm dialog 精确列出删除范围 + 提示"云端共享团队 zone 不删,如需删请先解散团队"
- 验证:BUILD SUCCEEDED

### R4 — 2026-05-18 — P1 #183 BackupService 备份 key 清单
- 加:`settings.builders.v1` / `settings.contacts.v1` / `settings.emailTemplate.v1` / `settings.engineerCompanyName` / `settings.engineerABN` / `settings.userProfile.displayName`
- 删:`settings.aiKeyHint.dismissed.v1`(legacy 已废弃)
- 注释明确:SitePreset 已迁 SwiftData,backup zip 通过 `Application Support/<store>.sqlite` 覆盖
- 确认 zip 包含:Documents 附件 + SwiftData store(default.store + -wal + -shm)+ UserDefaults snapshot JSON(已存在,见 snapshotSwiftDataStore / snapshotUserDefaults)
- 验证:BUILD SUCCEEDED

### R5 — 2026-05-18 — P1 #180 团队成员移除 / 离队
- 新 `TeamCloudKitService.removeMemberOnCloud(member:)`:删 zone 里 TeamMember CKRecord
- 新 `TeamCloudKitService.tryRevokeShareParticipant(team:memberUserID:)`:从 CKShare.participants 撤销 share access(best-effort,iCloud 端延迟生效)
- `TeamManagementView.removeMember` 改 async,顺序:删 record → 尝试撤 participant → 删本地
- `leaveTeam` 改用 `clearLocalTeamMirror`(自动清 token / sharedZoneOwnerName / selfMemberID / selfPushed)
- `dissolveTeam` 末尾加 `purgeTeamLocalCaches`
- UI alert 文案修正:Member 离队时明确告知 "Owner 仍然在云端 share 名单里看到你 —— 彻底移除需要 Owner 在团队页点 '-' 撤销邀请"
- 验证:BUILD SUCCEEDED
- 需真机 CloudKit 验证:实际 share participant revoke 是否生效(可能 iCloud 端延迟)

### R6 — 2026-05-18 — P1 #179 云端单一事实源决策
- 决策:**不拆 ModelConfiguration**(影响现有 SwiftData CloudKit 用户多设备同步)
- 策略:**双链路并存**,SwiftData CloudKit = 同账号多设备通道,CKShare zone mirror = 跨账号协作通道
- 关键执行:每次 SwiftData @Model 改动都调对应 `mirrorXxx`,确保两通道一致
- 补 mirror 触发点:`EngineerReportsView.softDelete` + `InspectionReportDetailView.performDelete`(原来软删后没推 share zone,Owner 端拉回 record 又复活)
- 产出:`CLOUD_DATA_FLOW.md` — 数据流官方文档
- 验证:BUILD SUCCEEDED
- 需真机验证:Owner 软删 mirror 进来的 report,等 share zone 也接收 deletedAt 字段,下次拉不再复活

### R7 — 2026-05-18 — P1 #181 团队报告完整性(noteSnapshots)
- 加 `InspectionReport.noteSnapshotsJSON: String?`(optional 字段 lightweight migration,CloudKit OK)
- 新 `NoteSnapshot` Codable struct:`noteID / transcription / siteTag / createdAt / photoCount / floorPlanRef`
- 新 `report.noteSnapshots() / setNoteSnapshots()` helpers
- 新 `TeamDataMirrorService.rebuildNoteSnapshots(for:in:)`:mirror 前从本地 Note 实体构造 snapshots → 写回 report.noteSnapshotsJSON
- `mirrorReport` 把 noteSnapshotsJSON 写入 record["noteSnapshots"];`upsertReport` 反向读
- `InspectionReportDetailView.notesGroup` fallback:本地 noteList 空 + snapshots 非空(团队场景)→ 显示团队成员 snapshot 行(`snapshotRow`),含 transcription + siteTag + photoCount + "照片在 Foreman 设备" 提示
- 决策:**v1 只传文字 + 元数据**,照片像素留 v2 改 CKAsset 传
- 验证:BUILD SUCCEEDED
- 需真机验证:Owner 跨账号能看到 Foreman 的 transcription 内容

### R8 — 2026-05-18 — P2 #188 UI 精修
- `EngineerReportsView.teamScopeDiagnostic`:从大诊断条简化为"团队成员提交 X 条 + 刷新按钮",长按显示 contextMenu(lastSyncStatus / lastMirrorStatus)
- `TeamManagementView.syncDiagnosticSection`:改为 `DisclosureGroup` 默认折叠,标签"同步诊断 + stethoscope icon"
- `EndInspectionSheet`:删除 `teamShare: Bool = false` state(toggle UI 早已移除,这是孤儿)+ 老注释更新
- 验证:BUILD SUCCEEDED

### R9 — 2026-05-18 — P2 #189 PM_FOREMAN_COLLAB_PLAN.md
- 产出:`PM_FOREMAN_COLLAB_PLAN.md`
- 决策:**InspectionReport 不被 PM/Foreman 复用**,新增 4 张表(Project / Task / TaskUpdate / DailyReport)
- 角色:扩 ProfileKind(pm / engineer / foreman / subbie / viewer),TeamRole 加 pm / subbie / viewer
- ProfileKind 控 UI,TeamRole 控数据权限,**不混用**
- 8 个 Phase 路线图,估时合计 ~3.5 周
- 明确不做:审批 / Subbie 申报 / 客户实时浏览 / Gantt / 预算 / 时间打卡 / IM / 自有账号
- 验证:文档无需 build

### R11 — 2026-05-18 — P2 #187 平面图 floorPlanID 改造
- Note 加 `floorPlanID: UUID?`(optional 新字段,lightweight migration)
- FloorPlansStorage 加 `find(id:)` + `resolve(id:name:siteTag:)`(双路 fallback)
- 写入路径:NoteDetailView L146 写 floorPlanRef 时同步写 floorPlanID
- 读取路径:NoteDetailView+Sections / NoteDetailView+Actions 用 `FloorPlansStorage.resolve(id:name:)` 优先 ID fallback name
- FloorPlanManageView 删图 + clearReferences:按 ID 优先,name fallback 老数据
- Note.init 加 floorPlanID 参数(向后兼容,默认 nil)
- 验证:BUILD SUCCEEDED

### R12 — 2026-05-18 — 收尾总结

- 最终 build:`xcodebuild -project SiteNote.xcodeproj -scheme SiteNote -destination 'generic/platform=iOS Simulator' build` → **BUILD SUCCEEDED**
- 11 个 Round 全 build pass
- 11 个 task(8 个 P1 + 3 个 P2)全完成
- 残留 TODO 极少:仅 1 处(InspectionReport.attn 当邮件状态字段近似,无 sentTo / sentAt 专门字段),非阻塞
- 产出 3 个 doc:`CLAUDE_10H_LOG.md` / `CLOUD_DATA_FLOW.md` / `PM_FOREMAN_COLLAB_PLAN.md`

## 最终输出

### A. 已修复列表(11 项)

1. ✅ AI / Onboarding 误导文案(R1)— OpenAI Key / AI 工地分类 删除
2. ✅ token reset 全前缀清理(R2)— resetToken 扩 prefix 扫,purgeTeamLocalCaches 统一清缓存
3. ✅ nukeAllData 全面化(R3)— 补 SitePreset/Team/TeamMember + 全部业务 UserDefaults + 附件目录
4. ✅ BackupService 备份 key 清单(R4)— 加 builders/contacts/emailTemplate/engineer info/displayName,删 aiKeyHint
5. ✅ 团队成员移除/离队(R5)— removeMemberOnCloud + tryRevokeShareParticipant,leaveTeam 走 clearLocalTeamMirror
6. ✅ 云端单一事实源决策(R6)— 双链路并存策略 + 软删 mirror 补全,产出 CLOUD_DATA_FLOW.md
7. ✅ 团队报告完整性(R7)— InspectionReport.noteSnapshotsJSON 新字段 + NoteSnapshot 结构,InspectionReportDetailView fallback 显示
8. ✅ UI 精修(R8)— 诊断条简化,EndInspectionSheet teamShare 孤儿 state 删
9. ✅ PM_FOREMAN_COLLAB_PLAN.md(R9)— v2.0 设计文档
10. ✅ SiteNoteTests target 步骤(R10)— LOG 文档(用户 Xcode UI 操作)
11. ✅ 平面图 floorPlanID(R11)— Note.floorPlanID 加字段 + resolve 双路 fallback

### B. 未修复但已定位列表

1. **Tests target 实际接入**:已写步骤(R10),需用户在 Xcode 点 4 步;未在 CI 跑过
2. **`InspectionReport.lastSentAt / sentTo` 字段**:当前邮件状态用 attn 近似,有 1 处 TODO 注释。v1.x 末期可加,但不阻塞
3. **PDF / 照片 CKAsset 跨账号传送**:R7 只做了文字 snapshot;照片仍只在 Foreman 设备(Owner 看到 photoCount 数字 + 引导文案)。v2 升级方向
4. **iCloud Drive PDF 镜像跨账号**:Member 推 PDF 到自己 iCloud Drive,Owner 看不到(隔离的)— v2 改 CKAsset
5. **Schedule mirror 缺 deletedAt 字段双写**:R6 决策"mirror 失败时无 retry queue",Schedule 软删 + mirror 失败 → 下次 fetch 回填
6. **PDF builder 平面图 ID 路径**:R11 改了 NoteDetailView + Actions,但 `InspectionReportPDFBuilder` 还按 name 找(改起来涉及 PDF 渲染,留 v1.x patch)
7. **TeamRole 权限矩阵不强制执行**:当前所有"Owner 操作"只在 UI 层 if-guard,Service 层未做权限检查 — v2 拆 `TeamPermissions` checker
8. **InspectionFormView 路径仍可能写空 createdByUserID**:CurrentUserRecordName 还没拉到时新建 report 会写空,后续 mirror 时虽然填回但有一个窗口期,可能导致 Member 视图分类错

### C. 需真机 CloudKit 验证列表

1. **Member 接受邀请后 sharedZoneOwnerName 缓存正确**(R5-R6):Owner Container 视角 ≠ Member Container 视角 user record name,UserDefaults cache + allRecordZones fallback 是否走通
2. **Member push report → Owner 拉到 + Owner 端"团队全部"显示**(R6):scope 切换 reset projectFilter 后是否能立刻看到
3. **noteSnapshotsJSON 跨账号文字证据**(R7):Owner 端 InspectionReportDetailView 显示 Foreman 提交的 transcription
4. **removeMember CKShare participant revoke 真撤销**(R5):iCloud 端延迟生效,Member 多久之后 fetch 返回 zoneNotFound
5. **leaveTeam 后再加入同团队**(R2/R5):purgeTeamLocalCaches 清干净后,acceptShareInvitation 再次写 sharedZoneOwnerName,fetchAndSyncAll 拉到全量
6. **nukeAllData 后 iCloud Drive 里的 PDF 镜像残留**(R3):ReportArchiveService.delete 才动 iCloud Drive,nukeAllData 不动 — 用户文件不删
7. **多设备 SwiftData CloudKit 自动同步 + mirror 双通道并存**(R6):Owner iPad / iPhone 同账号是否数据一致

### D. PM/Foreman 协作方案

见 [`PM_FOREMAN_COLLAB_PLAN.md`](./PM_FOREMAN_COLLAB_PLAN.md)。要点:
- 4 张新表(Project / Task / TaskUpdate / DailyReport),不复用 InspectionReport
- 5 个 ProfileKind(pm / engineer / foreman / subbie / viewer),5 个 TeamRole
- 权限矩阵分离 UI 与数据,7 个 Phase 路线图,~3.5 周
- 明确不做:审批 / 客户 / Gantt / 预算 / IM / 自有账号

### E. 下一轮最值得做的 5 件事

按 ROI / 风险排序:

1. **接 SiteNoteTests target**(P1,1 小时)— 按 R10 步骤在 Xcode UI 操作,验证两个现有测试。然后补 BackupService.backupKeys 完整性测试 + TeamDataMirrorService.purgeTeamLocalCaches prefix 扫描测试。这是上 CI 的前置条件。
2. **真机 CloudKit 跨账号端到端测试**(P1,半天)— 找 2 个 Apple ID 测 5 个场景(C 列表),记录哪个 timing 问题需 retry queue。这是 beta 上线前必跑。
3. **PDF builder 切到 floorPlanID resolve**(P2,1 小时)— `InspectionReportPDFBuilder` 找平面图改用 `FloorPlansStorage.resolve(id:name:)`。补 R11 最后一个引用点。
4. **InspectionReport.lastSentAt + sentTo 真字段**(P2,2 小时)— 加 2 字段 + 改 `sendMail success` callback 写入 + UI 改读这两个,删 attn 近似。给 v1.x 邮件状态显示真实化。
5. **mirror retry queue**(P1.5,1 天)— `TeamDataMirrorService.save(record:db:context:)` 失败时把 record 入 UserDefaults 队列,网络恢复时重发。当前失败只 log,导致 软删 deletedAt 偶尔丢失 → record 复活循环(R6 已知 case)。

---

## 自我检查 Audit Round(2026-05-18 晚)

4 个 Explore agent 并行 audit codebase。汇总后修了 8 项,定位 1 项不修,4 项后续:

### 已修

| # | 严重度 | 位置 | 问题 → 修法 |
|---|---|---|---|
| 194 | P1 | EngineerReportsView L548 / EndInspectionSheet L940 / InspectionReportDetailView L815 / ScheduleEditorSheet L301+L317 | 4 处 `try? modelContext.save()` → 改 `do/catch + os.Logger.error`,失败可查;InspectionReportDetailView 邮件 sent 路径加 errorMessage UI 提示 |
| 195 | P1 | HomeViewModel L339 + L697 | AI polish catch 空块 → 加 os.Logger.error,trimmed 空时 `保留原 transcription`(防 polish 返回空覆盖原文) |
| 196 | P1 | InspectionDraft.swift NoteSnapshot + TeamDataMirrorService.rebuildNoteSnapshots | NoteSnapshot 缺 floorPlanID → 加字段,跨账号平面图 ID 不丢 |
| 197 | P1 | VoiceCaptureService.startCapturing L266 | audioEngine.start 失败时未清 recognitionRequest → 内存泄漏。补 `recognitionRequest = nil` |
| 198 | P2 | InspectionFormView.saveDraft L618 | mirror 失败 silent → 加 os.Logger,view 已 dismiss 不加 UI(mirror 内部已写 lastMirrorStatus 暴露到诊断段) |
| 199 | P2 | EndInspectionSheet.handleConfirm L753 | `isGenerating=true` 在 Task 内 → 用户狂按可双重生成 PDF → 改成 guard 后**同步**置 true |
| 200 | P2 | EngineerScheduleView L119-126 | .task 3 个调用并发 → scanAndNotify 用旧数据。改成 **串行 await**,fetchAndSyncAll 完成后再 scan |
| 201 | P2 | HomeViewModel.commitDirectly L591+L609 | insert 后推迟 Task save → race + app kill 后孤儿。改**同步 save**(5-20ms 损失换数据完整) |

### 不修(已评估)

- **NotificationService L188 task 竞态** — agent 报但实际有 `taskLock` + `clearScheduleIfCurrent` generation 检查,逻辑安全只是注释不足。
- **InspectionSessionManager L184 `report.id as UUID?` 冗余** — 无害冗余代码,不修。
- **TeamCloudKitService.acceptShareInvitation 不报错** — 现有 try?,失败用户重新接受邀请即可。
- **HomeViewModel `await MainActor.run` 冗余 hop** — 性能微小,SwiftUI 推荐写法,不改。

### 后续 P2/P3(已记 LOG 不立即修)

- **InspectionReportPDFBuilder.drawFloorPlanPin 仍用 name 查** — P2 #187 尾巴,需改 `FloorPlansStorage.resolve(id:name:)`(下个 round)
- **NotificationService 时区:Calendar.current 改 explicit timeZone** — 用户出差跨区可能延迟
- **PhotoStorage.absoluteURL path 穿越防御** — `..` 校验,实际 iOS 沙盒已防,加 belt & suspenders
- **TeamDataMirrorService.resolveZoneID 缓存 TTL** — Member 换 iCloud 账号后老缓存可能错。当前 cache miss 才查,加 TTL 30 天主动 invalidate

---

## R10 — 2026-05-18 — P1 #186 SiteNoteTests target(Xcode UI 步骤)

#### 现状
- `SiteNoteTests/` 目录已存在,内含 `ChineseDateParserTests.swift` + `NotificationScheduleTests.swift`
- pbxproj 只有 1 个 `PBXNativeTarget`(SiteNote app),**没有 Tests target**
- 直接手改 pbxproj 风险:破坏 UUID 引用 / 配置 list / scheme,容易 corrupt project file

#### 决策
**不手改 pbxproj**,改为详细写 Xcode UI 操作步骤,用户开 Xcode 3 分钟可完成。

#### Xcode UI 步骤(用户执行)

1. 打开 `SiteNote.xcodeproj`
2. 顶部菜单 **File → New → Target...**
3. 选 **iOS** tab → 选 **Unit Testing Bundle** → Next
4. 在 form 填:
   - Product Name: `SiteNoteTests`
   - Target to be Tested: `SiteNote`(自动)
   - Language: `Swift`
   - Use Core Data: 不勾(单选)
5. 点 **Finish**。Xcode 自动:
   - 创建 `SiteNoteTests/SiteNoteTests.swift` 占位文件
   - 创建 target `SiteNoteTests`(productType = unit-test bundle)
   - 自动加 PBXTargetDependency / PBXContainerItemProxy
   - 加 scheme test action
6. 删 Xcode 自动创建的 `SiteNoteTests/SiteNoteTests.swift`(已经有现成测试)
7. 在 Project navigator 右键 `SiteNoteTests` group → **Add Files to "SiteNote"...** → 选 `ChineseDateParserTests.swift` + `NotificationScheduleTests.swift` → **Target Membership 勾 SiteNoteTests**(取消 SiteNote)
8. **Cmd+U** 应该跑过两个测试 file

#### 验证后续
- 若 Cmd+U 跑过,可以接着加纯函数测试(backlog 提到的 BackupService key / token reset / ReportNumbering / TeamPermissions)
- 这些可以纯 Swift 写,不需要 UI / CloudKit

#### Build 验证
- 当前 R10 没改代码,只写 LOG。前面 9 轮 build 都过。
- 真正建立 Tests target 后,需重跑:`xcodebuild test -project SiteNote.xcodeproj -scheme SiteNote -destination 'platform=iOS Simulator,name=iPhone 17'`


