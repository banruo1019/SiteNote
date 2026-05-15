# Obsidian Vault 迁移决策

> **状态**：决策文档（**未执行**）
> **诉求**：用户希望把 Obsidian vault `construction-pm` 放到 `~/Developer/SiteNote/`（"软件开发"目录）下方便统一管理。
> **结论**：**推荐方案 B（软链接）**。原 vault 保留在 iCloud Drive 不动,在 `~/Developer/SiteNote/obsidian-vault` 创建 symlink 指过去 —— iCloud 同步不断,开发目录也能直接 `cd` 进去。
> **本文档不会执行任何文件操作**,所有 shell 命令需用户手动确认后再跑。

---

## 1. 当前 vault 路径机制

### 1.1 真实的 vault 在哪里

实地探查（只读,未改动）：

| 位置 | 说明 |
|---|---|
| `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/construction-pm/` | **真正的 Obsidian vault**(35 MB+,含 `00_Inbox`、`01_Projects` ... `10_AI_Workspace`、`.obsidian` 配置)。这是 iOS Obsidian 和 Mac Obsidian 共享同步的源头。 |
| `~/construction-pm/` | **不是 vault**,是与 vault 配套的 **代码仓库**(含 `.git`、`.env`、`intake.py` 之类 watchdog 脚本)。**不需要迁移**。 |
| `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/软件开发/` | **另一个独立 vault**(用户已有的 dev-notes vault)。**与 construction-pm 无关,不要混淆**。 |

### 1.2 SiteNote iOS App 怎么记住 vault 路径

iOS 端 **完全不写死路径**,机制如下(代码出处:`SiteNote/Services/ObsidianExportService.swift:45-91`):

1. 用户首次进 **Settings → 报告与导出 → Obsidian 同步 → "导出文件夹"**,弹出 `fileImporter`(iOS Files App)。
2. 用户在 Files App 里导航到 `iCloud Drive → Obsidian → construction-pm → 00_Inbox`,点"打开"。
3. App 调 `ObsidianExportService.persistFolder(url)`,把 URL 序列化成 **security-scoped bookmark Data**,存进 `UserDefaults`:
   - Key `settings.obsidian.exportFolderBookmark` — bookmark Data(沙盒必需)
   - Key `settings.obsidian.exportFolderPath` — 可读 path 字符串(只给 UI 显示)
4. 后续导出调 `resolveFolder()` 反序列化 bookmark 回 URL,包在 `startAccessingSecurityScopedResource()` 里写文件。

**关键含义**：
- iOS 端 **没有任何硬编码路径**。换路径只需在 App 里重新点一次"选文件夹"。
- bookmark 是 **绑定 inode** 的,**用户重命名 iCloud Drive 文件夹会让 bookmark stale**,App 会自动清掉,要求用户重选(代码 line 82-86)。
- Mac 端 watchdog(`intake.py`,在 `~/construction-pm/`)用的是 **写死的 vault 路径**(从 `.env` 读),需要单独改。

### 1.3 与 Mac/iOS 的依赖关系

```
                              ┌─ iOS SiteNote App
                              │   (UserDefaults bookmark,
                              │    用户运行时选)
                              │
~/Library/Mobile Documents/iCloud~md~obsidian/Documents/construction-pm/
   ↑ 真实 vault                │
   │                          ├─ Mac Obsidian App
   │                          │   (Obsidian 自己存的 vault path,
   │                          │    一般在 ~/Library/Application Support/obsidian)
   │                          │
   │                          ├─ ~/construction-pm/.env
   │                          │   VAULT_PATH=... (intake.py 读)
   │                          │
   │                          └─ iCloud 同步(iOS Obsidian / 备份)
   │
~/Developer/SiteNote/obsidian-vault  ← 软链接(方案 B 的目标)
```

---

## 2. 三个方案对比

### 方案 A：直接 `mv` + 改各端配置（不推荐）

**操作**：把 vault 整个搬出 iCloud Drive,放到 `~/Developer/SiteNote/obsidian-vault/`。

**问题**：
- **断 iCloud 同步**。iOS Obsidian / iPad / 别的 Mac 全部失联,vault 各端分叉。
- iOS SiteNote App 的 security-scoped bookmark **不能跨出 iCloud Drive**(沙盒限制)。
  搬走后 App 再选这个文件夹会失败 —— 因为 `~/Developer/...` 不在 App 沙盒可见空间里。
  必须用 iCloud Drive 路径或 App Group。
- Mac Obsidian / `intake.py` / 备份脚本 **全部要改路径**。
- 一旦再想回去同步,数据已分叉,合并代价高。

**结论**:**不推荐**。除非用户明确不再用 iCloud 同步、不再用 iOS Obsidian。

---

### 方案 B：软链接 `ln -s`（**推荐**）

**核心思路**：vault 真身留在 iCloud Drive,在 `~/Developer/SiteNote/` 下放个 symlink 指过去。

```
~/Developer/SiteNote/obsidian-vault  ──symlink──>  ~/Library/Mobile Documents/iCloud~md~obsidian/Documents/construction-pm
```

**好处**：
- iCloud 同步**完全不动**,iOS Obsidian / 别的 Mac / 备份全部继续工作。
- iOS SiteNote App 的 bookmark **不用改**(它指的是 iCloud Drive 真路径,symlink 是 Mac 本地的快捷方式)。
- Mac 端 `cd ~/Developer/SiteNote/obsidian-vault` 直接进 vault,`ls`、`grep`、`find` 全部正常工作。
- 把 vault 加入"软件开发"目录的 IDE workspace / VSCode multi-root / Cursor 索引 也没问题。
- `intake.py` 不用动(它读 `.env` 的真实路径,本来就指 iCloud)。
- **零数据风险,可随时 `rm` 删掉 symlink 回退**。

**唯一注意**：
- `git status` 等命令在 symlink 下能正常工作,但 `git init` 在 symlink 内部新建仓 偶尔会有怪行为 —— vault 内已经不放 git 仓(`~/construction-pm` 是独立 repo),所以不冲突。
- macOS Spotlight / Time Machine **不重复索引** symlink 目标,放心。

---

### 方案 C：双向同步（`rsync` / Syncthing,不推荐）

**操作**：在 iCloud vault 和 `~/Developer/SiteNote/obsidian-vault/` 之间用 `rsync` / launchd 定时双向同步。

**问题**：
- 双向同步 + iOS 也在写 = **三方写冲突**,Obsidian 不喜欢双 writer。
- 维护成本高(写 launchd plist、查日志、处理冲突文件)。
- 没解决任何方案 B 解决不了的问题。

**结论**:**不推荐**。

---

## 3. 推荐方案 B 的执行步骤（用户手动跑）

> **下列命令请用户自己在终端复制运行**。本文档**没有执行**。

### 3.1 前置检查

```bash
# 确认源 vault 存在且是预期的目录
ls -la "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/construction-pm" | head -5

# 确认目标位置还没东西占着
ls -la "$HOME/Developer/SiteNote/obsidian-vault" 2>/dev/null && echo "已存在,先决定怎么处理" || echo "目标位置干净,可建 symlink"
```

### 3.2 关 Mac Obsidian(避免 sync 冲突)

手动:Cmd+Q 退出 Obsidian.app。

### 3.3 建立 symlink

```bash
ln -s "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/construction-pm" \
      "$HOME/Developer/SiteNote/obsidian-vault"
```

### 3.4 验证

```bash
# 应该看到一个 -> 指向 iCloud 的箭头
ls -la "$HOME/Developer/SiteNote/obsidian-vault"

# 应该能列出 vault 内容
ls "$HOME/Developer/SiteNote/obsidian-vault/" | head -10

# 应该看到 00_Inbox / 01_Projects 等
ls "$HOME/Developer/SiteNote/obsidian-vault/00_Inbox" 2>/dev/null | head -5
```

### 3.5 把"软件开发"目录加进 IDE workspace（可选）

VSCode / Cursor:`File → Add Folder to Workspace → ~/Developer/SiteNote/obsidian-vault`(底层走 symlink,正常工作)。

### 3.6 重新打开 Obsidian

直接打开,vault 路径没变,正常加载。

### 3.7 回退方案(如果后悔)

```bash
rm "$HOME/Developer/SiteNote/obsidian-vault"
```

**只删 symlink,不动 vault 真身**。

---

## 4. 风险登记

| 风险 | 严重度 | 缓解 |
|---|---|---|
| 用户误以为 symlink 是真目录,直接 `rm -rf obsidian-vault` | **高** | `rm` 一个 symlink 只删链接(macOS 行为),但 `rm -rf` 在某些 shell 设置下会跟链接走 —— **用户操作前要心里有数,bash 默认是安全的**。 |
| iOS SiteNote App 重启后 bookmark 失效 | 低 | bookmark 指 iCloud 路径没变,不受 symlink 影响。即便失效,App 会提示重选,在 Files App 里走 iCloud Drive → Obsidian → construction-pm 重新点一次即可。 |
| Mac 重装系统 | 低 | symlink 不在 Time Machine 还原范围内,重装后用户手跑一次 3.3 步即可恢复。 |
| `~/Developer/SiteNote/` 被 git 当成根仓库,把 symlink commit 进去 | 中 | `.gitignore` 加一行 `obsidian-vault`(下方有 todo)。 |
| iOS App fileImporter 限制 | 已规避 | 方案 B 不动 iCloud 真路径,App 端零改动。 |

---

## 5. 配套 todos(用户确认后执行,本次不动)

1. `.gitignore` 加一行 `obsidian-vault`(本次没改,因为不知道用户最终选哪个方案)。
2. 如果将来 iOS App 想"自动判断 vault 是否在 dev 目录",可调用 `ObsidianExportService.symlinkVaultToDevDir()` 这个新加的 **占位方法**(只是文档/常量,不执行 shell —— 见代码注释)。

---

## 6. 我的最终建议

**跑方案 B 的 3.1–3.4 命令,5 分钟搞定,零数据风险**。
方案 A、C 都要解决的副作用比它们带来的"整洁感"贵得多 —— B 已经把"开发目录能看到 vault"这一个目标做到了。

如需我帮你执行 3.3 的 `ln -s` 命令,**请明确回复"执行 B"**,我才会动你的文件系统。
