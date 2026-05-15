# 空态文案审计报告 (2026-05-16 overnight)

## 现状

项目里 ~20 处空态文案,分布在 12 个文件。已经形成 3 种半通用 helper:
- `EngineerRecordView.emptyHint` / `EngineerReportsView.emptyHint` / `RecordView.emptyHint` / `GlobalSearchView.emptyHint`
- `LogTabView.emptyOverviewState` / `LogTabView+Ledger.emptyDayState`
- 其他 view 内联 `Text("...")`

## 文案盘点

### 主屏类("还没有"开头)
- RecordView:`今天没有待办`
- EngineerRecordView:`还没有记录`
- EngineerReportsView:`还没有报告`
- InspectionDraftListView:`还没有巡检报告`
- JargonTermsEditorView:`还没有自定义词。下面输入框加一个试试。`
- SubTagsEditorView:`还没有分类`
- FloorPlanLookupView:`还没有工地` / `{site} 还没有楼层`

### 列表搜索结果空态
- LogTabView:`还没有速记` / `没有匹配的速记`(基于 searchText)
- NotePickerSheet:`当前筛选条件下没有记录。`
- ReportsView:`本周还没有记录,去「记」tab 按住 mic 开始。`

### 台账各 sub-tab 空态(LogTabView+Ledger,4 处)
- 人员:`当天还没人员记录`
- 机械:`当天还没机械记录`
- 事件:`当天还没送达 / 访客 / 事件`
- 速记:`当天还没速记`

### 内联占位
- NoteDetailView line 429:TextField placeholder `(空内容)`
- InspectionFormView line 629:`(空记录)`(NotePickerSheet 用同样)

### 历史性空态
- SettingsView line 1151:`还没有分享过。在日志 tab 的某一天底部用「生成今日简报」导出 PDF。`

## 风格观察

**好的**:
- 都用"还没有X"开头(中文,统一)
- 大多包含 CTA(怎么开始)
- LogTabView+Ledger 4 个空态有 `icon + 主标题 + 引导句` 三段式

**待统一**:
- 有的有 icon(emptyDayState),有的没(emptyHint)
- 字号:14pt semibold / 13pt medium / 12pt 混用
- 引导句:有的提供 "去「记」tab 按住 mic 开始",有的没

## 建议

引入 `EmptyStateView` reusable component:
```swift
struct EmptyStateView: View {
    let icon: String              // SF Symbol
    let title: String             // 主标题
    let subtitle: String?         // 引导句(可选)
    let cta: (label: String, action: () -> Void)?   // 可选 CTA 按钮
}
```

各 view 替换内联 `Text("...")` 为 `EmptyStateView(...)`。

**整改工作量**:中(~10 处替换 + 1 个组件文件)。**风险**:低(纯视觉,无业务变更)。
**建议**:**v1.1 后期 polish 一次性做完**,这次 overnight 不动。
