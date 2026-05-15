# SiteNote 操作手册 — 发布 v1.1

> 面向你(owner)。早上起床后照清单走,半小时内可以提交到 App Store Review。

---

## 0. 预备清单(发包前 5 分钟检查)

```bash
cd /Users/banruo/Developer/SiteNote

# 1. 干净的工作区
git status                     # 应该 clean,或者只有 docs untracked

# 2. 当前在 main 分支
git branch                     # * main

# 3. 最新 build
xcodebuild -scheme SiteNote -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build 2>&1 | grep -E "error:|BUILD" | tail -3
# 必须看到 ** BUILD SUCCEEDED **

# 4. 检查 overnight 改动
git log --oneline | head -20   # 看 [overnight #N] 一串 commit
```

---

## 1. 版本号 + Build Number 递增

当前版本号:`MARKETING_VERSION = 1.0`,`CURRENT_PROJECT_VERSION = 2`(build 2 已在 v1.0 上架)。

**v1.1 改动**:
- `MARKETING_VERSION` → `1.1`
- `CURRENT_PROJECT_VERSION` → `3`(每次上传都得 +1)

**操作**:
1. 打开 Xcode
2. 顶部选 SiteNote target → General
3. **Identity 段**:
   - Version: `1.0` → `1.1`
   - Build: `2` → `3`
4. Cmd+S 保存

或者 CLI(更快):

```bash
cd /Users/banruo/Developer/SiteNote
sed -i '' 's/MARKETING_VERSION = 1.0;/MARKETING_VERSION = 1.1;/g' SiteNote.xcodeproj/project.pbxproj
sed -i '' 's/CURRENT_PROJECT_VERSION = 2;/CURRENT_PROJECT_VERSION = 3;/g' SiteNote.xcodeproj/project.pbxproj
```

---

## 2. Xcode Archive(打包)

1. Xcode 顶栏 device 选择器 → 选 **Any iOS Device (arm64)**(不能选 Simulator,Simulator 不能 Archive 真机包)
2. 菜单 **Product → Archive**
3. 等编译 + 链接,约 2-5 分钟
4. **Organizer 自动弹出**,看到刚才的 Archive 在最上面,带今天日期

❗ 如果 Organizer 没弹:Xcode 菜单 **Window → Organizer → Archives tab**。

---

## 3. 上传到 App Store Connect

在 Organizer 里:
1. 选刚生成的 SiteNote 1.1 (3) archive
2. 点右侧 **Distribute App**
3. 选 **App Store Connect** → **Upload**
4. Distribution options:全默认(Strip Swift symbols ✓ / Upload symbols ✓ / Manage Version and Build Number off)
5. Signing:全默认(自动签名)
6. Review → Upload

等 1-3 分钟看到 "Upload Successful"。

---

## 4. App Store Connect 提交

打开浏览器 https://appstoreconnect.apple.com → 选 SiteNote app。

### 4.1 等 Processing
- TestFlight tab 看新 build,会显示 "Processing"
- 等 10-30 分钟,变成 "Ready to Submit"
- 期间会收到 Apple 邮件("Your build SiteNote (1.1) has completed processing")

### 4.2 准备 v1.1 版本

App Store tab → 左侧 + → **New Version** → 1.1 → 创建。

填写 What's New(中英文,内容从 `RELEASE_NOTES_v1.1.md` 抄):
- 简体中文必填
- 英文必填(US English)
- 其他语言可不填(继承)

### 4.3 截图

v1.1 主要 UI 变化:
- Engineer 全新 Settings 主页(简体)
- PM 主屏 stats filter 行为修复(看不出截图差异,跳过)
- PDF 报告新布局(可截一张内页)

建议至少更新 2-3 张主截图。规格:
- 6.7" iPhone:1290×2796px(iPhone 14 Pro Max / 15 Plus)
- 6.5" iPhone:1242×2688px

从 Simulator(iPhone 17 OS 26.5)截图 → Files app 拉到 Mac → 直接拖到 App Store Connect 截图槽。

### 4.4 选 Build
- 滚到 "Build" 段 → + → 选刚 upload 的 SiteNote 1.1 (3)
- Encryption:不变(继承 v1.0)

### 4.5 Submit
- 顶部右上 **Add for Review** → **Submit to App Review**
- Apple 答复时间:中位数 1-3 天

---

## 5. 本地运维 / 常见排错

### 清 DerivedData(build 卡死或代码改了不生效)
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/SiteNote-*
```

### 清模拟器数据(重置 SwiftData)
```bash
# 找当前 Simulator UUID
xcrun simctl list devices | grep "iPhone 17"
# 删指定模拟器的 app 数据(替换 UUID)
xcrun simctl uninstall <UUID> com.banruo.SiteNote
```

或在模拟器里:Settings app → General → Transfer or Reset → Erase All Content and Settings。

### 查 log
- Console.app(macOS 自带)→ 左侧选 simulator/真机 → 顶部搜索框输 `SiteNote`
- 或者 Xcode 跑时 Console pane 直接看 `print` 输出

### CoreSimulator 版本不对
如果 xcodebuild 报 "Simulator version X < Xcode Y":
```bash
sudo softwareupdate --install-rosetta --agree-to-license  # Apple Silicon 偶尔需要
# 通常需要 Xcode 自动更新 CoreSimulator,等 1-2 天
```

---

## 6. 紧急回滚

### 6.1 用户上线后报 crash,想退到 v1.0
- App Store Connect → App Store tab → 当前 v1.1 → **Remove from Sale**
- v1.0 不会自动回归(Apple 默认延续最后 ready 版本)
- 准备 v1.1.1 hotfix:Archive 新 build → 同上流程

### 6.2 想撤回 review(还没 approve)
- App Store Connect → 当前 1.1 (In Review) → **Reject this version**
- 修完代码 + Archive + Upload 新 build → Resubmit

### 6.3 本地 git 回滚 overnight 改动
```bash
# 看 overnight 之前的 checkpoint
git log --oneline | grep -v overnight | head -5
# 拿到那个 commit hash(假设 55f48e7)
git reset --hard 55f48e7
```

⚠️ `--hard` 会丢未 commit 的改动,先 `git status` 确认。

---

## 7. 检查清单(最后一遍)

提交前:

- [ ] `MARKETING_VERSION = 1.1` 和 `CURRENT_PROJECT_VERSION = 3` 都改了
- [ ] xcodebuild BUILD SUCCEEDED
- [ ] Archive 成功生成
- [ ] Organizer 显示 "Validated"(可选,Distribute App 前可点 Validate)
- [ ] Upload 成功,App Store Connect TestFlight 见 build
- [ ] 简中 + 英文 What's New 都填
- [ ] 至少 2 张新截图
- [ ] Build 已选到 1.1 版本
- [ ] Add for Review 点了

提交后:

- [ ] Apple 处理邮件收到
- [ ] 1-3 天内 Apple 答复(approve / reject)
- [ ] approve 后 → 选 Manual Release 还是 Auto Release(推荐 Manual,自己挑时间发)
- [ ] 朋友圈/Twitter/小红书发布预告

---

## 8. 这次 v1.1 的卖点(对外营销)

写营销文案时强调:
- ✨ Engineer 工程师专版:独立 4 Tab + 极简 Settings
- 📄 巡检报告新布局:A3 图纸大图 + 自适应照片网格 + 邮件发送自动归档
- 🧹 移除 Tradie 模式(简化角色,聚焦工程场景)
- 🐛 PM 主屏多项 UX 修复(stats filter / 命名统一 / 月度图表)

---

## 9. CloudKit 团队功能上线

v1.2 计划点亮 iCloud 同步 + 团队协作。**走这条线之前**必须按 [`ICLOUD_SETUP.md`](./ICLOUD_SETUP.md) 跑一遍完整清单,不能跳步。

关键节点速览:
- **发包前**:Apple Developer 后台必须先建 `iCloud.com.banruo.SiteNote` container,Xcode capability 链接成功
- **TestFlight 前**:两台真机双向同步 + conflict + 离线场景全部通过
- **上 App Store 前**:CloudKit Dashboard 把 Development schema **Deploy 到 Production**(漏这步 = TestFlight 能同步、正式版用户拿不到数据)
- **审核材料**:App 描述加 "iCloud 同步",Privacy nutrition label 补 iCloud 数据收集
- **回滚预案**:App 内 toggle 关闭 sync,本地 + 云端数据都保留,降级到 local-only 不丢数据

具体每一步、错误处理、团队邀请流程、常见问题排查 → 看 `ICLOUD_SETUP.md`。
