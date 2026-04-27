# SiteNote · 工地速记

> 给工程师 / 项目经理 / 工地主管用的语音速记 iOS App。
> 长按说话，AI 自动整理，一键导 PDF。

[官网](https://github.com/banruo) · [隐私政策](./PRIVACY_POLICY.md) · [架构](./ARCHITECTURE.md) · [上架攻略](./LAUNCH.md)

---

## 这是什么

一款**本地优先**的工地语音笔记 App。所有数据存你 iPhone 里。

- 🎤 长按麦克风说话，自动转文字
- 🤖 AI 抽出人员到场 / 机械进场 / 工程量 / 隐患（**仅当**用户启用 OpenAI BYOK）
- 📋 日志台账模式：当日"工时账"一目了然
- 📄 一键导 PDF 给业主、监理、律师
- 🚨 普通速记 7 天提醒，隐患 10 天双重提醒
- 📦 备份 ZIP（含数据库 + 音频 + 照片 + 设置）

---

## 技术栈

| 层 | 技术 |
|---|---|
| UI | SwiftUI |
| 数据 | SwiftData |
| 录音 | AVFoundation |
| 语音转写 | Apple SFSpeechRecognizer（本地）|
| AI 文本任务 | OpenAI（用户 BYOK）/ Apple Foundation Models（v1.1+）|
| 位置 | CoreLocation + MapKit |
| PDF | PDFKit |
| 通知 | UNUserNotificationCenter |
| 崩溃 | MetricKit（无第三方）|

**目标平台**：iOS 17+
**Xcode**：26.4+
**Swift**：5.0
**第三方依赖**：**无**（按 [`feedback_workflow` memory](#) 立的红线）

---

## 快速开始

### 编译

```bash
git clone <this-repo>
cd SiteNote
open SiteNote.xcodeproj
# Xcode → ⌘R 装真机
```

### 命令行 build verify

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme SiteNote \
  -destination 'generic/platform=iOS' \
  -configuration Debug build
```

---

## 项目结构

详见 [`ARCHITECTURE.md`](./ARCHITECTURE.md)。简化版：

```
SiteNote/
├── SiteNoteApp.swift           App 入口 + 三态启动（loading/ready/failed）
├── ContentView.swift           顶层 view 路由
├── Models/                     SwiftData 数据模型（Note / LogEntry / ShareLog）
├── Services/                   纯业务逻辑（Voice / AI / Notification / PDF / Backup）
├── ViewModels/                 状态翻译层（HomeViewModel 等）
├── Views/                      SwiftUI 屏幕
│   └── Components/             通用零件（按钮 / banner / 图钉）
└── Utils/                      工具（设置 / 解析 / Keychain）
```

---

## 开发规范

> 详见 [`feedback_workflow` memory](https://claude.ai/projects)（仅作者本地可见）

1. **不引第三方依赖**（Apple 自带够用）
2. **先规划再写代码**：每个新任务先列计划等确认
3. **小步推进**：写完一个模块停下让测试
4. **不过度设计**（YAGNI）
5. **`xcodebuild build` 验证后停下**，让用户在 Xcode 里 ⌘R 装真机测

---

## 文档

| 文件 | 用途 |
|---|---|
| [`README.md`](./README.md) | 本文件，项目快速入门 |
| [`ARCHITECTURE.md`](./ARCHITECTURE.md) | 架构速读手册 |
| [`LAUNCH.md`](./LAUNCH.md) | 上架攻略（21 项 checklist）|
| [`CHANGELOG.md`](./CHANGELOG.md) | 版本日志 |
| [`PRIVACY_POLICY.md`](./PRIVACY_POLICY.md) | 隐私政策（中英双语）|
| [`PRODUCT.md`](./PRODUCT.md) | 产品定位 |

---

## 开发者

**Banruo Yang** · [banruostudio@gmail.com](mailto:banruostudio@gmail.com)

工程师独立开发。专注一件事：把工地工程师从"打字记笔记"里解放出来。

---

## 许可

Copyright © 2026 Banruo Yang. All rights reserved.

未上架前代码不公开。上架后视情况开源核心模块。
