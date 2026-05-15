# SiteNote v1.1 Release Notes

> App Store Connect 用 — What's New。中英双语。各 ≤ 4000 字符。

---

## 简体中文(贴到 zh-Hans)

**v1.1 — 工程师模式重做 + 报告 PDF 升级**

新增

• 工程师模式全新独立设计:记录 / 报告 / 日程 / 设置 四个 Tab,极简专注的工程师工作流
• 巡检报告 PDF 全新布局:大尺寸 A3 图纸 + 红色十字位置标记 + 编号 + 自适应照片网格,每条记录独占连续页面
• 报告状态自动归档:邮件发送成功后,草稿自动跳到"已提交"
• 工地预设功能:绑定工地与项目信息,导出报告时自动 prefill Header
• 图纸缩略图大幅放大,位置标记一目了然

改进

• 项目经理主屏修复:点击 stats 分类筛选后,其他段不再消失
• "今天到期"命名统一(主屏与日志一致)
• 月度报告条形图修复:Top 5 工种名不再被截断
• 移除 Tradie 工头模式,聚焦工程师 + 项目经理两种角色,减少认知负担
• Engineer 模式全面禁用 AI 处理,转写忠实录音原话
• 工地新建流程改进:先输入地址,自动派生工地名称
• 邮件正文模板英文化,匹配国际客户场景

修复

• Photo Editor 文字标注键盘弹起时序优化
• 报告"选记录"对话框:超出当前筛选的已选记录现在会标灰显示在末尾(之前会"消失")
• 多项小 polish 与 i18n 完善

---

## English(paste to en-US)

**v1.1 — Engineer redesign + Report PDF overhaul**

What's New

• Engineer mode redesigned from scratch: Record / Reports / Schedule / Settings — focused 4-tab workflow for site engineers
• Brand new inspection report PDF layout: large A3 floor plan + red crosshair pin + numbered records + adaptive photo grid, one record per page
• Reports auto-archive after sending: drafts move to "Submitted" automatically once the email is sent
• Site presets: bind project info (No. / Client / Inspection Type) to a site, auto-prefill report headers
• Floor plan thumbnails are dramatically larger, pin location is now crystal clear

Improvements

• PM home screen fix: tapping a stats filter no longer hides other sections
• "Today due" naming unified across home and log tabs
• Monthly bar chart fix: Top 5 trade names no longer truncated
• Removed Tradie mode — focus on Engineer + PM, reduce cognitive load
• Engineer mode fully disables AI processing — transcripts are your original words, no rewriting
• Improved new-site flow: enter address first, site name auto-derived
• Email template anglicized for international clients

Fixes

• Photo Editor text tool: keyboard focus timing improved
• Report "Select Notes" sheet: previously-selected notes outside current filter now appear greyed at the bottom (used to "disappear")
• Multiple small polishes & i18n improvements

---

## 字数核对

- 中文段: ~520 字符(远低 4000 上限)
- English: ~720 字符(远低 4000 上限)

---

## 提交 App Store Connect 时

App Store tab → 1.1 版本 → 滚到 **What's New in this Version**
- 简体中文(zh-Hans):贴上面"简体中文"段(去掉 markdown 标题)
- 英文(en-US):贴上面"English"段
- 其他语言(如有):留空,Apple 会继承 en-US 显示

---

## Marketing 配套(社媒发文用)

### Twitter / X
> SiteNote v1.1 来了 🚀
> 工程师模式独立 4 Tab + A3 图纸 PDF + 自动归档报告。
> 一次现场记录,一份专业 PDF 直接发 builder。
> #ConstructionTech #SiteEngineer #iOS

### 小红书 / 朋友圈
> SiteNote 这次大改:
> ✅ 工程师专版,4 个 Tab 极简
> ✅ 巡检报告 A3 图纸 + 红十字定位
> ✅ 邮件发了自动归档,工作流闭环
> 工地巡检 + 出报告,1 个 App 搞定

### 应用页面截图建议
1. Engineer 主屏 + 录音中(动态感)
2. Engineer 报告 Tab + 一份草稿打开
3. PDF 内页(大 A3 图纸 + 红十字 + 2x2 photos)
4. Engineer Settings 5 段
5. PM 主屏 + stats(对比 v1.0 stats filter 修复后)

---

## 已知问题(不上 Release Notes,内部备忘)

- iCloud 同步暂未上线(v1.2 重点)
- 团队协作功能暂未上线(v1.2-1.3)
- 触控目标部分 < 44pt(v1.1 polish 阶段处理)
- 设计 token 部分硬编码(v1.2 重构)
