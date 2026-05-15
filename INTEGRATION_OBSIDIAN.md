# SiteNote → construction-pm Obsidian vault 集成

> **状态**：iOS 端 + vault 端全部代码完成 + 编译通过 ✅
> **你只需做 2 件事**：Xcode ⌘R 装到 iPhone + 在 App 里选导出文件夹。

---

## 已完成（你不用碰）

### iOS 端（SiteNote App）
- ✅ `Services/ObsidianExportService.swift` — Note 渲染成 markdown + 导出到 iCloud Drive 文件夹
- ✅ `Views/SettingsView.swift` — Settings → 报告与导出 里加了"Obsidian 同步"区块
   - 选导出文件夹（系统 fileImporter）
   - "导出全部速记到 Obsidian" 按钮
   - "只导出最近 7 天" 按钮
- ✅ `Views/NoteDetailView.swift` — 每条笔记详情页底部加了"📂 导出到 Obsidian"按钮
- ✅ Xcode clean build 通过，无错误

### vault 端（construction-pm）
- ✅ `intake.py` 加了 SiteNote markdown fast-path handler（不调 Claude）
- ✅ `is_eligible()` 调宽 text 文件最小阈值（100 字节，支持短笔记）
- ✅ 实测验证（测试文件已成功路由 + hazard followup 自动添加）

---

## 你需要做的 2 步（10 分钟）

### 1. Xcode 装到 iPhone（5 分钟）

```
1. 打开 Developer/SiteNote/SiteNote.xcodeproj
2. 顶栏选你的 iPhone（连 USB 或同 WiFi）
3. ⌘R（Build & Run）
4. 等装好，App 自动打开
```

### 2. 第一次设置导出文件夹（5 分钟）

在 iPhone 上：

```
1. 打开 SiteNote
2. 设置 Tab → 报告与导出 → "Obsidian 同步" 区块
3. 点"导出文件夹" → 跳出 Files App
4. 导航到：
   位置 → iCloud Drive → Obsidian → construction-pm → 00_Inbox
5. 点右上角"打开"（选中这个文件夹）
6. 回到 SiteNote，路径已显示在按钮下方
```

---

## 验证流程

### 单条导出（NoteDetailView）

1. 在 SiteNote 选任意一条已有笔记
2. 滑到底部，点"📂 导出到 Obsidian"
3. 弹出 ✓ 提示
4. 等 5-15 秒（iCloud 同步）
5. Mac 上看 `vault/01_Projects/{对应项目}/14_Daily_Log/`，应该有这条笔记

### 批量导出（SettingsView）

1. Settings → 报告与导出 → "导出全部速记到 Obsidian"
2. 弹出 ✓ "导出 X 条 / 跳过 Y 条 / 失败 Z 条"
3. Mac vault/00_Inbox 5-30 秒内陆续出现 .md 文件
4. intake.py 自动路由到各项目

### 隐患（hazard）特殊处理

- SiteNote 里把笔记标 🚨 隐患
- 导出后，intake 看到 frontmatter `hazard: true`
- 自动加进 `vault/10_AI_Workspace/_Followups/{当周}.md`，2 天截止
- 第二天 06:30 早 briefing 把这条 hazard followup 显示在"今日必做"

---

## site 字段必须匹配项目别名

intake.py 用 `vault/01_Projects/_aliases.json` 找项目。你在 SiteNote 里设的 siteTag 必须能匹配上：

| 项目目录 | 在 SiteNote 里 siteTag 可以填 |
|---|---|
| 20-Forsyth | "20 Forsyth" / "20 Forsyth St" / "20-Forsyth" |
| 38-Forsyth | "38 Forsyth" / "38 Forsyth St" |
| 2-Stan | "2 Stan" / "2 Stan St" |
| 39-Pearl-Bay | "39 Pearl Bay" / "Pearl Bay" |
| 39-Pearl-Bay-Lift | "39 Pearl Bay Lift" |
| 40-Central | "40 Central" |
| 8-Battle | "8 Battle" |

匹配不上 → 文件去 `00_Inbox/_pending_review/`，你 Mac 上手动归位（或扩 _aliases.json）。

---

## 故障排查

| 症状 | 怎么修 |
|---|---|
| 导出后笔记没出现在 Mac | iCloud 没同步好。Mac Finder 看 iCloud Drive 同步状态。可重启 Mac 上的 `bird` 进程 |
| 路径 picker 找不到 Obsidian | iPhone 设置 → Apple ID → iCloud → iCloud Drive → 把 Obsidian 打开 |
| 导出后进了 _pending_review | siteTag 没匹配项目别名。看上面表 |
| Hazard 没加 followup | frontmatter 的 hazard 必须是小写 `true` |
| Xcode build 失败"cannot find 'X' in scope" | Cmd+Shift+K Clean，再 ⌘R |

---

## 数据流（最终长这样）

```
┌────────────────────────────────────────────────┐
│ iPhone 工地                                    │
│ 长按 SiteNote 🎤                               │
│ "钢筋有问题"+ 标 hazard                          │
└────────────────────┬───────────────────────────┘
                     │ 点"📂 导出到 Obsidian"（1 秒）
                     ▼
┌────────────────────────────────────────────────┐
│ ObsidianExportService                          │
│ 渲染 markdown + frontmatter                    │
│ 写到 iCloud Drive/Obsidian/.../00_Inbox/       │
└────────────────────┬───────────────────────────┘
                     │ iCloud 同步（5-15 秒）
                     ▼
┌────────────────────────────────────────────────┐
│ Mac vault/00_Inbox/                            │
│ intake.py watchdog 看到新 .md                  │
└────────────────────┬───────────────────────────┘
                     │ frontmatter 含 source: SiteNote
                     │ → fast path（不调 Claude）
                     ▼
┌────────────────────────────────────────────────┐
│ try_handle_sitenote()                          │
│ site="20 Forsyth" → 匹配到 20-Forsyth-...     │
│ 移动到 {项目}/14_Daily_Log/                   │
│ hazard=true → 写一条 followup                 │
└────────────────────┬───────────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────────┐
│ 第二天 06:30                                    │
│ morning_briefing.py 把 hazard followup         │
│ 显示在"今日必做"区                              │
│ 你早上一打开 Obsidian 就看到 → 跟进             │
└────────────────────────────────────────────────┘
```

---

## 现在就做的下一步

1. **Xcode ⌘R** 装到 iPhone（必做）
2. **设置 → 报告与导出 → Obsidian 同步 → 选文件夹**（必做）
3. 找一条现有笔记测试导出
4. 若成功 → 接下来工地用 SiteNote 录音都会自动同步到 Mac vault
5. 若失败 → 看 Mac `/tmp/intake.out`，给我反馈
