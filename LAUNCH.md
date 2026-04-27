# SiteNote 上线攻略

> 给"将要上 App Store 的你"。每一项打钩才往下走，不要跳。
> 最后更新：2026-04-25

---

## Phase 1 · 上线前必修（本周内完成）

### ✅ R3 SwiftData 启动失败友好降级
已完成 — `DatabaseRecoveryView.swift` + `DiagnosticPackager.swift` + 改 `SiteNoteApp.swift`。

### ⬜ 1.1 · Info.plist Usage Description 自查（30 分钟）

打开 `SiteNote/Info.plist`（或 Xcode → SiteNote target → Info），确保以下 5 个 key 都存在且文案诚恳：

| Key | 推荐文案 |
|---|---|
| `NSMicrophoneUsageDescription` | SiteNote 用麦克风录下你的工地速记，录音文件存在你手机本地。 |
| `NSSpeechRecognitionUsageDescription` | SiteNote 把你的语音转成文字方便检索和导出 PDF，转写在设备本地完成。 |
| `NSLocationWhenInUseUsageDescription` | SiteNote 用你的位置自动关联工地，位置不会上传到任何服务器。 |
| `NSCameraUsageDescription` | SiteNote 用相机拍工地现场照片附在速记里。 |
| `NSPhotoLibraryAddUsageDescription` | SiteNote 把巡检照片保存到你的相册。 |

**审核重点**：Apple 会读这些文案。**不要含糊**（"用于改善体验"会被拒），要直说"用来干什么、数据去哪"。

**自查命令**（在工程根目录跑）：
```bash
grep -A1 "UsageDescription" SiteNote/Info.plist
```

### ⬜ 1.2 · 隐私政策页面（45 分钟）

App Store 必须有一个**公网可访问的 URL**指向隐私政策。最省事方案：GitHub Pages。

**步骤**：
1. 新建 GitHub repo（公开），如 `sitenote-privacy`
2. 加一个 `index.md`，按下面模板写
3. Settings → Pages → 选 main branch → 拿到 URL（如 `https://banruo.github.io/sitenote-privacy/`）
4. 把这个 URL 填到 App Store Connect 的 "Privacy Policy URL"

**模板（中英双语，照搬填空）**：
```markdown
# SiteNote 隐私政策 / Privacy Policy

最后更新 / Last updated: 2026-04-XX

## 我们收集什么数据 / What we collect
SiteNote 是本地应用。**所有速记数据（录音、文字、照片、位置、提醒）都只存储在你的设备上**，
我们的服务器不接收、不存储、不分析这些数据。

## 第三方 / Third parties
当你**主动**在设置里启用 OpenAI 集成并提供你自己的 API Key 时，
SiteNote 会把你的语音转写文本发送到 OpenAI 进行：
- 文本润色
- 工地分类
- 结构化日志条目抽取

发送的内容仅限文本，不包含原始音频或位置。
OpenAI 处理你的数据按 OpenAI 自己的隐私政策执行：https://openai.com/policies/privacy-policy

如果你不启用 OpenAI 集成，**没有任何数据会离开你的设备**。

## 你的权利 / Your rights
- 任何时候可在设置里关闭 OpenAI 集成
- 任何时候可"一键清空所有内容"删除全部本地数据
- 可在设置里"导出全部数据为 ZIP"备份所有内容

## 联系 / Contact
banruostudio@gmail.com
```

### ⬜ 1.3 · App Store Connect 应用资料（60 分钟）

去 https://appstoreconnect.apple.com → My Apps → "+" → New App。

填写：
- **Bundle ID**：`com.banruoyang.sitenote`（已在 Xcode 配置）
- **Name**：`SiteNote · 工地速记`（最多 30 字符）
- **Subtitle**：`语音→提醒→PDF · 工程师专用`（最多 30 字符）
- **Primary Category**：Productivity（生产力）
- **Secondary Category**：Business
- **Price**：Free（见本文档末尾的定价说明）

### ⬜ 1.4 · App Privacy Details（在 App Store Connect 里填，30 分钟）

App Store Connect → SiteNote → App Privacy → 按这个填：

| 数据类型 | 收集？ | 用途 | 链接到用户身份？ |
|---|---|---|---|
| Audio Data（录音）| 是 | 仅设备本地，App 功能 | 否 |
| Photos | 是 | 仅设备本地，App 功能 | 否 |
| Coarse Location | 是 | 仅设备本地，App 功能 | 否 |
| User Content（语音转写文本）| 是 | **第三方处理**：OpenAI（仅当用户启用） | 否 |

**关键**：**所有项都不要勾"用于追踪"**。SiteNote 不做广告也不卖数据。

### ⬜ 1.5 · 应用截图（90 分钟）

Apple 要求至少 5 张 6.7" 截图（最新 iPhone Pro Max 尺寸 1290×2796）。

**推荐 5 张顺序**（要"功能 → 价值"递进）：
1. **录音中** — 大麦克风按钮 + 波形动画 + "正在录音"
2. **保存后顶部** — 黄高亮 note + 简介文字 + UndoToast
3. **日志台账模式** — 一天的人员/机械/事件清单
4. **AI 抽出 banner** — 双按钮"标为施工日志/保留提醒"
5. **导出 PDF 预览** — 整日施工日志 PDF 第一页

**做法**：Xcode 模拟器选 iPhone 17 Pro Max（或最新型号）→ ⌘S 截图 → 用 [Screenshots.pro](https://screenshots.pro) 或 Figma 加文字标注（"一句话快速记录"等）。

### ⬜ 1.6 · App 描述（45 分钟）

**Promotional Text**（170 字符，可随时改不用重审）：
```
工地速记 · 长按说话 · AI 自动整理 · 一键 PDF 给业主
支持 OpenAI 和 Apple Intelligence，所有数据存你设备上。
```

**Description**（4000 字符）：
```
SiteNote 是给工程师/项目经理/工地主管用的语音速记 App。

🎤 长按录音
说什么记什么。"今天来了 4 个水工"、"东区漏水要紧急处理"、"挖机 8 点半到了"。
不用打字，不用整理，松手就存。

📋 自动结构化（可选 AI）
启用 AI 后：
· 自动识别人员到场、机械进场、隐患警报
· 自动关联到当前工地（基于 GPS）
· 自动整理成"今日施工日志"

🚨 智能提醒
普通速记 7 天内每天早上提醒一次。
带"隐患"标记的速记 10 天内每天早晚双提醒。
完成后自动取消。

📄 一键导 PDF
施工日志、巡检记录、EOT 工期延误证据 — 都能直接导出 PDF 发给业主或律师。

🔒 数据是你的
· 所有数据本地存储，包括录音和照片
· OpenAI Key 由你自己提供（也可不启用，用 Apple Intelligence）
· 任意时刻一键清空 / 备份全部数据

适合谁
· 项目经理、工程师、工头
· 需要做工地日志、巡检记录、EOT 索赔的人
· 不想打字、想用语音搞定记录的人

不收订阅、不卖数据、不发广告。
```

**Keywords**（100 字符，逗号分隔）：
```
工地,日志,巡检,语音,提醒,工程,建筑,施工,PDF,EOT,工程师,项目经理,语音转文字,AI
```

### ⬜ 1.7 · 测试设备 + Apple Developer Account
- 至少 1 部 iPhone 真机（你已有）
- Apple Developer Account（$99/年，已开就略过）
- Xcode 里 SiteNote target → Signing & Capabilities → Team 选你的开发者账号
- iCloud capability 不要勾（v1 不用）

---

## Phase 2 · TestFlight Beta（3-7 天）

### ⬜ 2.1 · Archive + Upload 第一版
1. Xcode 工具栏目标改 "Any iOS Device (arm64)"
2. Product → Archive（5-10 分钟）
3. Organizer 打开 → Distribute App → App Store Connect → Upload
4. 等 5-15 分钟，App Store Connect 里 TestFlight tab 出现这个 build

### ⬜ 2.2 · 内部测试（你自己 + 1-2 个人）
- App Store Connect → TestFlight → Internal Testing → 加成员
- 测试者从 TestFlight App 装

### ⬜ 2.3 · 外部测试（3-5 个工地朋友）
- TestFlight → External Testing → 创建群组
- 第一次外部测试要 Apple 走个简单审核（< 24h，比正式审核宽松）
- 给朋友发 Public Link 或邀请邮件

### ⬜ 2.4 · 反馈表单（在 App 内或外）
**简单做法**：建一个 [Tally.so](https://tally.so) 或 Google Form：
1. 你测了几天？
2. 最常用的功能是？（多选）
3. 最不顺手的一处是？（开放）
4. 你愿意推荐给同事吗？1-10
5. 如果收 ¥38 一次性买断，你会买吗？

**目的**：知道哪个功能值得做，哪个可以砍。**不是收测试 bug，那应该走 TestFlight 内置反馈**。

### ⬜ 2.5 · 真用 7 天
- 你自己每天到工地用
- 朋友至少用 3 天
- 每晚记一条"今天哪里别扭"
- **不要**急着改——观察"反复出现的同一个抱怨"，那个才是真问题

---

## Phase 3 · 提交 App Store 审核（3-5 天）

### ⬜ 3.1 · 修 critical bug
TestFlight 反馈里**只修这两类**：
- 崩溃 / 数据丢失 / 闪退
- 主流程走不通（录音不工作、PDF 导不出）

**不要改设计 / 加功能**。审核期间稳定优先。

### ⬜ 3.2 · 写 App Review Information
App Store Connect → Submit for Review 前会让填：
- **Sign-In Required**：No（如果不需要登录）或 Yes（如果有）
- **Demo Account**：填一个测试账号（如果有登录）。SiteNote 没登录可以跳过
- **Notes**（给审核员看）：

```
SiteNote is a voice-first note app for construction site managers.

Key features to test:
1. Long-press the mic button to record (requires microphone permission)
2. Speech is transcribed locally on device (Apple Speech Recognition)
3. Optional AI features (polish/classify/extract) require user to provide
   their own OpenAI API key in Settings → AI Engine. App works fully without it.
4. PDF export from any day in the Log tab

No login required. No data leaves the device unless user enables OpenAI.

Tested on iPhone 15 Pro Max running iOS 26.4.

Contact: banruostudio@gmail.com
```

### ⬜ 3.3 · 选择审核版本
- 选 TestFlight 里最新且测过的 build
- Submit for Review → 选 "Manually release this version"（这样审核过了你按按钮才发布，避免半夜上架）

### ⬜ 3.4 · 等审核（24-72 小时）
- 90% 概率一次过
- 如果被拒：仔细读拒绝理由，最常见是隐私描述不清楚或截图不真实
- 修完重提交即可

---

## Phase 4 · 上架后 1-4 周（v1.0 → v1.1）

### ⬜ 4.1 · 接 MetricKit 崩溃报告（半天）
Apple 内置，不引第三方。在 SiteNoteApp 加：
```swift
// 监听崩溃和卡顿报告，自动发到你的邮箱或 webhook
import MetricKit
```
具体做法：写一个 `MetricSubscriber` 实现 `MXMetricManagerSubscriber`，把 `MXCrashDiagnostic` 转 JSON 邮件出去。

### ⬜ 4.2 · In-app 反馈表单（1 小时）
Settings 里加一个"反馈"按钮，点了用 `mailto:` 打开邮件 App 预填收件人 + App 版本 + iOS 版本。  
比"装个第三方 SDK 收反馈"省事 100 倍。

### ⬜ 4.3 · SiteNoteTests 接 Xcode test target（半天）
本轮没做。把 test target 加进 .xcodeproj，至少把 `NotificationService.computeSchedule` 那几个纯函数测起来。

### ⬜ 4.4 · SwiftData VersionedSchema + MigrationPlan（1 天）
现在 `Schema([Note.self, LogEntry.self, ShareLog.self])` 是无版本的。等你下次改 Note 字段，老用户升级就崩。  
最小改动：把 schema 包进 `VersionedSchema` v1，未来加字段时升 v2 写迁移代码。**不做这个 = 第一次改字段就要让所有用户重装**。

### ⬜ 4.5 · 备份 zip 的 restore 流程（半天-1 天）
现在能导出，导不回。最小做法：Settings → 导入 → 选 zip → 把 `_backup_meta/store/*` 复制回 Application Support → 重启 App。

### ⬜ 4.6 · C1 工种 / 机械汇总条（1-2 天）
你 memory 立的"真实工地核心缺口"。台账 mode 顶部加：
```
今日总账：
  人员：木工 4 · 钢筋工 6（合 10 人 · 80 工时）
  机械：挖机 2 台（共 7h 开机）
  事件：1 次停水（10:30-11:15）
```

### ⬜ 4.7 · 看用户行为
- 每周看一次 App Store Connect Analytics
- 关注：留存（D1/D7）、卸载率、崩溃率
- 留存 D7 < 20% = 有 onboarding 问题，看是哪步流失
- 崩溃率 > 0.5% = 紧急修

---

## Phase 5 · v2 再说（不要塞 v1）

按优先级：
1. omni-classify 链 + 建议确认 UI（你 memory 里 Phase A→B→C 的方向）
2. iCloud 同步（多设备）
3. 团队共享（一个工地多人）
4. 离线 AI 完全替代 OpenAI（Apple Intelligence on iOS 18+）

---

## 定价决策（写在这里方便你回头看）

**v1（前 3 个月）：完全免费**
- 目的：拿用户 + 反馈，不是收入
- BYOK（用户自带 OpenAI Key）的产品再加付费会双重收费感
- App Store 算法对免费友好，新 App 才有露出

**v1.1 加内购（达到 200+ 真用户后考虑）**
- 一次性买断 $4.99-$9.99 解锁专业版
- 专业版仅含：EOT 报告 + AI 高级功能 + 多工地
- **绝不**限制：录音条数 / 基础 PDF 导出 / 备份导出

**v2 转订阅（达到 1000+ 月活后考虑）**
- $2.99/月解锁多设备 iCloud 同步 + 团队共享
- 没人主动问"能不能多设备同步"就**不做**

---

## 关键不要做的事

❌ **上线前一周加新功能** — 稳定优先  
❌ **App 名带"AI"** — Apple 审查严格，容易被要求加"powered by OpenAI"  
❌ **截图用模拟器纯空白界面** — 必须真实数据 + 工地场景背景  
❌ **隐私政策含糊** — Apple 会拒  
❌ **预设过高目标** — 第一周下载 < 50 是常态，不代表失败  
❌ **看负评失眠** — 看反复抱怨的同一点，看一两个酸民别理  

---

## 行动顺序速查

```
本周一 1.1+1.2     Info.plist + 隐私政策
本周二 1.3+1.4     App Store Connect 应用资料 + Privacy Details
本周三 1.5+1.6     截图 + 描述
本周四 2.1         Archive + 上 TestFlight
本周五 2.3         邀请 3-5 个工地朋友
下周一-三 2.5       真用 + 收反馈
下周四 3.1+3.2     修 critical + 写 review notes
下周五 3.3         提交审核
下下周 4.x         迭代 v1.1
```

如果今天是第 1 天，理论上**第 14 天**可以上架。
