# 触控区域审计报告 (2026-05-16 overnight)

## iOS HIG 要求
- 最小触控目标 **44pt × 44pt**
- 工地工人戴手套场景建议更大(50pt+)

## 项目现状

**全项目 .frame ≤ 36pt 的位置:64 处**(grep 统计,不全是 Button — 部分是 icon 容器或 Spacer)。

## 关键 Button / NavLink 触控目标盘点

### 主要 button 的尺寸(实际可点区域)

| 位置 | 元素 | 尺寸 | 评估 |
|---|---|---|---|
| EngineerRecordView mic 大按钮 | DragGesture | 132 × 132 | ✅ 远超标准 |
| EngineerRecordView 相机大按钮 | onTap | 132 × 132 | ✅ |
| RecordView 同上 | 同上 | 132 × 132 | ✅ |
| LogTabView+Ledger:96-105 dayNavigator(左/右箭头) | Button | 36 × 36 | ⚠️ < 44pt |
| FloorPlanLookupView:237 dayNavigator | Button | 36 × 36 | ⚠️ |
| EngineerReportsView:136 + icon container | Button frame | 36 × 36 | ⚠️ |
| ReportsView:74 齿轮按钮 | NavLink | 32 × 32 | ⚠️ < 44pt |
| LogTabView:175 齿轮按钮 | NavLink | 32 × 32 | ⚠️ |
| EngineerRecordView:192 齿轮 | NavLink | 32 × 32 | ⚠️ |
| RecordView:425 photo 缩略图 删除按钮 | Button | 24 × 24 | ⚠️⚠️ |
| RecordView:329 单选 checkbox | Image | 24 × 24 | ⚠️⚠️(但被 List row 整体包,实际可点 ≈ 整行 60pt) |
| EngineerRecordView 删除按钮 size:18 | Button | 18 × 18 + offset | ⚠️⚠️(同上,在大图上偏移 -6,实际容器更大) |
| PhotoEditorView:291 颜色圆点 | Button | 32 × 32 | ⚠️ |
| settingsRow icon | non-tap container | 34 × 34 | N/A(icon 容器,整 row 是 NavLink) |
| 各 contextChip / capsule | Button | inset 10,5 ≈ 30 × 22 | ⚠️ |

## 评估

**真实风险点(常用、戴手套场景)**:
1. **dayNavigator 36pt 箭头**(LogTabView+Ledger):用户每天切换日期都用 — 应提到 44pt
2. **顶部齿轮 32pt**:几乎所有主页都有 — 应提到 44pt
3. **照片删除小按钮 18-24pt**:常误触和真按之间难分辨

**伪风险(整行容器包裹)**:
- NoteRow / 各 List row 内部的 22pt icon:实际可点是整 row(高 ≥ 56pt)
- settingsRow 的 34pt icon container:整 row NavLink

## 建议

1. **轻量整改**:dayNavigator 36 → 44(+边距 4pt 影响小)
2. **齿轮**:32 → 44(可能影响顶栏对齐,需视觉验证)
3. **照片小删除按钮**:18 → 28(明显改进,需视觉验证不挡照片)
4. 整体改动 **risk 中**,需视觉 review

**整改工作量**:小(~10 处替换,半天)。**风险**:中(视觉对齐变化)。
**建议**:**v1.1 上架前最后一轮 visual polish** 里做。这次 overnight 不动。

## 完整 grep 输出

参考(部分):
SiteNote/Views/EngineerReportsView.swift:136:                .frame(width: 36, height: 36)
SiteNote/Views/EngineerReportsView.swift:245:            .frame(width: 28, height: 28)
SiteNote/Views/ReportsView.swift:74:                    .frame(width: 32, height: 32)
SiteNote/Views/ReportsView.swift:442:                    .frame(width: 22)
SiteNote/Views/ReportsView.swift:548:                .frame(width: 22)
SiteNote/Views/ReportsView.swift:586:                .frame(width: 22)
SiteNote/Views/NoteDetailView+Photos.swift:61:                .frame(height: 240)
SiteNote/Views/NoteDetailView+Photos.swift:126:                    .frame(width: 120, height: 120)
SiteNote/Views/NoteDetailView+Photos.swift:131:                            .frame(width: 120, height: 120)
SiteNote/Views/NoteDetailView+Photos.swift:152:                .frame(width: 120, height: 120)
SiteNote/Views/EngineerRecordView.swift:192:                        .frame(width: 32, height: 32)
SiteNote/Views/EngineerRecordView.swift:518:                .frame(width: 132, height: 132)
SiteNote/Views/EngineerRecordView.swift:522:                    .frame(width: 142, height: 142)
SiteNote/Views/EngineerRecordView.swift:528:        .frame(width: 132, height: 132)
SiteNote/Views/EngineerRecordView.swift:554:            .frame(width: 132, height: 132)
SiteNote/Views/PDFExportView.swift:145:                    .frame(width: 22)
SiteNote/Views/PDFExportView.swift:148:                    .frame(width: 12, height: 12)
SiteNote/Views/PDFExportView.swift:326:                    .frame(width: 28)
SiteNote/Views/PMSettingsView.swift:152:                .frame(width: 34, height: 34)
SiteNote/Views/NoteDetailSheets.swift:223:                    .frame(width: 24)
SiteNote/Views/NoteDetailSheets.swift:246:                    .frame(width: 16, height: 16)
SiteNote/Views/NoteDetailSheets.swift:248:                    .frame(width: 24)
SiteNote/Views/NoteDetailSheets.swift:329:                                .frame(width: 10, height: 10)
SiteNote/Views/JargonTermsEditorView.swift:31:                                .frame(width: 18)
SiteNote/Views/RecordView.swift:329:                    .frame(width: 24, height: 24)
SiteNote/Views/RecordView.swift:425:                        .frame(width: 32, height: 32)
SiteNote/Views/RecordView.swift:900:                .frame(width: 132, height: 132)
SiteNote/Views/RecordView.swift:904:                    .frame(width: 142, height: 142)
SiteNote/Views/RecordView.swift:910:        .frame(width: 132, height: 132)
SiteNote/Views/RecordView.swift:937:            .frame(width: 132, height: 132)
SiteNote/Views/DatabaseRecoveryView.swift:197:                    .frame(width: 28, alignment: .leading)
SiteNote/Views/PhotoEditorView.swift:291:                            .frame(width: 32, height: 32)
SiteNote/Views/SubTagsEditorView.swift:44:                                    .frame(width: 18, height: 18)
SiteNote/Views/SubTagsEditorView.swift:176:                                .frame(width: 10, height: 10)
SiteNote/Views/InspectionDraftListView.swift:195:            .frame(width: 28, height: 28)
SiteNote/Views/LogTabView+Ledger.swift:76:                    .frame(width: 36, height: 36)
SiteNote/Views/LogTabView+Ledger.swift:102:                    .frame(width: 36, height: 36)
SiteNote/Views/LogTabView+Ledger.swift:258:                    .frame(width: 28, alignment: .center)
SiteNote/Views/LogTabView+Ledger.swift:342:                        .frame(width: 28, alignment: .center)
SiteNote/Views/LogTabView+Ledger.swift:463:                    .frame(width: 28, alignment: .center)
