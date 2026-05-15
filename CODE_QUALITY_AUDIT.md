# 代码质量审计报告 (2026-05-16 overnight #20)

**扫描范围**:`SiteNote/**/*.swift`(31872 行,过滤 Tests/)
**目标**:发现 P0(崩溃风险)/ P1(bug 风险)/ P2(代码债)问题

---

## P0 问题(用户能崩) — 0 项 ✅

无 production 代码里的 `fatalError` / `preconditionFailure` / 危险 `try!`。

所有 `try! ModelContainer(...)` 都在 `#Preview` 块里 — Preview crash 不影响生产用户,可接受。

---

## P1 问题(bug 风险) — 1 项

### P1-1: SiteSuggestionService.swift:38 force unwrap
```swift
if best == nil || d < best!.distance {
```
**风险**:逻辑上 `best == nil` 已经 short-circuit,实际不会到 `best!`,但代码 reviewer 看到 `!` 会怀疑。
**修复**:重构成 `if let b = best, d < b.distance` 或 `guard` pattern。
**优先级**:低,功能正常,只是代码 smell。

---

## P2 问题(代码债 / dead code)

### P2-1: 39 处生产 `print()` 输出
分布:
- `HomeViewModel.swift`(7 处)— AI polish / LogEntry extract 日志
- `VoiceCaptureService.swift`(8 处)— STT 错误日志 + 孤儿文件清理日志
- `BrandingStorage.swift`(1)/ `SemanticSearchService.swift`(1)/ `SiteNoteApp.swift`(1)等
- `DeadlineSheet.swift:520`:`print("Committed:", result)` ⚠️ 看起来是临时调试

**风险**:生产 console 噪音 + 性能影响微小 + 字符串拼接的 transcription 可能泄露用户内容到 system log。
**修复建议**:全部包到 `#if DEBUG ... #endif`,或用 `Logger`(os.log,可分级)。
**优先级**:P2(不紧急)

### P2-2: 大文件未拆完
| 文件 | 行数 | 状态 |
|---|---|---|
| SettingsView.swift | 1203 | 子页未拆,主 struct 已 27 行 |
| RecordView.swift | 1063 | 55 处 private,拆 internal 风险大,留 v1.1.1 |
| InspectionReportPDFBuilder.swift | 949 | PDF 逻辑紧密,留 v1.2 |
| NoteDetailView.swift | 799 | ✅ 已达标 |
| HomeViewModel.swift | 797 | 边线 |

(已记 v1.1.1 hotfix,本轮不强求)

### P2-3: TODO/FIXME 检查
扫 `TODO|FIXME|HACK|XXX`: **0 项** ✅

### P2-4: Phase 0 mock TeamMember 多处重复
- `TeamManagementView.swift` mock members
- `SitePresetEditorView.swift` mock members
- `ScheduleEditorSheet.swift` mock members

3 处 hardcode 同样的 mock,Phase 2 接通 @Query 后才删。
**修复**:暂可接受,标记 v1.2 清理。

### P2-5: Magic numbers / hardcoded paths
- `Team.maxMembers = 10`(已 const,OK)
- `ICloudSyncConfig.containerID = "iCloud.com.banruo.SiteNote"` — hardcode,但 container ID 本来就是单一字面值,OK
- 各种 `cornerRadius: 8` / `cornerRadius: 12` 分布不统一(见 UI_CONSISTENCY_AUDIT)

---

## 整体判断

| 等级 | 数量 | 注 |
|---|---|---|
| P0 崩溃风险 | 0 | ✅ |
| P1 bug 风险 | 1 | force unwrap 1 处(SiteSuggestionService) |
| P2 代码债 | 5 类 | print 39 处 / 大文件 / mock 重复 / 等 |
| P3 优化 | — | 字号 / 间距 token 化(见 UI audit) |

**结论**:**代码质量整体很高**,无紧急问题。建议:
1. 把 39 处 print 用 `#if DEBUG` 或 os.log 替换(0.5 天 polish)
2. SiteSuggestionService:38 force unwrap 改 guard(5 分钟)
3. 其他 P2 留 v1.1.1 hotfix 一起做

---

## 修复优先级(给 task #77)

`#77 fix P0 3 个`原计划 — 但 **P0 = 0**。本次 audit 后建议 **#77 改成修 P1 1 + P2 中最简单的 2**:

1. **P1-1**:SiteSuggestionService:38 改 guard let
2. **P2-1a**:DeadlineSheet:520 临时 print → 删除或 #if DEBUG
3. **P2-1b**:其他高频 print(HomeViewModel 7 处)用 `#if DEBUG print(...) #endif` 包裹

预计 30 分钟可完成。
