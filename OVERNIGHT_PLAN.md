# SiteNote 今晚自动化迭代计划

**启动时间**: 2026-05-16 深夜
**用户状态**: 已休息,期望早上看结果

---

## 终止条件(全部 ✓ 才停)

- [ ] `xcodebuild` 0 error 0 warning(关键 warning,非 SourceKit/asset 噪音)
- [ ] 所有 > 1000 行的 Swift 文件拆到 < 800 行,共 5 个:
  - [ ] `SettingsView.swift` 1360 → 拆 PM Form 段
  - [ ] `NoteDetailView.swift` 1259 → 拆 sections/actions/AI 三个 extension 文件
  - [ ] `LogTabView.swift` 1256 → 拆 overview/ledger 两个子文件
  - [ ] `RecordView.swift` 1214 → 抽 stats/sections/staged 三个组件
  - [ ] `InspectionFormView.swift` 1098 → 抽 sections 子文件
- [ ] 设计语言 audit 通过(Ink.* token 使用一致,SectionHeader/Footer 统一,字号/间距遵循 DesignTokens)
- [ ] 所有 main view 排版 audit 通过(已 polish:Settings/Engineer 全模块/PM 4 项)
- [ ] 操作手册 `OPERATIONS_MANUAL.md` + 使用说明 `USER_GUIDE.md` 完成
- [ ] release notes 草稿 `RELEASE_NOTES_v1.1.md` 完成

---

## 执行循环(每 30 分钟一次 ScheduleWakeup)

每次唤醒做一件事,做完 commit checkpoint(本地 git),失败回滚:

| 循环 # | 任务 | 风险 |
|---|---|---|
| 1 | 拆 SettingsView PM 段到 `PMSettingsView.swift` | 低 |
| 2 | 拆 NoteDetailView sections 到 `NoteDetailView+Sections.swift` | 中(已有 +AI/+Actions 二拆) |
| 3 | 拆 LogTabView 的 ledger 模式到 `LogLedgerView.swift` | 中 |
| 4 | 拆 LogTabView 的 overview 模式到 `LogOverviewView.swift` | 中 |
| 5 | 拆 RecordView 的 stats/staged 到组件 | 中 |
| 6 | 拆 InspectionFormView sections | 低 |
| 7 | 设计 token audit:扫所有硬编码颜色/字号,替换为 Ink/DesignTokens | 低 |
| 8 | 空态文案统一(audit 所有 empty hint) | 低 |
| 9 | 触控区域 audit(所有 Button 至少 44pt) | 低 |
| 10 | 写 `OPERATIONS_MANUAL.md` | 无 |
| 11 | 写 `USER_GUIDE.md` | 无 |
| 12 | 写 `RELEASE_NOTES_v1.1.md` | 无 |
| 13 | 最终 build + format pass | 低 |

---

## 安全网

- 每次循环开始前:`git status` 检查
- 每次循环结束后:`xcodebuild` build,**失败立即 revert**
- 不会 push 任何东西到 remote
- 不会改 entitlements / pbxproj(除非必要,且会标注)
- 所有改动都用 `git commit -m "[overnight] ..."` 标识,你可以一键 reset

---

## 你早上起来要做的

1. `git log --oneline | head -20` 看我做了什么
2. `git diff main HEAD` 看具体改动
3. 不满意:`git reset --hard <previous-checkpoint>`(每次循环都有 checkpoint)
4. 满意:继续 v1.1 发布流程,看 `OPERATIONS_MANUAL.md`

---

## 已经完成的(2026-05-16 白天 / 晚上前段)

- ✅ Engineer Settings 重写(5 section 极简)
- ✅ Tradie Profile 完全删除(UserProfile.swift / MainTabView / SettingsView / ProfileSelectorView / AIService / LogEntryIngestor / TradieReportPDFBuilder 文件删 + ASCIISlug 抢救)
- ✅ PM RecordView polish:stats filter 不再隐藏 section + 删 valuePropBar 重复信息
- ✅ PM ReportsView polish:月细分条形图修截断 + 删 Tradie PDF 入口
- ✅ PM LogTabView polish:section 命名统一"今天到期"
- ✅ PDF detail page 重排(A3 图纸 + 描述 + 自适应照片)
- ✅ 邮件发送 → 自动归档报告为 .submitted
- ✅ Inspection caption section 改名"图片说明" + 友好 footer
- ✅ Engineer 全面禁 AI(polish/classify/extract/photo-analyze)

build 现在: ** BUILD SUCCEEDED **。
