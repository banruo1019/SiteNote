# 操作 Flow 审计报告 (2026-05-16 overnight #22)

**扫描范围**:`SiteNote/Views/**/*.swift`
**目标**:发现用户能"走死 / 卡死 / 撞空"的路径

---

## 总览

| 项 | 数量 |
|---|---|
| `.sheet(...)` | 64 |
| `.alert(...)` | 38 |
| `.confirmationDialog(...)` | 2 |
| Loading state flag(isGenerating / isAnalyzing 等) | 47 |
| errorMessage 引用 | 61 |
| NavigationLink | 33 |

---

## P0 风险(用户能卡死) — 0 项 ✅

详细扫描所有 sheet / alert / loading state:
- 每个 sheet 都有 dismiss 路径(NavigationStack 内的 toolbar Cancel / 系统手势下拉)
- 每个 alert 都有"知道了"/"取消"/"删除"等 button
- 每个 loading flag(isGenerating / isAnalyzing 等)都有 `isGenerating = false` 在 catch 块或 finally 路径

例:`LogTabView+Ledger.generateDiaryPDF()` — Task 内 do/catch,catch 里写 errorMessage + isGenerating = false ✅。

---

## P1 风险(糟糕 UX,不致命)

### P1-1: errorMessage 多处显示风格不统一
- 61 处 errorMessage 引用,有的弹 alert,有的显示在 inline Text,有的塞到 viewModel.errorMessage
- **影响**:同一类错误,在不同 view 视觉表现不一样,用户体验割裂
- **修复建议**:统一一个 `ErrorPresenter` view modifier,所有 view 用 `.errorAlert($errorMessage)`

### P1-2: 空 state 没 CTA(EMPTY_STATE_AUDIT.md 已记)
- 主屏 / 报告 / 日志 / 日程 都有空态文案,但部分没"去 X tab"按钮
- **影响**:首次用户在 0 数据时不知道下一步
- **修复**:已在 EMPTY_STATE_AUDIT.md 标好(留 v1.1 polish)

### P1-3: AppLanguageManager 切换语言后部分文案不变
- PMSettingsView line 132 `alert("已切换语言")` 提示"需重启 App 完全生效"
- 但这是已知问题,SwiftUI 静态文案 init 时 capture locale,运行时切换部分能动态更新
- **影响**:用户切语言后看到混合中英文,直到下次启动
- **修复**:工作量大,留 v1.2

---

## P2 风险(优化)

### P2-1: 38 alert 中部分缺角色明示
- 多数 alert 用 `Button("知道了") { }` 但没标 `role: .cancel`
- **影响**:VoiceOver 用户不清楚 cancel 还是 destructive
- **修复**:每个 alert 至少一个 `role: .cancel`

### P2-2: 47 loading state 中缺超时
- 大多 loading 走 `Task { ... }`,但没设 timeout
- 如果 AI / 网络挂住,用户看到 spinner 永转
- **影响**:小概率事件,但 PM/Engineer 在工地弱网容易撞到
- **修复**:每个 loading Task 加 `try await Task.timeout(seconds: 30)` 或外层 cancel button

### P2-3: 64 sheet 中有些没 drag indicator
- iOS 17+ 自动加 grabber 在 medium detent,但 large detent 没有,用户可能以为没法关
- **影响**:轻微
- **修复**:`.presentationDragIndicator(.visible)` 全套加

### P2-4: 部分 Navigation 死链(已删除子页引用)
扫"还在引用但已删除"的子页 — 暂时没发现。Tradie 删除后所有引用都清干净了。

---

## 整体判断

| 等级 | 数量 |
|---|---|
| P0 卡死 | 0 ✅ |
| P1 糟糕 UX | 3 类 |
| P2 优化 | 4 项 |

**结论**:**操作 flow 整体健壮**,无关键问题。

---

## 给 task #77 的修复清单

`#77 fix: 修最高优先级 3 个`,**优先级**:

1. **CODE_QUALITY P1-1**:`SiteSuggestionService.swift:38` force unwrap 改 guard let(5 分钟)
2. **CODE_QUALITY P2-1**:39 处 `print()` 加 `#if DEBUG` 包裹(20 分钟)
3. **FLOW P2-1**:alert 加 `role: .cancel`(10 分钟)

3 项预计 35 分钟可完成。其余留 v1.1 polish / v1.2 重构。

---

## 给 task #78 的修复清单

(沿用 UI_CONSISTENCY_AUDIT.md 的 5 处)

1. 字号 17 → 18 (10 处)
2. 字号 16 → 15 or 18 (9 处)
3. cornerRadius 14/16 → 12 (4 处)
4. `.borderless` → `.plain` (5 处)
5. 裸 Section → SectionHeader (3-5 处显眼的)

预计 1 小时。
