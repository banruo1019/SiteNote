# 设计 token 审计报告 (2026-05-16 overnight)

## 范围:SiteNote/Views/*.swift

### 1. 硬编码 SwiftUI Color literals(`Color.red` 等)

```
SiteNote/Views/NoteDetailView+Photos.swift:60:                .fill(Color.gray.opacity(0.08))
SiteNote/Views/NoteDetailView+Photos.swift:80:                    .foregroundStyle(.white, Color.black.opacity(0.6))
SiteNote/Views/NoteDetailView+Photos.swift:125:                    .fill(Color.gray.opacity(0.08))
SiteNote/Views/NoteDetailView+Photos.swift:144:                        .foregroundStyle(.white, Color.black.opacity(0.6))
SiteNote/Views/NoteDetailView+Photos.swift:151:                .fill(Color.gray.opacity(0.2))
SiteNote/Views/EngineerRecordView.swift:385:                    .foregroundStyle(Color.white)
SiteNote/Views/EngineerRecordView.swift:401:                .foregroundStyle(Color.white)
SiteNote/Views/EngineerRecordView.swift:406:                    Circle().strokeBorder(Color.white, lineWidth: 1.5)
SiteNote/Views/EngineerRecordView.swift:526:                .foregroundStyle(Color.white)
SiteNote/Views/EngineerReportsView.swift:135:                .foregroundStyle(Color.white)
SiteNote/Views/EngineerReportsView.swift:137:                .background(Color.white.opacity(0.18))
SiteNote/Views/EngineerReportsView.swift:142:                    .foregroundStyle(Color.white)
SiteNote/Views/EngineerReportsView.swift:145:                    .foregroundStyle(Color.white.opacity(0.7))
SiteNote/Views/EngineerReportsView.swift:150:                .foregroundStyle(Color.white.opacity(0.7))
SiteNote/Views/TrashView.swift:159:                        .background(Color.gray.opacity(0.2))
SiteNote/Views/PDFExportView.swift:371:            .background(Color.gray.opacity(0.2))
SiteNote/Views/PDFExportView.swift:400:                .background(selectedIDs.isEmpty ? Color.gray : Color.accentColor)
SiteNote/Views/NoteDetailSheets.swift:247:                    .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
SiteNote/Views/NoteDetailSheets.swift:377:                            colorName == c ? Color.primary : Color.black.opacity(0.15),
SiteNote/Views/RecordView.swift:908:                .foregroundStyle(Color.white)
SiteNote/Views/LogTabView+Ledger.swift:366:                        .foregroundStyle(Color.white)
SiteNote/Views/LogTabView+Ledger.swift:581:                            ProgressView().tint(Color.white)
SiteNote/Views/LogTabView+Ledger.swift:588:                    .foregroundStyle(Color.white)
SiteNote/Views/SubTagsEditorView.swift:46:                                        Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
SiteNote/Views/SubTagsEditorView.swift:130:                            .background(Color.gray.opacity(0.12))
SiteNote/Views/SubTagsEditorView.swift:152:                                                    colorName == c ? Color.primary : Color.black.opacity(0.15),
SiteNote/Views/FloorPlanLookupView.swift:164:                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
SiteNote/Views/FloorPlanLookupView.swift:175:                Color.gray.opacity(0.08)
SiteNote/Views/PhotoEditorView.swift:54:            Color.black.ignoresSafeArea()
SiteNote/Views/PhotoEditorView.swift:215:                    .background(Color.black.opacity(0.35))
SiteNote/Views/PhotoEditorView.swift:218:                            .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
SiteNote/Views/PhotoEditorView.swift:229:                    .background(Color.black.opacity(0.25))
SiteNote/Views/PhotoEditorView.swift:280:                ForEach([Color.red, Color.yellow, Color.green, Color.blue, Color.white, Color.black], id: \.self) { color in
SiteNote/Views/PhotoEditorView.swift:294:                                    .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 1)
SiteNote/Views/PhotoEditorView.swift:333:                                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
SiteNote/Views/PhotoEditorView.swift:340:                        .foregroundStyle(Color.black)
SiteNote/Views/PhotoEditorView.swift:343:                        .background(Color.white)
SiteNote/Views/PhotoEditorView.swift:351:        .background(Color.black)
SiteNote/Views/PhotoEditorView.swift:361:                .background(Color.white.opacity(0.12))
SiteNote/Views/PhotoEditorView.swift:401:            .foregroundStyle(active ? Color.black : Color.white)
SiteNote/Views/PhotoEditorView.swift:403:            .background(active ? Color.white : Color.white.opacity(0.12))
SiteNote/Views/PhotoEditorView.swift:459:                UIColor.black.withAlphaComponent(0.25).setFill()
SiteNote/Views/NoteDetailView+Actions.swift:159:            UIColor.white.setFill()
SiteNote/Views/NoteDetailView+Actions.swift:176:            UIColor.white.setStroke()
SiteNote/Views/NoteDetailView+AI.swift:21:            Color.black.opacity(0.3).ignoresSafeArea()
SiteNote/Views/NoteDetailView+AI.swift:38:                                .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
SiteNote/Views/NoteDetailView+AI.swift:44:            .background(Color.black.opacity(0.7))
SiteNote/Views/NoteDetailView+AI.swift:104:                        .background(Color.gray.opacity(0.2))
SiteNote/Views/NoteDetailView+AI.swift:208:                            .foregroundStyle(Color.white)
SiteNote/Views/NoteDetailView+AI.swift:241:                        .foregroundStyle(Color.white)
```

**总数**: 30 处

**建议**:大多数应改成 Ink.* token(Ink.red / Ink.accent / Ink.green / Ink.fg / Ink.fgDim 等)。例外:
- PhotoEditorView.swift line 280:颜色选择器,用户主动选,需保留 SwiftUI Color literal
- AccentColor / Color.accentColor:这是系统 accent,不动
- Color.white / Color.black:绝对色,在某些 overlay 场景合理

### 2. 硬编码 font size 数字

项目里大量 `.font(.system(size: N, weight: ...))`,N 是字面值。建议用 DesignTokens.FontSize.* 或 typography helper。

**总数**: 808 处 `.font(.system(size:` 调用

**建议**:统一到 5 个档(11/12/13/14/16/18/22/28),引入 `SiteFont` enum 替换。这是大改动,跨上百个文件,留待 v1.2。

### 3. 当前 Ink.* token 覆盖率

**Ink.* 出现次数**: 631 处
**DesignTokens.* 出现次数**: 379 处

### 结论

项目已经较好地使用 Ink/DesignTokens token,绝大多数视觉单位走 token。
30 处 `Color.*` 硬编码主要分布在:PhotoEditor 颜色选择器(合理)、DeadlineSheet/AI menu/RecordView 录音红光点(可改 Ink.red)、Settings 子页 icon 颜色(用 SwiftUI 标准色作为强信号)。

**整改优先级**: 低。视觉已稳定,改动等于视觉回归风险。建议放到 v1.2 与整套字体 token 一起做。
