# SiteNoteTests

这个文件夹里的测试文件**不会被主 App Target 编译**——因为主 App 的 `fileSystemSynchronizedGroups` 只扫 `SiteNote/` 目录。

## 怎么让这些测试跑起来

1. 打开 `SiteNote.xcodeproj`
2. **File → New → Target**
3. 选 **Unit Testing Bundle**
4. Product Name: `SiteNoteTests`
5. Target to be Tested: `SiteNote`
6. 完成后,Xcode 会帮你建一个默认的测试 target
7. 把这个目录下的 `.swift` 测试文件**拖进新建的 target**(勾选 Target Membership)
8. 删掉 Xcode 自动生成的空 `SiteNoteTests.swift`(如果冲突的话)
9. `Cmd + U` 跑测试

## 当前覆盖范围

- `ChineseDateParserTests.swift` — deadline 关键词推断、保存命令识别、语言错配检测
- `NotificationScheduleTests.swift` — 推送调度算法(纯函数 computeSchedule)的边界和逻辑正确性

## 哲学

只写**核心业务逻辑的纯函数**测试。UI / 异步流 / 文件系统 / 网络都不测——ROI 低。
