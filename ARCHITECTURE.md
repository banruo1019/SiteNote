# SiteNote 架构速读手册

> 这份给"未来的你"。等几个月后回来看代码不知道从哪开始，就翻这一页。
> 写法：把代码忘掉，**当成一家小公司**。每个文件夹是一个部门，每个文件是部门里的一个员工。
>
> 最后更新：2026-04-25 / 适用 review-fix 整改后的版本（含 P2 竞态修复 + AI 失败可见 + 备份增强）

---

## 0. 一分钟速览

```
SiteNote/                    （项目根，Xcode 工程在这里）
├─ SiteNoteApp.swift         开机键
├─ ContentView.swift         开机后第一眼
├─ Models/                   文件柜：每条数据长什么样
├─ Services/                 工具间：具体活儿谁干
├─ ViewModels/               翻译官：把界面要的整理好
├─ Views/                    门面：用户看得到的所有屏幕
│  └─ Components/            通用零件：可复用按钮 / banner / 图钉
├─ Utils/                    杂物间：设置 / 日期解析 / 密钥保管
└─ Assets.xcassets/          图片 / 颜色 / App 图标
SiteNoteTests/               单元测试（暂未接入 Xcode test target）
```

**3 句话理解整套**：
1. 用户点屏幕 → SwiftUI 把动作传给 ViewModel/Service
2. Service 干完活 → 改 Models 里的数据
3. Models 一变 → SwiftUI 自动重画屏幕（**没有"刷新"这回事**）

---

## 1. 几个核心名词（人话版）

| 名词 | 比喻 |
|---|---|
| **SwiftUI** | Apple 提供的"画屏幕"工具。你写"屏幕长这样"，它负责画 |
| **SwiftData** | Apple 提供的"数据柜"。你说"存一条 Note"，它存到磁盘；你说"给我未删除的 Note"，它给你一沓 |
| **`@State`** | 这个变量"属于这个屏幕"，**变了自动重画** |
| **`@Bindable var note`** | 这个变量是 SwiftData 文件柜里的一条数据，**改它=改文件柜+自动重画** |
| **`@Query var notes`** | 自动从文件柜读一筐数据回来，文件柜变了它也自动更新 |
| **`@Observable`** | 一个共享的小本本，**多个屏幕都能读和监听** |
| **`@AppStorage("key")`** | 这个变量绑定到 UserDefaults 里某个 key，改了自动写盘 |
| **`@Environment(\.modelContext)`** | 拿到当前的 SwiftData 文件柜句柄，用来手动 fetch / delete |

---

## 2. 一条速记从录到存，完整链路

```
[手指按住🎤]
   │
   ▼
RecordView.swift              ← 屏幕（按钮所在）
   │ 通知
   ▼
HomeViewModel.swift           ← 翻译官（协调录音/保存/UI状态）
   │ 调用
   ▼
VoiceCaptureService.swift     ← 麦克风工人（开录、转写）
   │
[说话]
   │
[松手]
   │
   ▼
HomeViewModel 收到松手
   │ 调用
   ▼
VoiceCaptureService           ← 停录、生成 .m4a 文件、返回最终文字
   │
   ▼
HomeViewModel.commit(...)     ← 真正"保存"在这里：
   │
   ├─→ Models/Note.swift            生成新 Note 对象
   ├─→ SwiftData                    存进文件柜
   ├─→ NotificationService          排到期推送（异步走授权门 + 防竞态 token）
   └─→ 后台异步 Task 跑 AI 链：
        1. AIService.polishTranscription   修标点
        2. AIService.runText               识别工地/分类/隐患
        3. AIService.extractLogEntries     抽人员/机械/事件结构化
              │ 抽到了
              ▼
        LogEntryIngestor                   仅写 LogEntry（**不再静默改 isDiaryRecord/cancel 推送**）
                                          + 通知 DiaryConversionTracker 入队
                                            → RecordView 顶部出 banner（不自动消失）
                                            → 用户点「标为施工日志」才翻 isDiaryRecord
                                              + 把 deadline 改 .archive + cancel 推送
        AI 链失败 → AIFailureTracker 记一笔 → AIStatusBar 红字（10 分钟内）
```

**用户感知**：松手 → UndoToast 弹出 → AI 后台跑 → 抽到日志条目时顶部 banner 提示，**等用户确认才转**。AI 失败时顶部 AIStatusBar 变红。

---

## 3. 屏幕地图（用户视角）

### 底部 3 tab（`MainTabView` 管）

| Tab | View 文件 | 主要职责 |
|---|---|---|
| 🎤 **记** | `RecordView.swift` | 大麦克风按钮 + 拍照 + UndoToast |
| 📋 **日志** | `LogTabView.swift` | 双 mode：纵览（跨日列表）/ 台账（单日明细）|
| 📊 **报告** | `ReportsView.swift` | 月度看板 + PDF 出口 + AI 洞察 + 刻意不做列表 |

### 「日志」tab 内部

```
顶部公共：AIStatusBar / 标题 / 搜索框 / 工地+分类 chips
       │
       ├── Mode segment [纵览 | 台账]
       │
       ├── 纵览 mode：4 大段折叠列表
       │     · 要盯 = 隐患 + 逾期
       │     · 今天 = 今日到期
       │     · 待分类 = inbox + 施工日记
       │     · 归档 = 3天/本周/以后/备忘/已完成
       │
       └── 台账 mode：日期导航 + 摘要条 + 4 段 [人员|机械|事件|速记]
             · 行内编辑 LogEntry / 结束机械 session / 生成 PDF
```

### 列表 → 详情：`NavigationStack`

`NavigationLink(value: note)` → 自动推入 `NoteDetailView(note:)` → 详情里改字段直接同步回文件柜。

### 临时弹窗：`.sheet`

详情页"指派" → 弹联系人选择；设置里"+ 新建工地" → 弹 `NewSiteSheet`。

---

## 4. 数据存哪了

| 类型 | 存哪 | 例子 |
|---|---|---|
| **业务对象**（Note / LogEntry / ShareLog）| SwiftData（背后是 SQLite，你不用管）| 每条速记 |
| **零碎设置**（开关 / 引擎 / 提醒时间）| UserDefaults | "AI 总开关 = 开" |
| **小列表**（工地名 / 分类 / 模板 / 条款）| UserDefaults 存 JSON | `["Olympic Park", "Sydney CBD"]` |
| **GPS 中心点** | UserDefaults 存 JSON | "Olympic Park → 33.85N, 151.07E, 样本 10" |
| **录音 .m4a** | App 沙盒 `Documents/audio/` | 实际音频 |
| **照片 .jpg** | App 沙盒 `Documents/photos/` | 实际图片 |
| **OpenAI API Key** | iOS Keychain（加密保险柜）| sk-... 密钥 |

---

## 5. 文件分类速查

### Models/（数据形状）

| 文件 | 干什么 |
|---|---|
| `Note.swift` | 速记：转写文本 + 录音路径 + 照片 + 工地 + 分类 + 到期 + 隐患 + 平面图坐标... |
| `LogEntry.swift` | 日志条：从 Note 抽出的结构化条目（人员到场/机械进出场/事件...）|
| `NoteClassificationSuggestion.swift` | AI 分类建议（暂存在 Note 上，用户点确认后落实）|
| `FloorPlan.swift` | 工地平面图（图片 + 工地 tag + 楼层名）|
| `InspectionTemplate.swift` | 巡检模板（一组 checklist 项）|
| `ShareLog.swift` | 分享/导出统计 |

### Services/（具体干活）

| 文件 | 干什么 |
|---|---|
| `VoiceCaptureService.swift` | 录音 + Apple Speech 转写 |
| `NotificationService.swift` | 排/取消本地推送 |
| `AIService.swift` | 跑 OpenAI 或 Apple Intelligence（polish / 分类 / 抽 LogEntry / 分析照片）|
| `OpenAIClient.swift` | OpenAI HTTP 底层 |
| `LogEntryIngestor.swift` | 把 AIService 抽出的 draft 落库为 LogEntry |
| `NoteClassificationPipeline.swift` | AI 分类的 Phase A（GPS 启发）+ Phase B（AI 综合）流水线 |
| `SemanticSearchService.swift` | 语义搜索（OpenAI embedding 或 Apple NL）|
| `NarrativeService.swift` | AI 生成日记叙事 + EOT claim letter |
| `InsightsService.swift` | 规则扫描，给 6 类异常洞察 |
| `PDFExportService.swift` | 单条/筛选 PDF 巡检日志导出 |
| `SiteDiaryPDFBuilder.swift` | 整日日志 PDF 渲染 |
| `EOTReportService.swift` | 工期延误证据 PDF |

### ViewModels/（状态翻译）

| 文件 | 干什么 |
|---|---|
| `HomeViewModel.swift` | 录音流程总指挥（startRecording / commit / undo / classify / mark hazard / convert to diary）|
| `NoteListViewModel.swift` | 把一筐 Note 按 4 段分组（pending / inbox / archived / done）|

### Views/（屏幕）

主要的：`RecordView` / `LogTabView` / `ReportsView` / `NoteDetailView` / `SettingsView` / `OnboardingView` / `DeadlineSheet` / `PhotoEditorView`...

### Views/Components/（通用零件）

| 文件 | 干什么 |
|---|---|
| `IndustrialTabBar.swift` | 底部 3 tab 自定义 bar |
| `UndoToast.swift` | 录音保存后的 5s 浮窗（标隐患 / 细记 / 撤销）|
| `DiaryConversionBanner.swift` | AI 抽出 LogEntry 后的顶部 banner（**双按钮 · 等用户确认才转**，不自动消失，多条 FIFO 队列）|
| `AIStatusBar.swift` | 顶部 AI 状态条（引擎 + 今日抽出数 + 待确认；**失败时变红显示原因 10 分钟**）|
| `NewSiteSheet.swift` | 新建工地（含地址搜索）|
| `SiteAddressPicker.swift` | Apple Maps 地址联想 + 选定 |
| `FullscreenPhotoView.swift` | 照片全屏预览 + pinch 缩放 |
| `PulsingRecordingRing.swift` / `AudioWaveformView.swift` / `SparkleLoading.swift` | 录音/AI 视觉反馈 |
| `BigButton.swift` / `Chrome.swift` | 设计系统基础件 |

### Utils/（杂物）

| 文件 | 干什么 |
|---|---|
| `DesignTokens.swift` / `IndustrialTheme.swift` | 颜色 / 字号 / spacing 设计 token（`Ink.bg` `Ink.fg` 这些哪来的）|
| `SiteTagsStorage.swift` / `SubTagsStorage` 等 | 各种"小列表"的 UserDefaults 封装 |
| `SiteCentroidsStorage.swift` | 工地 GPS 中心点学习 |
| `SiteSuggestionService.swift` | 根据当前 GPS 推荐工地 |
| `KeychainStorage.swift` | OpenAI Key 安全存储 |
| `ChineseDateParser.swift` | 中文/英文语音里的"明天/3 天后"解析成 deadline 档 |
| `DiaryConversionTracker.swift` | "AI 抽到 LogEntry 待用户确认" 跨 tab 信号（队列 FIFO）|
| `AIFailureTracker.swift` | "AI 链最近失败了" 跨 tab 信号（10 分钟新鲜期）|
| `HighlightTracker.swift` | "刚保存的 note 黄高亮 2 秒" 跨 tab 信号 |
| `AppRouter.swift` | "去日志 tab 的台账 mode" 跨 tab 跳转信号 |
| `AppHeaderProvider.swift` | RecordView 顶部"今天 + 天气 + 位置" 数据源 |
| `JargonStorage.swift` / `JargonDictionary.swift` | 用户自定义术语 / 快捷词 + 内置词典 |

---

## 6. 几个特别中间人（看不见但关键）

这些都是 **`@Observable` 单例**，跨屏幕传信号用：

| 单例 | 谁写 | 谁读 |
|---|---|---|
| `AppRouter.shared` | HomeViewModel.convertLastSaveToDiary | MainTabView + LogTabView |
| `DiaryConversionTracker.shared` | LogEntryIngestor.ingest | RecordView 顶部 banner |
| `AIFailureTracker.shared` | HomeViewModel.runAIPipeline / AIService.extractLogEntries 的 catch | AIStatusBar |
| `HighlightTracker.shared` | HomeViewModel.commit | NoteRow 渲染时查 |
| `AppHeaderProvider.shared` | RecordView.task / 自动定时 | RecordView 标题块 |

**模式**：写方调 `.requestX(...)` → 单例改 `pendingX` 属性 → SwiftUI 自动通知所有读这属性的屏幕重画 → 屏幕处理完调 `.clear()` 防重复。

---

## 7. 7 条心法（写在脑子里）

1. **改一条业务数据 = 不用做"保存"动作**：SwiftData 自动写盘
2. **想让屏幕动 = 改 `@State` / `@Bindable` / `@Observable` 字段**：不要手动 refresh
3. **跨屏共享的状态 = `@Observable` 单例**：定义在 Utils/，多屏读
4. **网络 / 磁盘 / AI 的活 = 放 Service 里**：View 只调用，不直接干
5. **公开类型/方法必须有 `///` 文档注释**：方便未来的你看懂
6. **不引第三方依赖**：iOS / SwiftUI / SwiftData / MapKit 自带 = 够用
7. **改完代码 → `xcodebuild build` 验证 → ⌘R 装真机测**：模拟器对录音/位置/Apple Intelligence 不准

---

## 8. 阅读新代码时问 3 个问题

1. 这个功能**改的是哪条数据**？→ `Models/` 找
2. **谁在屏幕上展示这数据**？→ `Views/` 找
3. **谁负责把数据从外部世界拿进来**？→ `Services/` 找

3 个问题答完，整张图就清楚了。

---

## 9. 文档相关

- `PRODUCT.md` — 产品定位、目标用户、不可妥协原则
- `ARCHITECTURE.md` — 本文件
- 项目专属记忆（仅 Claude Code 可见，路径 `~/.claude/projects/-Users-banruo-Developer-SiteNote/memory/`）：
  - `project_sitenote.md` — 产品使命与原则
  - `project_decisions.md` — V1-V4 + Phase 10 等已敲定决策
  - `project_p0_rectification.md` — 2026-04 整改 12 项完成记录
  - `feedback_workflow.md` — 协作规则
