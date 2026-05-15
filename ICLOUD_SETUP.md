# SiteNote iCloud / CloudKit 启用清单

> 面向 owner(我)。按时间顺序走,每一步打勾再下一步。开启 iCloud 同步 + 团队功能的完整前置准备。

---

## 1. Xcode 加 iCloud capability

1. 打开 `SiteNote.xcodeproj`(双击 Finder 里的文件或 Xcode 菜单 File → Open Recent)
2. 左侧 Project Navigator → 选 SiteNote target(蓝色顶层 icon 下面那行)
3. 顶部 tab 切到 **Signing & Capabilities**
4. 左上角点 **+ Capability** 按钮
5. 弹窗里搜 "iCloud" → 双击添加
6. 在新出的 iCloud 段里:
   - 勾选 **CloudKit**(默认还有 Key-value storage,不需要可以不勾)
   - **Containers** 区域:点 + 按钮
   - 输入 `iCloud.com.banruo.SiteNote`(注意前缀 `iCloud.` 是 Xcode 自动加的,自己填的部分是 `com.banruo.SiteNote`)
   - 或者点 + 后等几秒,Xcode 会拉远端列表,直接勾选已存在的 container
7. Cmd+S 保存
8. 检查 `SiteNote/SiteNote.entitlements`(如果新建了)里有:
   - `com.apple.developer.icloud-container-identifiers` = `iCloud.com.banruo.SiteNote`
   - `com.apple.developer.icloud-services` = `CloudKit`

> ⚠️ 如果遇到 "Failed to register" 错误,先做第 2 步(Apple Developer 后台创建 container),回来再点 +。

---

## 2. Apple Developer 后台创建 iCloud Container

1. 浏览器打开 https://developer.apple.com/account/resources/identifiers/list/cloudContainer
2. 左上角下拉确认在 **iCloud Containers** 类型
3. 右上角 **+** 新建:
   - **Description**: `SiteNote`
   - **Identifier**: `iCloud.com.banruo.SiteNote`(全小写,前缀固定)
4. **Continue** → **Register** → 完成
5. 回 Identifiers 列表,左上切到 **App IDs**
6. 找到 `com.banruo.SiteNote` 点进去
7. **Capabilities** 段滚到 **iCloud** 一行,勾上(如果没勾)
8. 右侧出现 **Edit** 按钮,点 Edit:
   - 选择 **Include CloudKit support**
   - 勾选刚建的 `iCloud.com.banruo.SiteNote` container
9. **Save**
10. 回 Xcode → Signing & Capabilities → 点 container 右边的刷新按钮(或重新打开项目),确认链接成功

> ⚠️ **Container 一旦创建不能改名,只能 deprecate**。命名前想清楚,SiteNote 这个名字打算长期用就放心建。

---

## 3. CloudKit Dashboard 配 schema

1. 浏览器打开 https://icloud.developer.apple.com/dashboard/database
2. 用 Apple Developer 账号登录(同 App Store Connect 那个)
3. 左上 container 下拉 → 选 `iCloud.com.banruo.SiteNote`
4. 左侧导航 **Schema → Record Types**:
   - 首次进来是空的
   - SwiftData 用 `@Model` 标注的类会在 App **首次启动并写入数据时**自动推导 Record Type 到 Development 环境
   - 不需要手动建 Record Type
5. **Indexes**(可选,后期性能优化用):
   - 给常查询字段(如 `Note.updatedAt`、`Note.siteId`)加 queryable index
6. **Security Roles**:默认 `_creator` / `_world` 不动
7. 上线前要做 **Deploy Schema to Production**:
   - Schema → 右上 **Deploy Schema Changes...**
   - 把 Development 环境的 schema 推到 Production
   - ⚠️ Production schema 字段也只能加不能删

8. 数据验证:
   - Data → Records → 选 Record Type → 看是否有真实数据生成
   - 测试 confirmed 后再上 TestFlight

---

## 4. App 里启用 sync

两种方式:

### 4.1 用户在 App 内开启(推荐,正式版)
- 设置 → 数据 → **启用 iCloud 同步** toggle(需要后续 PR 加这个 UI)
- 关 toggle 立即停止 sync,但本地 + 云端数据都保留

### 4.2 代码里直接打开(开发期)
```swift
ICloudSyncConfig.shared.isEnabled = true
```
- 改完 App 重启
- SwiftData 的 `ModelConfiguration(cloudKitDatabase: .private("iCloud.com.banruo.SiteNote"))` 会触发首次 sync
- Console 看 `NSPersistentCloudKitContainer` 日志

---

## 5. 真机测试清单

**前置**:两台 iPhone,登录**同一 Apple ID**,且都已 Settings → Apple ID → iCloud → SiteNote 开启。

1. iPhone A:
   - 打开 SiteNote
   - 创建 3 条 Note(带照片、文字、GPS)
   - 创建 1 个 Site
2. **等 1-5 分钟**(CloudKit sync 有延迟,不是即时)
3. iPhone B:
   - 安装 SiteNote(TestFlight 或 Xcode 拖装)
   - 第一次打开,等 30s-2min 拉云端数据
   - 看 Note 和 Site 是否完整出现(含照片缩略图)
4. **Conflict 测试**(last-write-wins):
   - A 和 B 都打开同一条 Note 详情
   - A 改文字保存
   - B 改不同文字保存
   - 等 1 分钟,两端应该都收敛到 B 的版本(B 是后写的)
5. **离线测试**:
   - A 飞行模式,改 Note
   - B 飞行模式,改同一条 Note
   - A 解除飞行,等 sync
   - B 解除飞行,等 sync
   - 最终应该是 B 的版本(B 更晚 ack 到 cloud)

记录每一步的耗时,后期优化用。

---

## 6. 回滚步骤

如果同步出问题或想关掉:

1. App 内 toggle:**设置 → 数据 → 关闭 iCloud 同步**
2. 或代码:`ICloudSyncConfig.shared.isEnabled = false`
3. App 重启,SwiftData 切回 local-only `ModelConfiguration`
4. **数据保留**:本地 store 文件 + iCloud 数据都不删
5. 想完全清云端:CloudKit Dashboard → Data → Reset Development Environment(只清 dev,production 谨慎操作)
6. 用户侧清:Settings → Apple ID → iCloud → Manage Account Storage → SiteNote → Delete Data

---

## 7. 团队功能(Phase 2 完成后)

> 依赖 CloudKit Sharing(`CKShare`)+ 后续 PR 实现的团队 UI。

1. 设置 → 团队 → **创建团队**
2. 输入团队名,选项目颜色 / icon
3. **邀请** → 输入对方 iCloud 邮箱(必须是 Apple ID 邮箱,不是 SiteNote 注册邮箱)
4. App 生成 CloudKit share URL(`https://www.icloud.com/share/...`)
5. 通过 iMessage / 微信 / 邮件发给对方
6. 对方点链接:
   - iOS 自动打开 SiteNote(如果装了)
   - 提示"接受加入团队"
   - 点接受,自动同步该团队的 Note / Site
7. 权限管理:
   - 创建人 = owner,可以踢人
   - 受邀人 = participant,默认 read-write(可改 read-only)

---

## 8. 常见问题

### App 启动崩 / SwiftData migration 失败
- 错误信息常见:`CloudKit requires default values for all attributes`
- 原因:`@Model` 的字段必须**全部 optional 或有 default value**
- 修法:看 console 报哪个字段,改 `var x: String?` 或 `var x: String = ""`

### Sync 不工作 / 数据不出现
- 检查:Settings → Apple ID → iCloud → 滚到底,SiteNote 是否在 list 且开启
- 检查:iCloud 存储有没有满(免费 5GB 上限)
- 检查:网络(Wi-Fi 或蜂窝)
- Console 搜 `NSPersistentCloudKitContainer` 看 error
- 强制 push:App 改一条 Note 保存,**回主屏停留 30s**,再切回 App

### 第一次 sync 卡很久
- Apple 服务器有时慢,**等 10-15 分钟**
- 大量数据(>100 条 Note + 照片)首次 sync 可能需要 30 分钟
- 后续增量 sync 通常 5-30 秒

### Schema mismatch(Development vs Production)
- TestFlight 用户报"找不到数据" → 八成是 Production schema 没 deploy
- 修法:CloudKit Dashboard → Schema → Deploy Schema Changes

### Container 名字打错了怎么办
- Container 一旦创建不能改名
- 只能新建一个,旧的 deprecate
- App 改 entitlements + Xcode capability 指向新 container
- 旧 container 数据迁不过去,**只能在 dev 阶段折腾,正式上线后绝不能改**

---

## 9. 上线 Checklist

启用 CloudKit 提交 App Store 之前过一遍:

- [ ] App ID `com.banruo.SiteNote` Capabilities 里 iCloud + CloudKit 都勾上
- [ ] Container `iCloud.com.banruo.SiteNote` 创建完成
- [ ] Xcode Signing & Capabilities 里 iCloud + CloudKit + container 链接 OK
- [ ] `SiteNote.entitlements` 文件含 `com.apple.developer.icloud-services = CloudKit`
- [ ] 至少两台真机同 Apple ID 双向同步测试通过
- [ ] Conflict / 离线 / Re-online 三个场景都测过
- [ ] CloudKit Dashboard 已 Deploy Schema to Production
- [ ] App 内有"启用 iCloud 同步" toggle(默认关 or 开看决策)
- [ ] Privacy nutrition label 里加 iCloud 数据收集声明
- [ ] App Store Connect 描述里提一句 "支持 iCloud 同步"

---

## 10. 参考链接

- Apple Doc: [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- Apple Doc: [Sharing CloudKit data with other iCloud users](https://developer.apple.com/documentation/cloudkit/shared_records/sharing_cloudkit_data_with_other_icloud_users)
- WWDC23: [Meet SwiftData](https://developer.apple.com/videos/play/wwdc2023/10187/)
- WWDC23: [Model your schema with SwiftData](https://developer.apple.com/videos/play/wwdc2023/10195/)
