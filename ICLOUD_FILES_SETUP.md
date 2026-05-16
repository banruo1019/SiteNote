# ICLOUD_FILES_SETUP.md — iCloud Drive "SiteNote" 文件夹配置

让导出过的 PDF 报告**自动出现在 iPhone Files App → iCloud Drive → SiteNote 文件夹**(Mac 上同步看到)。

> ⚠️ 这跟 `ICLOUD_SETUP.md` 的 CloudKit (SwiftData 同步) 是**两套不同机制**:
> - CloudKit Private DB:你的速记 / 照片走系统级 sync,**Files App 看不到**
> - **iCloud Drive Documents Container**(这份文档):导出的 PDF 报告,Files App **能看到 + 能 share**
>
> 复用同一个 container ID `iCloud.com.banruo.SiteNote`,只是开启不同的 service。

---

## 当前状态(2026-05-16)

| 层 | 状态 |
|---|---|
| 代码:`ReportArchiveService` 双写逻辑 | ✅ 已写完(本地必有,iCloud 可选) |
| 代码:`SavedReportsView` "我的报告"页 | ✅ Engineer / PM 设置入口已加 |
| 代码:PDFExportView / InspectionFormView 自动归档 | ✅ 接通 |
| **Apple Developer 后台:CloudDocuments service** | ❌ 需要你开 |
| **Xcode capability:iCloud Documents** | ❌ 需要你勾 |
| **entitlements:`ubiquity-container-identifiers`** | ❌ 勾完 capability Xcode 自动加 |
| **Info.plist:`NSUbiquitousContainers`** | ❌ **需要你授权我改 pbxproj,或你自己改** |

**当前不动配置也能跑** —— 报告会归档到本地 `Application Support/Reports/`,在"我的报告"页能看到、能 share。**只是不会出现在 Files App**。

---

## 步骤 1:Apple Developer 后台

1. 打开 https://developer.apple.com/account/resources/identifiers/list/cloudContainer
2. 找到 `iCloud.com.banruo.SiteNote`(已存在,ICLOUD_SETUP.md 阶段创建过)
3. 不需要新增 — CloudKit container 自动也支持 Documents service,无独立开关

> 注:Apple 现在不区分"CloudKit container"和"Documents container"——是同一个 iCloud container,通过 entitlements 里开不同 service 来用。

---

## 步骤 2:Xcode capability

1. 打开 `SiteNote.xcodeproj`
2. 选 Project → Target `SiteNote` → **Signing & Capabilities**
3. 找已有的 **iCloud** capability(ICLOUD_SETUP.md 时已加)
4. 在 Services 列表勾上 **iCloud Documents**(已勾的 CloudKit 保留)
5. Containers 保留 `iCloud.com.banruo.SiteNote`(不需要再加新的)

勾完后,`SiteNote.entitlements` 应该多出:
```xml
<key>com.apple.developer.ubiquity-container-identifiers</key>
<array>
    <string>iCloud.com.banruo.SiteNote</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
    <string>CloudDocuments</string>   <!-- 新增 -->
</array>
```

---

## 步骤 3:Info.plist 加 `NSUbiquitousContainers`(决定 Files App 显示名)

**这是关键** —— 没有这步,文件会进 iCloud 容器,但 **Files App 不会显示**(Apple 的规则:必须显式声明才让用户看到)。

SiteNote 没有独立 Info.plist 文件(用的 Xcode 自动生成,key 写在 .pbxproj 的 `INFOPLIST_KEY_*` 字段)。**有两种做法**:

### 做法 A(推荐):新建 Info.plist 文件,在里面加这个 key

1. 在 Xcode 里 File → New → File → Property List,命名 `Info.plist`,加进 target SiteNote
2. 在 Target → Build Settings 里把 `INFOPLIST_FILE` 指到这个新文件
3. 把所有 `INFOPLIST_KEY_*`(NSCameraUsageDescription / NSMicrophoneUsageDescription 等)从 build settings 搬进这个 plist
4. 在 plist 里加:

```xml
<key>NSUbiquitousContainers</key>
<dict>
    <key>iCloud.com.banruo.SiteNote</key>
    <dict>
        <key>NSUbiquitousContainerIsDocumentScopePublic</key>
        <true/>
        <key>NSUbiquitousContainerName</key>
        <string>SiteNote</string>
        <key>NSUbiquitousContainerSupportedFolderLevels</key>
        <string>Any</string>
    </dict>
</dict>
```

### 做法 B(快):在 pbxproj 的 `INFOPLIST_KEY_*` 直接加(我可以做,等你授权)

Xcode 13+ 支持把 NSUbiquitousContainers 直接写在 build settings,但格式特殊(是嵌套 dict 不是简单字符串),pbxproj 里不一定能稳定 round-trip。

> 我推荐做法 A,长远稳定。pbxproj 里全是嵌套字典反而难维护。

---

## 步骤 4:验证

1. 卸载 App(清掉旧 sandbox)
2. 重装 → 启动 → 设置 → 我的报告 → 应该看到 "iCloud Files 同步已启用"
3. 导出一份 PDF 巡检日志 / SVR 报告
4. 打开 **Files App**(iPhone 自带)→ iCloud Drive → 应该有 **SiteNote** 文件夹 → 里面有刚导出的 PDF
5. Mac 上 Finder → iCloud Drive → SiteNote 也应该看得到(可能要等 1-2 分钟 sync)

---

## 步骤 5:常见问题

### Files App 没显示 SiteNote 文件夹
- 检查 `NSUbiquitousContainerIsDocumentScopePublic` 是否 `true`
- 检查 `NSUbiquitousContainerName` 是否设了
- 卸载重装(系统缓存了上次的元数据)
- iPhone 设置 → Apple ID → iCloud → iCloud Drive 是否开

### "我的报告"页显示 "iCloud Files 同步未启用"
- 检查 entitlements `CloudDocuments` 有没有加
- 检查 entitlements `ubiquity-container-identifiers` 有没有 `iCloud.com.banruo.SiteNote`
- 检查 iPhone 设置 → Apple ID 是否登录 + iCloud Drive 是否开

### 上传慢 / 没 sync
- 第一次的文件需要 1-5 分钟,看文件大小和网速
- 飞行模式 / 弱 WiFi 会阻断
- iPad / Mac 端 Files App 拉一下刷新

### 离线导出的 PDF 怎么办
- 本地永远有(`Application Support/Reports/`)
- 网恢复后系统自动补同步,不用手动重做

---

## 数据流向总结

```
用户点"导出 PDF"
    ↓
PDFExportService / InspectionReportPDFBuilder 生成 → temp 目录
    ↓
ReportArchiveService.archive(sourceURL:)
    ├─ 写入本地:<App Support>/Reports/<filename>.pdf  ← 必有
    └─ 镜像到 iCloud:<Ubiquity>/Documents/<filename>.pdf  ← 可选(配齐 capability 才有)
            ↓
        Apple 系统自动 sync 到 iCloud Drive
            ↓
        Files App / Finder 显示 SiteNote 文件夹
```

---

## 与其他 iCloud 路径的关系

| 用途 | 容器 / 路径 | 用户看得到吗 |
|---|---|---|
| SwiftData(Note / LogEntry / 照片) | CloudKit Private DB | ❌(只系统设置看大小) |
| 导出的 PDF 报告(这份文档) | Ubiquity Container Documents/ | ✅ Files App |
| 录音 / 照片原始文件 | App sandbox 本地 only | ✅ Files App "我的 iPhone" |
| 设备级 iCloud 备份 | iCloud Backup | ❌(只系统恢复整机用) |

---

**当前实际工作:**

✅ 代码层全部就绪,**现在就能跑**(只是不上 iCloud Drive)
⏸ Files App 同步需要你完成步骤 1-3
