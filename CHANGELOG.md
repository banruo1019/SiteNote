# SiteNote 版本日志

> 只记**用户感知到的变化**。代码内部重构在 git log 里看。

---

## v1.0.0 · 首次发布（待审核）

**预计上架日期**：2026-05-XX（看 App 审核进度）

### 核心功能
- 长按麦克风录音速记，自动转文字
- 智能提醒：普通速记 7 天，隐患 10 天双提醒
- 工地自动关联（基于 GPS）
- AI 抽取人员/机械/工程量（**可选**，需用户提供 OpenAI Key）
- 一键导出施工日志 PDF
- EOT 工期延误证据 PDF
- 数据完全本地存储
- 备份 ZIP（含 SwiftData + UserDefaults + 音频 + 照片 + 设置）
- 一键清空所有内容（含 3 秒倒计时撤销）
- 启动失败友好降级（重试 / 导诊断包 / 重置数据库）

### 隐私
- 无埋点、无追踪
- 仅在用户主动启用 OpenAI 时数据离开设备
- Privacy Manifest 已声明所有 required reason API
- 5 个 Usage Description 明确说明数据去向

### 已知限制
- iCloud 多设备同步：v2 计划
- 团队协作：v2 计划
- iPhone 主屏 icon 标准尺寸：v1.1 补
- 完整 VoiceOver Accessibility 覆盖：v1 仅核心 5 个按钮

---

## 历次代码改动（commit 跨度大的）

### 2026-04-26 · 多 Agent 上架代码准备
- Privacy Manifest（PrivacyInfo.xcprivacy）
- ITSAppUsesNonExemptEncryption 豁免
- In-app 反馈邮件按钮
- MetricKit CrashReporter 骨架
- 5 个核心按钮 VoiceOver labels
- 移除 unused Image.imageset（-1.3 MB）

### 2026-04-25 · Codex Review Fix + R3 启动降级
- 通知调度异步化 + 授权门 + 防竞态 token
- LogEntryIngestor 不再静默 cancel/标 diary，改建议式 banner（FIFO 队列）
- AI 失败可见性（AIFailureTracker + AIStatusBar 红条）
- 备份 zip 含 SwiftData store + UserDefaults
- nukeEverything 补 LogEntry/ShareLog/JargonStorage
- "施工日记" UI 字符串统一改为"施工日志"
- 三 tab 顶部"今日简报"按钮全删（保留台账内简报）
- SwiftData fatalError 改 DatabaseRecoveryView
- DiaryConversionTracker 单条改 FIFO 队列
- inFlightSchedules 字典自清（gen counter）

### 2026-04-25 · P0 整改 12/12（commit `596df3b`）
- 详见该 commit message

---

## 协议

非二进制版本号约定：
- **MAJOR** 增 = 数据格式不兼容（要写 SwiftData migration）
- **MINOR** 增 = 加新功能（向后兼容）
- **PATCH** 增 = 修 bug

---

[GitHub](https://github.com/banruo) · [反馈](mailto:banruostudio@gmail.com)
