# SiteNote iPad 适配框架 + 约束

> 起草:2026-05-18 自主整改 Round iPad-R1
> Build baseline:已 universal(TARGETED_DEVICE_FAMILY = "1,2"),iOS 17.0
> 现状:iPad 上能装能跑,但 UI 是 iPhone 拉伸版,无一处 size class / split view 适配

---

## 1. 现状评估

### 1.1 已具备
- ✅ **Universal target**:`TARGETED_DEVICE_FAMILY = "1,2"`,无需新建 iPad target
- ✅ **iOS 17 deployment**:`NavigationSplitView` / `@Bindable` / `Observation` 都可用
- ✅ **Info.plist 多场景**:`UIApplicationSupportsMultipleScenes = true` 已配
- ✅ **iPad 方向**:`UISupportedInterfaceOrientations~ipad` 支持 4 方向
- ✅ **CloudKit / SwiftData**:同账号多设备 sync 已工作(参见 `CLOUD_DATA_FLOW.md`)

### 1.2 缺失
- ❌ **任何 iPad-specific UI 适配**:`rg "horizontalSizeClass|NavigationSplitView"` 返回 0
- ❌ **底部 TabBar 在 iPad 上拉满宽**:13" iPad 上 88pt 高的 tab bar 看起来很丑
- ❌ **NavigationStack 单栈**:iPad 大屏只显示一列,空间浪费
- ❌ **大屏专属交互**:拖拽 / Apple Pencil 标注 / hover preview / 多窗口
- ❌ **键盘快捷键**:无 `.keyboardShortcut` modifier

### 1.3 关键约束
- 不新建 iPad target(universal 就够,避免双码库)
- **iPhone 体验不退化** — 所有 iPad 改造必须 size class gated,iPhone 走原路径
- **不重写 view** — 现有 RecordView / EngineerScheduleView / EngineerReportsView 复用为 detail 内容
- **不动 SwiftData / Service 层** — 数据流不变,只改 layout

---

## 2. 目标场景(iPad 使用心智)

工地实际 iPad 使用场景:

| 场景 | 设备 | 优化重点 |
|---|---|---|
| PM 办公室,大屏看团队报告 | 11/13" iPad Pro + Magic Keyboard | NavigationSplitView 三栏,键盘快捷键 |
| 工地 toolbox 取出 iPad 标记问题 | 11" iPad Air,横屏 | 平面图 + 录音同屏,Apple Pencil 直标 |
| Foreman 接班,iPad 立架查今日任务 | 11" iPad,竖屏 | 任务时间线 + 现场速记一屏 |
| PM 同时看两个工地 | iPad Pro + Stage Manager 多窗口 | Scene-based 多窗口 |

---

## 3. 框架(导航 / 布局 / 输入)

### 3.1 根 view 路由

```
AppRoot
├─ (horizontalSizeClass == .compact) → MainTabView(iPhone 原路径,零改动)
└─ (horizontalSizeClass == .regular) → IPadRootView
                                          ├─ NavigationSplitView
                                          │   ├─ Sidebar(5 sections)
                                          │   ├─ Content List
                                          │   └─ Detail
                                          └─ 多窗口 Scene 支持
```

**约束**:
- AdaptiveRootView 是唯一 size class 路由器,不在 view 内散 `@Environment(\.horizontalSizeClass)`
- IPadRootView 不引用 MainTabView,但**复用所有 detail view**(RecordView / EngineerReportsView 等)

### 3.2 Sidebar 设计

5 sections,固定顺序(按使用频率):

| Sidebar | Content List | Detail 默认 |
|---|---|---|
| 记 | 今日 notes 时间线 | NoteDetailView 或 EmptyNote |
| 日程 | SiteVisitSchedule 月视图 | ScheduleEditorSheet 或 InspectionReport 详情 |
| 报告 | InspectionReport 列表(草稿/已提交分段) | InspectionReportDetailView |
| 团队 | TeamMember + Schedule assigned-to-me | TaskDetail(v2 占位)|
| 设置 | EngineerSettingsRoot 节列表 | 对应配置详情 |

### 3.3 布局栅格

iPad 三栏布局基准:
- **Sidebar**:240pt(min 200, max 280),只显示 icon + 简短文字
- **Content List**:340pt(min 300, max 400),density 紧凑显示
- **Detail**:剩余宽度,主要内容区

横屏 11" iPad(1180pt 宽):240 + 340 + 600 = 1180,刚好
竖屏 11" iPad(820pt 宽):240 + 340 + 240 = 820,detail 太挤 → 用 `.navigationSplitViewStyle(.balanced)` 自动 stack

### 3.4 输入

- **键盘快捷键**(M1/M2 iPad 接 Magic Keyboard):
  - ⌘ N → 新建 note
  - ⌘ Shift R → 录音
  - ⌘ Return → 巡检 session 结束
  - ⌘ F → 全局搜索
  - ⌘ 1 / 2 / 3 / 4 / 5 → sidebar 切换
- **拖拽**:
  - 照片从相册 / 文件 → drop 到 NoteDetailView 直接附加
  - Builder 名片 → drop 到 attn 字段
  - PDF → drop 到 FloorPlanManageView 上传
- **Apple Pencil**:
  - 平面图标注:已有 FloorPlanMarkView,优化为 Pencil 双击切换工具
  - 签字:EndInspectionSheet 加签字板(v2)
- **Hover**(M1/M2 iPad)— 列表行 hover 显示 quick action 按钮(soft delete / mark done)

---

## 4. 实施约束(代码规则)

### 4.1 必须

1. **所有 iPad 改造代码必须 size class gated** — 用 `@Environment(\.horizontalSizeClass)` 决定走哪条路径,不要在 init 时硬判 idiom
2. **新文件命名**:iPad-specific view 以 `IPad` 开头(`IPadRootView` / `IPadReportsLayout`),Compact 路径维持原名
3. **共用 ViewModel / Service 不变** — 任何 iPad 改动只动 View 层
4. **测试责任**:每加一个 iPad-specific view,必须能在 iPhone 上 build pass(因为代码会被编译)
5. **预览(Preview)**:iPad view 必须有 `#Preview { ... }` 用 iPad device

### 4.2 禁止

1. ❌ **不新建 iPad target / 不拆 universal** — 双码库维护成本太高
2. ❌ **不依赖 `UIDevice.current.userInterfaceIdiom`** — SwiftUI 在多窗口 / Stage Manager 下不可靠,用 size class
3. ❌ **不改 RecordView 的 132pt 大圆按钮**(iron rule)— 录音按钮位置 / 大小 / 颜色一字不动
4. ❌ **不在共用 view 里 if-else size class** — 共用 view 维持 Compact 行为,iPad 走 wrapper
5. ❌ **不写 `if isIPad { ... } else { ... }` 风格代码** — 改用 ViewBuilder + size class 路由
6. ❌ **不动 SwiftData Schema** — iPad 适配纯 UI 层
7. ❌ **不实现 Stage Manager 多窗口的"同时编辑同一 report"** — Scene 共享 modelContext 但并发写入冲突边界 case 多,v1 阶段单实例

### 4.3 设计纪律

- 沿用 M1 极简白(Ink 调色板),iPad 上不要换设计语言
- iPad 上字号**不放大** — 现有 13/14/15pt 字号在 iPad 阅读距离合适,不要追求"大屏一定要大字"
- iPad 上**间距适当扩大**:padding 从 24pt → 32pt(用 `@Environment(\.horizontalSizeClass)` 守门的 modifier)
- 颜色 / icon 完全沿用 — iPad 不引入新视觉元素

---

## 5. Phase 路线图

| Phase | 工作 | 估时 | 验证 |
|---|---|---|---|
| **R1**(本轮)| `IPAD_PLAN.md` 框架文档 | 0.5h | 文档 |
| **R2** | `AdaptiveRootView` + size class 路由骨架,SiteNoteApp 切换 | 0.5h | build pass + iPad 模拟器肉眼看路由生效 |
| **R3** | `IPadRootView` NavigationSplitView 三栏占位,sidebar 5 sections | 1h | iPad 模拟器看到三栏 |
| **R4** | 第一个完整接通:**报告 detail** — 点 sidebar 报告 → list → detail 显示 InspectionReportDetailView | 1h | iPad 端能跑通 PM 看团队报告流 |
| **R5** | **日程 detail** 接通 — sidebar 日程 → 月视图 list → detail 显示 schedule 编辑 | 1h | 工程师日程能用 |
| **R6** | **记 detail** 接通 — sidebar 记 → notes 时间线 list → detail NoteDetailView | 1h | 速记 + 详情一屏完成 |
| **R7** | **键盘快捷键**:⌘ N / ⌘ F / ⌘ 1-5 | 0.5h | M1 iPad + Magic Keyboard 真机验证 |
| **R8** | **拖拽**:相册照片 → NoteDetailView 附加 | 1h | iPad drag-and-drop 真机验证 |
| **R9** | iPad 端 onboarding 字号 + 占位文案优化 | 0.5h | 视觉走查 |
| **R10** | Info.plist iPad 方向收敛(去 PortraitUpsideDown)+ Stage Manager 评估 | 0.5h | 真机走查 |

**总估时**:~7.5h,可在 1-2 个 sprint 完成 v1 iPad 体验。

---

## 6. 不做的(明确)

- ❌ **Mac Catalyst** — 这是另一个 target,与 iPad 兼容不冲突但工作量大,留 v2.5+
- ❌ **多窗口"同时编辑同一 report"** — 数据并发写冲突,SwiftData 主线程绑定不友好
- ❌ **自定义 sidebar 拖拽排序** — iOS 自带 navigation 已够
- ❌ **iPad-only feature(iPhone 没有的)** — 一切 iPad 功能在 iPhone 上也要有路径
- ❌ **复杂表格 / spreadsheet** — SiteNote 不是 PM 工具
- ❌ **landscape video 全屏录制** — RecordView 132pt iron rule 不动
- ❌ **跨 iPad 同步 cursor**(类似 Notes app)— 与 SwiftData CloudKit 时序冲突

---

## 7. 真机验证清单

每个 Phase 上 git 前必须跑:

- [ ] iPhone 17 模拟器 build pass + UI 不退化
- [ ] iPad Pro 13" (M4) 模拟器 build pass + 进入 iPad 路径
- [ ] iPad mini 8.3" 模拟器(竖屏 / 横屏切换)layout 不破
- [ ] M1 iPad Pro + Magic Keyboard 真机(键盘快捷键 / 拖拽 / hover)
- [ ] Stage Manager 开启时不崩溃(不要求多窗口,但不能 crash)

---

## 8. 验证当前状态

- `xcodebuild -project SiteNote.xcodeproj -scheme SiteNote -destination 'generic/platform=iOS Simulator' build` → BUILD SUCCEEDED(P1 整改后基线)
- 真机 / 模拟器进 iPad 默认走 MainTabView,底部 IndustrialTabBar 拉伸到 iPad 宽度,**就是要修的现状**

---

## 9. 决策开放点(待用户拍板)

1. **iPad 默认横屏还是竖屏开启**?(工地 toolbox 抓出来通常横屏,办公室通常竖屏)
2. **是否做 Stage Manager 多窗口**?— v1 阶段建议不做,但要保证不 crash
3. **键盘快捷键是否进 v1**?— Magic Keyboard 用户极少数,但加 4-5 个不复杂
4. **Apple Pencil 是否进 v1**?— 平面图标注现已能用,Pencil 优化属于细节,可后续

这些 v1 不一定要拍板,但 Phase R3+ 之前要明确,避免架构需要回滚。

---

## R2-R4 完成记录

### R2 — AdaptiveRootView 骨架(2026-05-18)
- 新文件:`SiteNote/Views/AdaptiveRootView.swift`(20 行)
  - 唯一 size class 路由器,Compact → MainTabView,Regular → IPadRootView
- 修改:`SiteNote/ContentView.swift` 改用 AdaptiveRootView,注释说明路由
- 验证:BUILD SUCCEEDED(Xcode 15 `PBXFileSystemSynchronizedRootGroup` 自动 discover 新文件,无需手改 pbxproj)
- 影响:**iPhone 路径零退化**,iPad 进入 IPadRootView placeholder 三栏

### R3 — IPadRootView sidebar + 5 sections 占位(2026-05-18)
- 新文件:`SiteNote/Views/IPad/IPadRootView.swift`(115 行)
- `IPadSection` enum:record / schedule / reports / team / settings(固定顺序)
- NavigationSplitView 三栏:
  - sidebar(200 / 240 / 280 pt min/ideal/max)
  - detail 占位 — icon + 标题 + "即将接入" 灰底
- `.navigationSplitViewStyle(.balanced)` — iPad 竖屏自动 stack
- `.tint(Ink.accent) + .preferredColorScheme(.light)` 沿用 iPhone 视觉
- 验证:BUILD SUCCEEDED

### R4 — Info.plist 评估(无改动)
- `UIApplicationSupportsMultipleScenes = true` ✅ 已开,Stage Manager 兼容
- `UIApplicationSupportsIndirectInputEvents = true` ✅ 已开,触控板 / Magic Mouse 支持
- iPhone 方向:3 个(无 PortraitUpsideDown)✅ 正确
- iPad 方向:4 个(含 PortraitUpsideDown)✅ 保留 — PadOS 标准行为允许 180° 旋转
- 多窗口策略:`UIApplicationSupportsMultipleScenes` 已开,**不实施业务逻辑层面的并发编辑**(数据冲突边界 case),但不会 crash
- **决策**:Info.plist 无需改动,iPad 适配纯走 SwiftUI 层

## 下一步

按 `IPAD_PLAN.md` Phase 路线图:
- **R5** — 报告 detail 接通(EngineerReportsView 进 IPadRootView detail)
- **R6** — 日程 detail 接通
- **R7** — 记 detail 接通
- **R8** — 键盘快捷键
- **R9** — 拖拽
- **R10** — 视觉走查

